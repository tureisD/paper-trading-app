import 'package:flutter/material.dart';

import '../../analytics/equity_curve.dart';
import '../../analytics/equity_snapshot_repository.dart';
import '../../analytics/portfolio_analytics.dart';
import '../../analytics/trade_stats.dart';
import '../../core/format.dart';
import '../../data/ledger_repository.dart';
import '../../data/settings_store.dart';
import '../../design/theme_controller.dart';
import '../../market/asset_class.dart';
import '../../market/instrument_repository.dart';
import '../../market/live_quotes.dart';
import '../../market/market_data_service.dart';
import '../../market/models/instrument.dart';
import '../../market/models/quote.dart';
import '../../market/providers/market_data_provider.dart';
import '../../market/quote_repository.dart';
import '../../sync/sync_engine.dart';
import '../../trading/order.dart';
import '../../trading/fee_model.dart';
import '../../trading/account_repository.dart';
import '../../trading/portfolio.dart';
import '../../trading/portfolio_engine.dart';
import '../../trading/trading_engine.dart';
import '../../design/layout.dart';
import '../../design/tokens.dart';
import '../common/primitives.dart';
import '../settings/settings_dialog.dart';
import '../trade/order_ticket.dart';
import 'equity_chart.dart';

/// Tab 1 — account summary, holdings table and analytics (roadmap Phase 5).
class PortfolioTab extends StatefulWidget {
  const PortfolioTab({
    super.key,
    required this.databasePath,
    required this.ledger,
    required this.instruments,
    required this.quotes,
    required this.marketData,
    required this.engine,
    required this.snapshots,
    required this.liveQuotes,
    required this.syncEngine,
    required this.syncOutcome,
    required this.pendingSync,
    required this.onOpenSync,
    required this.onSyncNow,
    required this.onDeposit,
    required this.settings,
    required this.theme,
    required this.accounts,
    required this.accountId,
    required this.accountName,
    required this.onAccountChanged,
  });

  final String databasePath;
  final LedgerRepository ledger;
  final InstrumentRepository instruments;
  final QuoteRepository quotes;
  final MarketDataService marketData;
  final TradingEngine engine;
  final EquitySnapshotRepository snapshots;
  final LiveQuoteService liveQuotes;
  final SyncEngine syncEngine;
  final SyncOutcome? syncOutcome;
  final int pendingSync;
  final VoidCallback onOpenSync;
  final VoidCallback onSyncNow;
  final VoidCallback onDeposit;
  final SettingsStore settings;
  final ThemeController theme;
  final AccountRepository accounts;
  final String accountId;
  final String accountName;
  final ValueChanged<String> onAccountChanged;

  @override
  State<PortfolioTab> createState() => PortfolioTabState();
}

class PortfolioTabState extends State<PortfolioTab> {
  CurveRange _range = CurveRange.all;
  bool _marking = false;
  String? _markError;
  DateTime? _lastReload;
  int _reloadedQuotes = 0;

  @override
  void initState() {
    super.initState();
    // Rebuild at most once per coalesced batch, never per tick.
    widget.liveQuotes.addListener(_onLiveQuotes);
    // Price the book on first display, when there is something to price.
    WidgetsBinding.instance.addPostFrameCallback((_) => reloadPrices());
  }

  @override
  void dispose() {
    widget.liveQuotes.removeListener(_onLiveQuotes);
    super.dispose();
  }

  void _onLiveQuotes() {
    if (mounted) setState(() {});
  }

  /// Fetches fresh prices for everything held, records today's valuation and
  /// rebuilds the derived numbers. Bound to the RELOAD button and `F5`.
  Future<void> reloadPrices() async {
    if (_marking) return;

    final state =
        PortfolioEngine.replay(widget.ledger.all(accountId: widget.accountId));
    final instruments = <Instrument>[];
    for (final position in state.openPositions) {
      final instrument = widget.instruments.get(position.symbol);
      if (instrument != null) instruments.add(instrument);
    }

    setState(() {
      _marking = true;
      _markError = null;
    });

    var fetched = 0;
    try {
      if (instruments.isNotEmpty) {
        final quotes = await widget.marketData.refreshQuotes(instruments);
        fetched = quotes.length;
        if (fetched == 0) {
          throw MarketDataException(
            'No quotes came back for ${instruments.length} '
            '${instruments.length == 1 ? 'holding' : 'holdings'}',
            source: 'reload',
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _lastReload = DateTime.now();
        _reloadedQuotes = fetched;
      });
      _recordSnapshot();
    } on MarketDataException catch (e) {
      if (mounted) setState(() => _markError = e.toString());
    } catch (e) {
      if (mounted) setState(() => _markError = 'Price refresh failed: $e');
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  PortfolioAnalytics _buildAnalytics(
    PortfolioSnapshot snapshot,
    Map<String, Quote> quoteMap,
  ) {
    final instruments = <String, Instrument>{};
    final bonds = <String, BondDetails>{};
    for (final position in snapshot.openPositions) {
      final instrument = widget.instruments.get(position.symbol);
      if (instrument != null) instruments[position.symbol] = instrument;
      final bond = widget.instruments.bondDetails(position.symbol);
      if (bond != null) bonds[position.symbol] = bond;
    }
    return PortfolioAnalyticsBuilder.build(
      snapshot: snapshot,
      instruments: instruments,
      quotes: quoteMap,
      bonds: bonds,
      netDeposits: widget.ledger.netDeposits(accountId: widget.accountId),
    );
  }

  /// Half of a position, snapped down to a valid lot size.
  static double _halfPosition(HoldingView holding) {
    final step = FeeModel.quantityStep(holding.assetClass);
    final units = ((holding.quantity / 2) / step).floorToDouble();
    return units <= 0 ? holding.quantity : units * step;
  }

  Future<void> _openSettings() async {
    await showSettingsDialog(
      context,
      settings: widget.settings,
      theme: widget.theme,
      ledger: widget.ledger,
      accounts: widget.accounts,
      accountId: widget.accountId,
      accountName: widget.accountName,
      onAccountChanged: widget.onAccountChanged,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    if (mounted) setState(() {});
  }

  /// Quick trade from a holdings row: pre-fills side and size.
  Future<void> _quickTrade(
    HoldingView holding,
    OrderSide side,
    double? quantity,
  ) async {
    final instrument = widget.instruments.get(holding.symbol);
    if (instrument == null) {
      setState(() => _markError = 'No catalog entry for ${holding.symbol}');
      return;
    }
    final result = await showOrderTicket(
      context,
      engine: widget.engine,
      marketData: widget.marketData,
      quotes: widget.quotes,
      instrument: instrument,
      initialSide: side,
      initialQuantity: quantity,
    );
    if (!mounted) return;
    setState(() {});
    _recordSnapshot();
    if (result != null) {
      final message = result.isFilled
          ? 'FILLED ${result.order.side.wire} '
              '${formatQuantity(result.order.quantity)} ${instrument.symbol}'
          : result.status.isWorking
              ? '${result.order.side.wire} ${formatQuantity(result.order.quantity)} '
                  '${instrument.symbol} resting'
              : (result.rejectionReason ?? 'Order rejected');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.raisedDark,
          content: Text(
            message,
            style: AppTypography.mono(
              size: 12,
              color: result.isRejected ? AppColors.negative : AppColors.textPrimaryDark,
            ),
          ),
        ),
      );
    }
  }

  /// Upserts today's marked-to-market valuation so the equity curve grows into
  /// a true daily history.
  void _recordSnapshot() {
    final state = PortfolioEngine.replay(widget.ledger.all(accountId: widget.accountId));
    final symbols =
        state.openPositions.map((p) => p.symbol).toList(growable: false);
    final analytics = _buildAnalytics(state, widget.quotes.getMany(symbols));
    widget.snapshots.record(
      accountId: widget.accountId,
      at: DateTime.now().toUtc(),
      netLiquidation: analytics.netLiquidation,
      cash: analytics.cash,
      marketValue: analytics.marketValue,
      realisedPnl: analytics.realisedPnl,
      unrealisedPnl: analytics.unrealisedPnl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final events = widget.ledger.all(accountId: widget.accountId);
    final snapshot = PortfolioEngine.replay(events);
    final heldSymbols =
        snapshot.openPositions.map((p) => p.symbol).toList(growable: false);
    final quoteMap = widget.quotes.getMany(heldSymbols);

    final analytics = _buildAnalytics(snapshot, quoteMap);

    // Prefer recorded daily marks; fall back to the ledger curve until at least
    // two days have been snapshotted.
    final recorded = widget.snapshots.all(accountId: widget.accountId);
    final livePrices = <String, double>{
      for (final quote in quoteMap.values) quote.symbol: quote.price,
    };
    final fullCurve = recorded.length >= 2
        ? EquityCurve.fromSnapshots(recorded)
        : EquityCurve.fromLedger(events, livePrices: livePrices);
    final curve = EquityCurve.filter(fullCurve, _range);

    // Risk-free proxy: a short-dated sovereign yield when one is cached.
    final riskFreeAnnual = (widget.quotes.get('DGS1MO')?.price ??
            widget.quotes.get('DTB3')?.price ??
            0.0) /
        100.0;
    final metrics = CurveMetrics.compute(
      curve,
      riskFreeRateAnnual: riskFreeAnnual,
    );
    final stats = TradeStats.fromRealisations(
      TradeStats.realisedTrades(events),
    );

    return SingleChildScrollView(
      padding: PagePadding.of(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _summary(analytics),
          const SizedBox(height: AppSpacing.lg),
          _holdings(analytics),
          const SizedBox(height: AppSpacing.lg),
          _analytics(curve, metrics, stats, analytics),
          const SizedBox(height: AppSpacing.lg),
          _syncPanel(),
          const SizedBox(height: AppSpacing.lg),
          _enginePanel(),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Account summary
  // -------------------------------------------------------------------------

  /// The account headline metrics, as a list so they can wrap on phones.
  List<Widget> _statBlocks(PortfolioAnalytics analytics) => <Widget>[
        StatBlock(
          label: 'NET LIQUIDATION VALUE',
          value: formatMoney(analytics.netLiquidation),
          valueSize: 22,
        ),
        StatBlock(
          label: 'DAY P&L',
          value: formatMoney(analytics.dayPnl),
          sub: _signedPercent(analytics.dayPnlPercent),
          valueColor: _pnlColour(analytics.dayPnl),
          subColor: _pnlColour(analytics.dayPnl),
        ),
        StatBlock(
          label: 'TOTAL P&L',
          value: formatMoney(analytics.totalPnl),
          sub: _signedPercent(analytics.totalPnlPercent),
          valueColor: _pnlColour(analytics.totalPnl),
          subColor: _pnlColour(analytics.totalPnl),
        ),
        StatBlock(
          label: 'BUYING POWER',
          value: formatMoney(analytics.buyingPower),
        ),
        StatBlock(
          label: 'ACCRUED INTEREST',
          value: formatMoney(analytics.accruedInterestReceivable),
        ),
      ];

  List<Widget> _actions() => <Widget>[
        GhostButton(
          label: _marking ? 'RELOADING…' : 'RELOAD',
          accent: AppColors.focus,
          onPressed: _marking ? () {} : reloadPrices,
        ),
        GhostButton(label: 'DEPOSIT', onPressed: widget.onDeposit),
        GhostButton(label: 'SETTINGS', onPressed: _openSettings),
      ];

  Widget _summary(PortfolioAnalytics analytics) {
    final compact = Breakpoints.isCompact(context);
    final stats = _statBlocks(analytics);

    return Panel(
      title: 'ACCOUNT • ${widget.accountName.toUpperCase()}',
      trailing: compact
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: _actions()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (compact) ...[
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: _actions(),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (compact)
            LayoutBuilder(
              builder: (context, constraints) {
                final columnWidth =
                    (constraints.maxWidth - AppSpacing.md) / 2;
                return Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: [
                    for (final stat in stats)
                      SizedBox(width: columnWidth, child: stat),
                  ],
                );
              },
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: stats.first),
                for (final stat in stats.skip(1)) Expanded(child: stat),
              ],
            ),
          if (_marking || _lastReload != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _marking
                  ? 'FETCHING PRICES…'
                  : 'PRICES UPDATED ${_formatClock(_lastReload)}'
                      '${_reloadedQuotes > 0 ? '  •  $_reloadedQuotes QUOTES' : ''}',
              style: AppTypography.mono(
                size: 10,
                color: _marking ? AppColors.textMutedDark : AppColors.positive,
                letterSpacing: 0.4,
              ),
            ),
          ],
          if (_markError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _markError!,
              style: AppTypography.mono(size: 11, color: AppColors.negative),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            'NLV = cash + market value. Total P&L = realised + unrealised '
            '(${formatMoney(analytics.realisedPnl)} realised). '
            'Day P&L marks holdings against the previous close.',
            style: AppTypography.ui(
              size: 11,
              color: AppColors.textMutedDark,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Holdings
  // -------------------------------------------------------------------------

  Widget _holdings(PortfolioAnalytics analytics) {
    return Panel(
      title: 'HOLDINGS',
      trailing: Text(
        analytics.isEmpty
            ? 'NO OPEN POSITIONS'
            : '${analytics.holdings.length} POSITIONS • '
                'COST ${formatMoney(analytics.holdings.fold<double>(0, (s, h) => s + h.position.costBasis))}',
        style: AppTypography.mono(
          size: 9,
          color: AppColors.textMutedDark,
          letterSpacing: 0.4,
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: analytics.isEmpty
          ? const EmptyLine(text: 'NO HOLDINGS — BUY FROM THE DISCOVERY TAB')
          : LayoutBuilder(
              builder: (context, constraints) {
                // The table needs ~1010 px; below that, use cards.
                final useTable = constraints.maxWidth >= 1010;
                return Column(
                  children: [
                    if (useTable) const _HoldingsHeader(),
                    for (final holding in analytics.holdings)
                      if (useTable)
                        _HoldingRow(
                          holding: holding,
                          onBuy: () => _quickTrade(holding, OrderSide.buy, 1),
                          onSell: () => _quickTrade(
                            holding,
                            OrderSide.sell,
                            _halfPosition(holding),
                          ),
                          onSellAll: () => _quickTrade(
                            holding,
                            OrderSide.sell,
                            holding.quantity,
                          ),
                        )
                      else
                        _HoldingCard(
                          holding: holding,
                          onBuy: () => _quickTrade(holding, OrderSide.buy, 1),
                          onSell: () => _quickTrade(
                            holding,
                            OrderSide.sell,
                            _halfPosition(holding),
                          ),
                          onSellAll: () => _quickTrade(
                            holding,
                            OrderSide.sell,
                            holding.quantity,
                          ),
                        ),
                  ],
                );
              },
            ),
    );
  }

  // -------------------------------------------------------------------------
  // Analytics drawer
  // -------------------------------------------------------------------------

  Widget _analytics(
    List<EquityPoint> curve,
    CurveMetrics metrics,
    TradeStats stats,
    PortfolioAnalytics analytics,
  ) {
    return Panel(
      title: 'ANALYTICS',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final range in CurveRange.values)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xs),
              child: _RangeChip(
                label: range.label,
                active: range == _range,
                onTap: () => setState(() => _range = range),
              ),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EquityChart(points: curve),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.md,
            children: [
              SizedBox(
                width: 170,
                child: StatBlock(
                  label: 'REALISED P&L',
                  value: formatMoney(stats.realisedTotal),
                  valueColor: _pnlColour(stats.realisedTotal),
                ),
              ),
              SizedBox(
                width: 170,
                child: StatBlock(
                  label: 'WIN / LOSS RATIO',
                  value: _winLoss(stats),
                  sub: '${stats.wins}W / ${stats.losses}L • '
                      '${stats.winRate.toStringAsFixed(0)}% win rate',
                ),
              ),
              SizedBox(
                width: 170,
                child: StatBlock(
                  label: 'MAX DRAWDOWN',
                  value: _signedPercent(metrics.maxDrawdownFraction * 100),
                  sub: formatMoney(metrics.maxDrawdownAmount),
                  valueColor: metrics.maxDrawdownFraction < 0
                      ? AppColors.negative
                      : AppColors.textPrimaryDark,
                ),
              ),
              SizedBox(
                width: 170,
                child: StatBlock(
                  label: 'SHARPE RATIO',
                  value: metrics.hasSharpe
                      ? metrics.sharpe.toStringAsFixed(2)
                      : '—',
                  sub: '${metrics.samples} daily obs',
                  valueColor: metrics.hasSharpe
                      ? (metrics.sharpe >= 0
                          ? AppColors.positive
                          : AppColors.negative)
                      : AppColors.textMutedDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _AllocationBar(allocation: analytics.allocation),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Equity is marked at the last traded price per instrument, with the '
            'latest point marked live. Sharpe uses daily observations and a 0% '
            'risk-free rate; it needs at least three days of history.',
            style: AppTypography.ui(
              size: 11,
              color: AppColors.textMutedDark,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Sync + engine
  // -------------------------------------------------------------------------

  Widget _syncPanel() {
    final outcome = widget.syncOutcome;
    return Panel(
      title: 'SYNC (GIST VAULT)',
      trailing: GhostButton(
        label: 'SETUP / SYNC',
        onPressed: widget.onOpenSync,
      ),
      child: Column(
        children: [
          KeyValueRow(
            label: 'STATUS',
            value: outcome?.label ?? 'LOCAL ONLY',
            mono: true,
            valueColor: _syncColour(outcome?.state),
          ),
          KeyValueRow(
            label: 'VAULT',
            value: widget.syncEngine.config.gistId ?? 'not connected',
            mono: true,
          ),
          KeyValueRow(
            label: 'PENDING EVENTS',
            value: '${widget.pendingSync}',
            mono: true,
          ),
          KeyValueRow(
            label: 'LAST SYNC',
            value: _formatClock(widget.syncEngine.config.lastSyncAt),
            mono: true,
          ),
          if (outcome?.message != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  outcome!.message!,
                  style: AppTypography.mono(
                    size: 11,
                    color: AppColors.negative,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _enginePanel() {
    final database = widget.engine.database;
    return Panel(
      title: 'LOCAL ENGINE',
      child: Column(
        children: [
          KeyValueRow(label: 'DATABASE', value: widget.databasePath, mono: true),
          KeyValueRow(
            label: 'JOURNAL',
            value: database.journalMode.toUpperCase(),
            mono: true,
          ),
          KeyValueRow(
            label: 'SCHEMA',
            value: 'v${database.schemaVersion}',
            mono: true,
          ),
          KeyValueRow(
            label: 'LEDGER EVENTS',
            value: '${widget.ledger.all(accountId: widget.accountId).length}',
            mono: true,
          ),
          KeyValueRow(
            label: 'INSTRUMENTS (FTS5)',
            value: '${database.instrumentCount()}',
            mono: true,
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Formatting helpers
  // -------------------------------------------------------------------------

  static Color _pnlColour(double value) {
    if (value > 0) return AppColors.positive;
    if (value < 0) return AppColors.negative;
    return AppColors.textPrimaryDark;
  }

  static String _signedPercent(double value) {
    final sign = value > 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(2)}%';
  }

  static String _winLoss(TradeStats stats) {
    if (stats.total == 0) return '—';
    final ratio = stats.winLossRatio;
    return ratio == null ? '∞' : ratio.toStringAsFixed(2);
  }

  static String _formatClock(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}

Color? _syncColour(SyncState? state) {
  switch (state) {
    case SyncState.synced:
      return AppColors.positive;
    case SyncState.error:
      return AppColors.negative;
    case SyncState.offline:
      return AppColors.warning;
    case SyncState.syncing:
      return AppColors.focus;
    case SyncState.notConfigured:
    case null:
      return AppColors.textPrimaryDark;
  }
}

// ---------------------------------------------------------------------------
// Holdings table
// ---------------------------------------------------------------------------

class _HoldingCard extends StatelessWidget {
  const _HoldingCard({
    required this.holding,
    required this.onBuy,
    required this.onSell,
    required this.onSellAll,
  });

  final HoldingView holding;
  final VoidCallback onBuy;
  final VoidCallback onSell;
  final VoidCallback onSellAll;

  @override
  Widget build(BuildContext context) {
    final hairline = Theme.of(context).dividerColor;
    final pnlColour = holding.unrealisedPnl > 0
        ? AppColors.positive
        : holding.unrealisedPnl < 0
            ? AppColors.negative
            : AppColors.textSecondaryDark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: hairline, width: AppBorders.hairline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                padding: const EdgeInsets.symmetric(vertical: 2),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: AppColors.hairlineDark,
                    width: AppBorders.hairline,
                  ),
                  borderRadius: AppRadii.smAll,
                ),
                child: Text(
                  holding.assetClass.wire,
                  style: AppTypography.mono(
                    size: 9,
                    weight: FontWeight.w600,
                    color: AppColors.textMutedDark,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      holding.symbol,
                      style: AppTypography.mono(
                        size: 14,
                        weight: FontWeight.w700,
                        color: AppColors.textPrimaryDark,
                      ),
                    ),
                    Text(
                      holding.isin == '—' ? '—' : holding.isin,
                      style: AppTypography.mono(
                        size: 10,
                        color: AppColors.textMutedDark,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMoney(holding.marketValue),
                    style: AppTypography.mono(
                      size: 14,
                      weight: FontWeight.w600,
                      color: AppColors.textPrimaryDark,
                    ),
                  ),
                  Text(
                    '${holding.unrealisedPnl > 0 ? '+' : ''}'
                    '${formatMoney(holding.unrealisedPnl)}  '
                    '${holding.unrealisedPercent > 0 ? '+' : ''}'
                    '${holding.unrealisedPercent.toStringAsFixed(2)}%',
                    style: AppTypography.mono(size: 11, color: pnlColour),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _cell(
                'QTY',
                holding.quantity.toStringAsFixed(
                  holding.assetClass == AssetClass.crypto ? 8 : 4,
                ),
              ),
              _cell('AVG COST', formatMoney(holding.averageCost)),
              _cell(
                'LAST',
                holding.hasQuote ? formatMoney(holding.price) : '—',
              ),
              _cell('WEIGHT', '${holding.weightPercent.toStringAsFixed(1)}%'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _TradeActions(onBuy: onBuy, onSell: onSell, onSellAll: onSellAll),
        ],
      ),
    );
  }

  Widget _cell(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTypography.label(AppColors.textMutedDark)),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.mono(
                size: 12,
                color: AppColors.textPrimaryDark,
              ),
            ),
          ],
        ),
      );
}

class _HoldingsHeader extends StatelessWidget {
  const _HoldingsHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: const [
          _HeaderCell('SYMBOL', 96),
          _HeaderCell('ISIN', 120),
          _HeaderCell('CLASS', 56),
          _HeaderCell('QTY', 88),
          _HeaderCell('AVG COST', 88),
          _HeaderCell('LAST', 88),
          _HeaderCell('MKT VALUE', 104),
          _HeaderCell('UNREAL \$', 96),
          _HeaderCell('UNREAL %', 76),
          _HeaderCell('WT %', 70),
          _HeaderCell('TRADE', 140),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, this.width);

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        label,
        textAlign: label == 'SYMBOL' ||
                label == 'ISIN' ||
                label == 'CLASS' ||
                label == 'TRADE'
            ? TextAlign.left
            : TextAlign.right,
        style: AppTypography.label(AppColors.textMutedDark),
      ),
    );
  }
}

class _HoldingRow extends StatelessWidget {
  const _HoldingRow({
    required this.holding,
    required this.onBuy,
    required this.onSell,
    required this.onSellAll,
  });

  final HoldingView holding;
  final VoidCallback onBuy;
  final VoidCallback onSell;
  final VoidCallback onSellAll;

  @override
  Widget build(BuildContext context) {
    final pnlColour = holding.unrealisedPnl > 0
        ? AppColors.positive
        : holding.unrealisedPnl < 0
            ? AppColors.negative
            : AppColors.textSecondaryDark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              holding.symbol,
              style: AppTypography.mono(
                size: 12,
                weight: FontWeight.w600,
                color: AppColors.textPrimaryDark,
              ),
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              holding.isin,
              style: AppTypography.mono(
                size: 10,
                color: AppColors.textMutedDark,
              ),
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              holding.assetClass.wire,
              style: AppTypography.mono(
                size: 9,
                color: AppColors.textMutedDark,
              ),
            ),
          ),
          _num(
            holding.quantity.toStringAsFixed(
              holding.assetClass == AssetClass.crypto ? 8 : 4,
            ),
            88,
          ),
          _num(formatMoney(holding.averageCost), 88),
          _num(
            holding.hasQuote ? formatMoney(holding.price) : '—',
            88,
            color: holding.hasQuote
                ? AppColors.textPrimaryDark
                : AppColors.textMutedDark,
          ),
          _num(formatMoney(holding.marketValue), 104),
          _num(formatMoney(holding.unrealisedPnl), 96, color: pnlColour),
          _num(
            '${holding.unrealisedPercent > 0 ? '+' : ''}'
            '${holding.unrealisedPercent.toStringAsFixed(2)}%',
            76,
            color: pnlColour,
          ),
          _num('${holding.weightPercent.toStringAsFixed(1)}%', 70),
          SizedBox(
            width: 140,
            child: _TradeActions(
              onBuy: onBuy,
              onSell: onSell,
              onSellAll: onSellAll,
            ),
          ),
        ],
      ),
    );
  }

  Widget _num(String value, double width, {Color? color}) {
    return SizedBox(
      width: width,
      child: Text(
        value,
        textAlign: TextAlign.right,
        style: AppTypography.mono(
          size: 12,
          color: color ?? AppColors.textPrimaryDark,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Allocation + range chips
// ---------------------------------------------------------------------------

class _TradeActions extends StatelessWidget {
  const _TradeActions({
    required this.onBuy,
    required this.onSell,
    required this.onSellAll,
  });

  final VoidCallback onBuy;
  final VoidCallback onSell;
  final VoidCallback onSellAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _action('BUY', AppColors.positive, onBuy),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: _action('SELL', AppColors.negative, onSell),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: _action('ALL', AppColors.textSecondaryDark, onSellAll,
              tooltip: 'Sell the whole position'),
        ),
      ],
    );
  }

  Widget _action(
    String label,
    Color colour,
    VoidCallback onTap, {
    String? tooltip,
  }) {
    final chip = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: colour, width: AppBorders.hairline),
          borderRadius: AppRadii.smAll,
        ),
        child: Text(
          label,
          style: AppTypography.mono(
            size: 10,
            weight: FontWeight.w700,
            letterSpacing: 0.4,
            color: colour,
          ),
        ),
      ),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip, child: chip);
  }
}

class _AllocationBar extends StatelessWidget {
  const _AllocationBar({required this.allocation});

  final Map<AssetClass, double> allocation;

  /// Monochrome ramp: allocation must not imply direction.
  static const Map<AssetClass, Color> _ramp = {
    AssetClass.stock: Color(0xFFA3AAB2),
    AssetClass.etf: Color(0xFF7C848C),
    AssetClass.fund: Color(0xFF5C646C),
    AssetClass.bond: Color(0xFF454C54),
    AssetClass.marketIndex: Color(0xFF38414A),
    AssetClass.crypto: Color(0xFF2E343B),
  };

  @override
  Widget build(BuildContext context) {
    final total = allocation.values.fold<double>(0, (a, b) => a + b);
    final entries = allocation.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (total <= 0) {
      return const EmptyLine(text: 'NO ALLOCATION — NO OPEN POSITIONS');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('ASSET ALLOCATION', style: AppTypography.label(AppColors.textMutedDark)),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: AppRadii.smAll,
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                for (final entry in entries)
                  Expanded(
                    flex: ((entry.value / total) * 1000).round().clamp(1, 1000),
                    child: Container(color: _ramp[entry.key]),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.xs,
          children: [
            for (final entry in entries)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 8, height: 8, color: _ramp[entry.key]),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '${entry.key.label.toUpperCase()} '
                    '${((entry.value / total) * 100).toStringAsFixed(1)}%',
                    style: AppTypography.mono(
                      size: 10,
                      color: AppColors.textSecondaryDark,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: active ? AppColors.panelDark : Colors.transparent,
          border: Border.all(
            color: active ? AppColors.focus : AppColors.hairlineDark,
            width: AppBorders.hairline,
          ),
          borderRadius: AppRadii.smAll,
        ),
        child: Text(
          label,
          style: AppTypography.mono(
            size: 10,
            weight: FontWeight.w600,
            color: active ? AppColors.textPrimaryDark : AppColors.textMutedDark,
          ),
        ),
      ),
    );
  }
}
