import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../data/app_database.dart';
import '../../data/ledger_repository.dart';
import '../../design/tokens.dart';
import '../../market/asset_class.dart';
import '../../market/instrument_repository.dart';
import '../../market/market_data_service.dart';
import '../../market/models/instrument.dart';
import '../../market/models/quote.dart';
import '../../market/providers/market_data_provider.dart';
import '../../market/quote_repository.dart';
import '../../trading/portfolio.dart';
import '../../trading/position_repository.dart';
import '../../trading/trading_engine.dart';
import '../trade/order_ticket.dart';

/// Virtual cash added by the "DEPOSIT CASH" action / opening balance.
const double kDepositAmount = 100000.0;

/// The application frame: a dense top bar, a two-tab body, and a bottom
/// segmented control (thumb-first on Android, `Ctrl+1`/`Ctrl+2` on Windows).
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.database,
    required this.databasePath,
    required this.ledger,
    required this.instruments,
    required this.quotes,
    required this.marketData,
    required this.engine,
    required this.positions,
    required this.accountId,
  });

  final AppDatabase database;
  final String databasePath;
  final LedgerRepository ledger;
  final InstrumentRepository instruments;
  final QuoteRepository quotes;
  final MarketDataService marketData;
  final TradingEngine engine;
  final PositionRepository positions;
  final String accountId;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  final GlobalKey<_DiscoveryTabState> _discoveryKey =
      GlobalKey<_DiscoveryTabState>();

  @override
  void initState() {
    super.initState();
  }

  void _selectTab(int index) {
    if (index == _tab) return;
    setState(() => _tab = index);
  }

  void _deposit() {
    widget.ledger.append(widget.ledger.deposit(amount: kDepositAmount));
    setState(() {});
  }

  /// Called after an order fills so derived views re-read the ledger.
  void _afterTrade() => setState(() {});

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (ctrl && key == LogicalKeyboardKey.digit1) {
      _selectTab(0);
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.digit2) {
      _selectTab(1);
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyR && _tab == 1) {
      _discoveryKey.currentState?.refreshQuotes();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final cash = widget.ledger.cashBalance();
    final openPositions = widget.positions.all(widget.accountId);
    final realisedPnl =
        openPositions.fold<double>(0.0, (sum, p) => sum + p.realisedPnl);

    return Scaffold(
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          children: [
            _TopBar(
              journalMode: widget.database.journalMode,
              schemaVersion: widget.database.schemaVersion,
              pending: widget.engine.workingOrders().length,
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  _PortfolioTab(
                    databasePath: widget.databasePath,
                    journalMode: widget.database.journalMode,
                    schemaVersion: widget.database.schemaVersion,
                    ledgerCount: widget.database.ledgerEventCount(),
                    cash: cash,
                    realisedPnl: realisedPnl,
                    positions: openPositions,
                    instrumentCount: widget.database.instrumentCount(),
                    onDeposit: _deposit,
                  ),
                  _DiscoveryTab(
                    key: _discoveryKey,
                    instruments: widget.instruments,
                    quotes: widget.quotes,
                    marketData: widget.marketData,
                    engine: widget.engine,
                    onTraded: _afterTrade,
                  ),
                ],
              ),
            ),
            _SegmentBar(index: _tab, onChanged: _selectTab),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.journalMode,
    required this.schemaVersion,
    required this.pending,
  });

  final String journalMode;
  final int schemaVersion;
  final int pending;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final hairline = Theme.of(context).dividerColor;

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.panelDark,
        border: Border(
          bottom: BorderSide(color: hairline, width: AppBorders.hairline),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          const _TbMark(size: 22),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'TUREIS',
            style: AppTypography.mono(
              size: 13,
              weight: FontWeight.w700,
              color: onSurface,
              letterSpacing: 1.4,
            ),
          ),
          Text(
            'BANKING',
            style: AppTypography.mono(
              size: 13,
              weight: FontWeight.w400,
              color: AppColors.neutral,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Container(width: AppBorders.hairline, height: 16, color: hairline),
          const SizedBox(width: AppSpacing.md),
          Text(
            'LEDGER v$schemaVersion  •  ${journalMode.toUpperCase()}',
            style: AppTypography.mono(
              size: 11,
              color: AppColors.textMutedDark,
              letterSpacing: 0.4,
            ),
          ),
          const Spacer(),
          _StatusPill(pending: pending),
        ],
      ),
    );
  }
}

/// The brand mark: a miniature of the app icon, drawn with widgets so it stays
/// crisp at any DPI without a raster asset.
class _TbMark extends StatelessWidget {
  const _TbMark({this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.carbon,
        border: Border.all(
          color: AppColors.hairlineDark,
          width: AppBorders.hairline,
        ),
        borderRadius: AppRadii.smAll,
      ),
      alignment: Alignment.center,
      child: Text(
        'TB',
        style: AppTypography.mono(
          size: size * 0.44,
          weight: FontWeight.w700,
          color: AppColors.textPrimaryDark,
          letterSpacing: 0,
          height: 1.0,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.pending});

  final int pending;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.hairlineDark, width: AppBorders.hairline),
        borderRadius: AppRadii.smAll,
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.warning, // swatch: local-only until Phase 4.
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'LOCAL • QUEUED ($pending)',
            style: AppTypography.mono(
              size: 11,
              weight: FontWeight.w600,
              color: AppColors.textSecondaryDark,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1 — Portfolio: engine read, account summary, positions
// ---------------------------------------------------------------------------

class _PortfolioTab extends StatelessWidget {
  const _PortfolioTab({
    required this.databasePath,
    required this.journalMode,
    required this.schemaVersion,
    required this.ledgerCount,
    required this.cash,
    required this.realisedPnl,
    required this.positions,
    required this.instrumentCount,
    required this.onDeposit,
  });

  final String databasePath;
  final String journalMode;
  final int schemaVersion;
  final int ledgerCount;
  final double cash;
  final double realisedPnl;
  final List<Position> positions;
  final int instrumentCount;
  final VoidCallback onDeposit;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Panel(
            title: 'ACCOUNT',
            trailing: _GhostButton(label: 'DEPOSIT CASH', onPressed: onDeposit),
            child: Column(
              children: [
                _KeyValueRow(
                  label: 'CASH BALANCE',
                  value: formatMoney(cash),
                  mono: true,
                  emphasis: true,
                ),
                _KeyValueRow(
                  label: 'REALISED P&L',
                  value: formatMoney(realisedPnl),
                  mono: true,
                  valueColor: realisedPnl > 0
                      ? AppColors.positive
                      : realisedPnl < 0
                          ? AppColors.negative
                          : AppColors.textPrimaryDark,
                ),
                _KeyValueRow(
                  label: 'OPEN POSITIONS',
                  value: '${positions.length}',
                  mono: true,
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Portfolio state is never stored — it is replayed from the '
                    'append-only ledger on every read.',
                    style: AppTypography.ui(
                      size: 12,
                      color: AppColors.textMutedDark,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _Panel(
            title: 'POSITIONS (CACHE)',
            trailing: Text(
              'MARK-TO-MARKET IN PHASE 5',
              style: AppTypography.mono(
                size: 9,
                color: AppColors.textMutedDark,
                letterSpacing: 0.4,
              ),
            ),
            child: positions.isEmpty
                ? _EmptyLine(text: 'NO OPEN POSITIONS')
                : Column(
                    children: [
                      const _PositionHeader(),
                      for (final position in positions)
                        _PositionRow(position: position),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _Panel(
            title: 'LOCAL ENGINE',
            child: Column(
              children: [
                _KeyValueRow(label: 'DATABASE', value: databasePath, mono: true),
                _KeyValueRow(label: 'JOURNAL', value: journalMode.toUpperCase(), mono: true),
                _KeyValueRow(label: 'SCHEMA', value: 'v$schemaVersion', mono: true),
                _KeyValueRow(label: 'LEDGER EVENTS', value: '$ledgerCount', mono: true),
                _KeyValueRow(label: 'INSTRUMENTS (FTS5)', value: '$instrumentCount', mono: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PositionHeader extends StatelessWidget {
  const _PositionHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          _col('SYMBOL', 110, alignRight: false),
          _col('CLASS', 70, alignRight: false),
          _col('QTY', 110),
          _col('AVG COST', 110),
          _col('COST BASIS', 110),
          _col('REALISED P&L', 120),
        ],
      ),
    );
  }

  Widget _col(String label, double width, {bool alignRight = true}) {
    return SizedBox(
      width: width,
      child: Text(
        label,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: AppTypography.label(AppColors.textMutedDark),
      ),
    );
  }
}

class _PositionRow extends StatelessWidget {
  const _PositionRow({required this.position});

  final Position position;

  @override
  Widget build(BuildContext context) {
    final realised = position.realisedPnl;
    final realisedColor = realised > 0
        ? AppColors.positive
        : realised < 0
            ? AppColors.negative
            : AppColors.textSecondaryDark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              position.symbol,
              style: AppTypography.mono(
                size: 12,
                weight: FontWeight.w600,
                color: AppColors.textPrimaryDark,
              ),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              position.assetClass.wire,
              style: AppTypography.mono(
                size: 9,
                color: AppColors.textMutedDark,
              ),
            ),
          ),
          _num(position.quantity.toStringAsFixed(
            position.assetClass == AssetClass.crypto ? 8 : 4,
          ), 110),
          _num(formatMoney(position.averageCost), 110),
          _num(formatMoney(position.costBasis), 110),
          _num(formatMoney(realised), 120, color: realisedColor),
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
// Tab 2 — Multi-asset discovery (FTS5 search + live quotes + trading)
// ---------------------------------------------------------------------------

class _DiscoveryTab extends StatefulWidget {
  const _DiscoveryTab({
    super.key,
    required this.instruments,
    required this.quotes,
    required this.marketData,
    required this.engine,
    required this.onTraded,
  });

  final InstrumentRepository instruments;
  final QuoteRepository quotes;
  final MarketDataService marketData;
  final TradingEngine engine;
  final VoidCallback onTraded;

  @override
  State<_DiscoveryTab> createState() => _DiscoveryTabState();
}

class _DiscoveryTabState extends State<_DiscoveryTab> {
  final TextEditingController _controller = TextEditingController();

  AssetClass? _filter;
  List<Instrument> _results = const [];
  Map<String, Quote> _quotes = const {};
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _runSearch();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _runSearch() {
    final results = widget.instruments.search(
      _controller.text,
      assetClass: _filter,
      limit: 60,
    );
    final quotes = widget.quotes.getMany(results.map((e) => e.symbol));
    setState(() {
      _results = results;
      _quotes = quotes;
      // Let resting orders react to the freshest known prices.
      for (final quote in quotes.values) {
        widget.engine.onQuote(quote);
      }
    });
  }

  void _setFilter(AssetClass? filter) {
    _filter = filter;
    _runSearch();
  }

  /// Fetches live quotes for the visible results (also bound to Ctrl+R).
  Future<void> refreshQuotes() async {
    if (_results.isEmpty || _refreshing) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final fetched = await widget.marketData.refreshQuotes(_results);
      for (final quote in fetched) {
        widget.engine.onQuote(quote);
      }
      if (!mounted) return;
      setState(() {
        _quotes = <String, Quote>{
          ..._quotes,
          for (final q in fetched) q.symbol: q,
        };
      });
    } on MarketDataException catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } catch (e) {
      if (mounted) setState(() => _error = 'Market data unavailable: $e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _openTicket(Instrument instrument) async {
    final result = await showOrderTicket(
      context,
      engine: widget.engine,
      marketData: widget.marketData,
      quotes: widget.quotes,
      instrument: instrument,
    );
    if (!mounted) return;
    if (result != null && result.isFilled) {
      widget.onTraded();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.raisedDark,
          content: Text(
            '${result.order.side.wire} ${result.order.quantity} '
            '${instrument.symbol} @ ${result.executionPrice?.toStringAsFixed(2)}',
            style: AppTypography.mono(
              size: 12,
              color: AppColors.textPrimaryDark,
            ),
          ),
        ),
      );
    }
    setState(() {
      _quotes = widget.quotes.getMany(_results.map((e) => e.symbol));
    });
    widget.onTraded();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: _SearchField(
            controller: _controller,
            onChanged: (_) => _runSearch(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: _FilterPills(selected: _filter, onChanged: _setFilter),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Text(
                '${_results.length} RESULTS',
                style: AppTypography.label(AppColors.textMutedDark),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                'CLICK A ROW TO TRADE',
                style: AppTypography.mono(
                  size: 9,
                  color: AppColors.textMutedDark,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              if (_refreshing)
                Text(
                  'FETCHING…',
                  style: AppTypography.mono(
                    size: 10,
                    color: AppColors.textMutedDark,
                    letterSpacing: 0.6,
                  ),
                ),
              const SizedBox(width: AppSpacing.sm),
              _GhostButton(
                label: 'REFRESH QUOTES',
                onPressed: _refreshing ? () {} : refreshQuotes,
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppColors.negative,
                  width: AppBorders.hairline,
                ),
                borderRadius: AppRadii.smAll,
              ),
              child: Text(
                _error!,
                style: AppTypography.mono(
                  size: 11,
                  color: AppColors.negative,
                ),
              ),
            ),
          ),
        Expanded(
          child: _results.isEmpty
              ? const _EmptyLine(text: 'NO INSTRUMENTS MATCH')
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final instrument = _results[index];
                    return _InstrumentRow(
                      instrument: instrument,
                      quote: _quotes[instrument.symbol],
                      onTap: () => _openTicket(instrument),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.raisedDark,
        border: Border.all(
          color: AppColors.hairlineDark,
          width: AppBorders.hairline,
        ),
        borderRadius: AppRadii.smAll,
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 15, color: AppColors.textMutedDark),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              autofocus: false,
              style: AppTypography.mono(
                size: 12,
                color: AppColors.textPrimaryDark,
              ),
              cursorColor: AppColors.focus,
              cursorWidth: 1.5,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search ticker, pair, issuer or ISIN  (/)',
                hintStyle: AppTypography.ui(
                  size: 12,
                  color: AppColors.textMutedDark,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterPills extends StatelessWidget {
  const _FilterPills({required this.selected, required this.onChanged});

  final AssetClass? selected;
  final ValueChanged<AssetClass?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _Pill(
          label: 'All',
          active: selected == null,
          onTap: () => onChanged(null),
        ),
        for (final assetClass in AssetClass.values)
          _Pill(
            label: assetClass.label,
            active: selected == assetClass,
            onTap: () => onChanged(assetClass),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.active, required this.onTap});

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
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: active ? AppColors.raisedDark : Colors.transparent,
          border: Border.all(
            color: active ? AppColors.focus : AppColors.hairlineDark,
            width: AppBorders.hairline,
          ),
          borderRadius: AppRadii.smAll,
        ),
        child: Text(
          label.toUpperCase(),
          style: AppTypography.mono(
            size: 10,
            weight: FontWeight.w600,
            letterSpacing: 0.6,
            color: active ? AppColors.textPrimaryDark : AppColors.textMutedDark,
          ),
        ),
      ),
    );
  }
}

class _InstrumentRow extends StatelessWidget {
  const _InstrumentRow({
    required this.instrument,
    this.quote,
    required this.onTap,
  });

  final Instrument instrument;
  final Quote? quote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hairline = Theme.of(context).dividerColor;
    final changeColor = _changeColor(quote?.changePercent);

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: hairline, width: AppBorders.hairline),
          ),
        ),
        child: Row(
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
                instrument.assetClass.wire,
                style: AppTypography.mono(
                  size: 9,
                  weight: FontWeight.w600,
                  color: AppColors.textMutedDark,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            SizedBox(
              width: 110,
              child: Text(
                instrument.symbol,
                style: AppTypography.mono(
                  size: 13,
                  weight: FontWeight.w600,
                  color: AppColors.textPrimaryDark,
                ),
              ),
            ),
            Expanded(
              child: Text(
                instrument.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.ui(
                  size: 12,
                  color: AppColors.textSecondaryDark,
                ),
              ),
            ),
            if (instrument.isin != null) ...[
              const SizedBox(width: AppSpacing.md),
              Text(
                instrument.isin!,
                style: AppTypography.mono(
                  size: 10,
                  color: AppColors.textMutedDark,
                ),
              ),
            ],
            const SizedBox(width: AppSpacing.lg),
            SizedBox(
              width: 96,
              child: Text(
                quote == null ? '—' : _formatPrice(instrument, quote!),
                textAlign: TextAlign.right,
                style: AppTypography.mono(
                  size: 13,
                  weight: FontWeight.w600,
                  color: AppColors.textPrimaryDark,
                ),
              ),
            ),
            SizedBox(
              width: 72,
              child: Text(
                quote == null ? '' : _formatChange(quote!),
                textAlign: TextAlign.right,
                style: AppTypography.mono(
                  size: 12,
                  color: changeColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatPrice(Instrument instrument, Quote quote) {
    if (instrument.assetClass == AssetClass.bond) {
      return '${quote.price.toStringAsFixed(3)}%';
    }
    return formatMoney(quote.price);
  }

  static String _formatChange(Quote quote) {
    final percent = quote.changePercent;
    if (percent == null) return '—';
    final sign = percent > 0 ? '+' : '';
    return '$sign${percent.toStringAsFixed(2)}%';
  }

  static Color _changeColor(double? percent) {
    if (percent == null) return AppColors.neutral;
    if (percent > 0) return AppColors.positive;
    if (percent < 0) return AppColors.negative;
    return AppColors.neutral;
  }
}

// ---------------------------------------------------------------------------
// Shared primitives
// ---------------------------------------------------------------------------

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final hairline = Theme.of(context).dividerColor;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panelDark,
        border: Border.all(color: hairline, width: AppBorders.hairline),
        borderRadius: AppRadii.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.raisedDark,
              border: Border(
                bottom: BorderSide(color: hairline, width: AppBorders.hairline),
              ),
            ),
            child: Row(
              children: [
                Text(
                  title,
                  style: AppTypography.label(AppColors.textSecondaryDark),
                ),
                const Spacer(),
                ?trailing,
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({
    required this.label,
    required this.value,
    this.mono = false,
    this.emphasis = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool mono;
  final bool emphasis;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final base = mono
        ? AppTypography.mono(
            size: emphasis ? 16 : 12,
            weight: emphasis ? FontWeight.w600 : FontWeight.w400,
            color: valueColor ?? AppColors.textPrimaryDark,
          )
        : AppTypography.ui(size: 12, color: AppColors.textPrimaryDark);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(
              label,
              style: AppTypography.label(AppColors.textMutedDark),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: base,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: Text(
          text,
          style: AppTypography.mono(
            size: 11,
            color: AppColors.textMutedDark,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 22),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: AppColors.textSecondaryDark,
        shape: RoundedRectangleBorder(
          side: const BorderSide(
            color: AppColors.hairlineDark,
            width: AppBorders.hairline,
          ),
          borderRadius: AppRadii.smAll,
        ),
        textStyle: AppTypography.mono(
          size: 10,
          weight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
      child: Text(label),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom segmented navigation
// ---------------------------------------------------------------------------

class _SegmentBar extends StatelessWidget {
  const _SegmentBar({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final hairline = Theme.of(context).dividerColor;
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: AppColors.panelDark,
        border: Border(
          top: BorderSide(color: hairline, width: AppBorders.hairline),
        ),
      ),
      child: Row(
        children: [
          _Segment(
            index: 0,
            selected: index == 0,
            title: 'PORTFOLIO',
            hint: 'Ctrl+1',
            onTap: onChanged,
          ),
          _Segment(
            index: 1,
            selected: index == 1,
            title: 'DISCOVERY',
            hint: 'Ctrl+2',
            onTap: onChanged,
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.index,
    required this.selected,
    required this.title,
    required this.hint,
    required this.onTap,
  });

  final int index;
  final bool selected;
  final String title;
  final String hint;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(index),
        child: Container(
          decoration: BoxDecoration(
            color: selected ? AppColors.raisedDark : Colors.transparent,
            border: Border(
              top: BorderSide(
                color: selected ? AppColors.focus : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${index + 1}',
                style: AppTypography.mono(
                  size: 11,
                  weight: FontWeight.w600,
                  color: selected
                      ? AppColors.textSecondaryDark
                      : AppColors.textMutedDark,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                title,
                style: AppTypography.ui(
                  size: 12,
                  weight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: selected
                      ? AppColors.textPrimaryDark
                      : AppColors.textMutedDark,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                hint,
                style: AppTypography.mono(
                  size: 10,
                  color: AppColors.textMutedDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
