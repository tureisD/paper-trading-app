import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/tokens.dart';
import '../../market/asset_class.dart';
import '../../market/instrument_repository.dart';
import '../../market/live_quotes.dart';
import '../../market/market_data_service.dart';
import '../../market/models/candle.dart';
import '../../market/models/instrument.dart';
import '../../market/models/quote.dart';
import '../../market/providers/market_data_provider.dart';
import '../../market/quote_repository.dart';
import '../../trading/bond_math.dart';
import '../../trading/trading_engine.dart';
import '../common/primitives.dart';
import '../trade/order_ticket.dart';
import 'price_chart.dart';

/// Tab 2 — unified multi-asset search with a split-pane detail/execution sheet
/// (roadmap Phase 6).
class DiscoveryTab extends StatefulWidget {
  const DiscoveryTab({
    super.key,
    required this.instruments,
    required this.quotes,
    required this.marketData,
    required this.engine,
    required this.liveQuotes,
    required this.onTraded,
  });

  final InstrumentRepository instruments;
  final QuoteRepository quotes;
  final MarketDataService marketData;
  final TradingEngine engine;
  final LiveQuoteService liveQuotes;
  final VoidCallback onTraded;

  @override
  State<DiscoveryTab> createState() => DiscoveryTabState();
}

/// Chart windows available in the detail sheet.
enum ChartRange {
  oneMonth('1M', 22),
  threeMonths('3M', 66),
  sixMonths('6M', 130),
  oneYear('1Y', 252);

  const ChartRange(this.label, this.sessions);

  final String label;
  final int sessions;
}

class DiscoveryTabState extends State<DiscoveryTab> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  AssetClass? _filter;
  List<Instrument> _results = const [];
  Map<String, Quote> _quotes = const {};
  bool _refreshing = false;
  String? _error;

  Instrument? _selected;
  ChartRange _range = ChartRange.threeMonths;
  final Map<String, List<Candle>> _candles = {};
  bool _loadingChart = false;
  String? _chartError;

  @override
  void initState() {
    super.initState();
    widget.liveQuotes.addListener(_onLiveQuotes);
    _runSearch();
  }

  @override
  void dispose() {
    widget.liveQuotes.removeListener(_onLiveQuotes);
    _controller.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onLiveQuotes() {
    if (!mounted) return;
    // The service already coalesces to one update per frame.
    setState(() {
      _quotes = <String, Quote>{..._quotes, ...widget.liveQuotes.latest};
    });
  }

  Future<void> _toggleLive() async {
    if (widget.liveQuotes.isStreaming) {
      await widget.liveQuotes.stop();
      if (mounted) setState(() {});
      return;
    }
    final targets = _results
        .where((instrument) => instrument.assetClass == AssetClass.crypto)
        .toList(growable: false);
    if (targets.isEmpty) {
      setState(() => _error = 'No crypto instruments in view to stream');
      return;
    }
    setState(() => _error = null);
    await widget.liveQuotes.start(targets);
    if (mounted) setState(() {});
  }

  /// Bound to `/` from the shell.
  void focusSearch() => _searchFocus.requestFocus();

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

  Future<void> _select(Instrument instrument, {bool force = false}) async {
    setState(() {
      _selected = instrument;
      _chartError = null;
    });
    await _loadCandles(instrument, force: force);
  }

  Future<void> _loadCandles(Instrument instrument, {bool force = false}) async {
    final key = '${instrument.symbol}:${_range.sessions}';
    if (!force && _candles.containsKey(key)) return;

    setState(() {
      _loadingChart = true;
      _chartError = null;
    });
    try {
      final candles = await widget.marketData.candles(
        instrument,
        interval: '1d',
        limit: _range.sessions,
      );
      if (!mounted) return;
      setState(() => _candles[key] = candles);
    } on MarketDataException catch (e) {
      if (mounted) setState(() => _chartError = e.toString());
    } catch (e) {
      if (mounted) setState(() => _chartError = 'Chart unavailable: $e');
    } finally {
      if (mounted) setState(() => _loadingChart = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (!wide) return _list();

    final hairline = Theme.of(context).dividerColor;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 470, child: _list()),
        Container(width: AppBorders.hairline, color: hairline),
        Expanded(child: _detail()),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Master list
  // -------------------------------------------------------------------------

  Widget _list() {
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
            focusNode: _searchFocus,
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
              GhostButton(
                label: 'REFRESH',
                onPressed: _refreshing ? () {} : refreshQuotes,
              ),
              const SizedBox(width: AppSpacing.sm),
              GhostButton(
                label: widget.liveQuotes.isStreaming ? 'LIVE ●' : 'GO LIVE',
                accent: widget.liveQuotes.isStreaming
                    ? AppColors.positive
                    : AppColors.textSecondaryDark,
                onPressed: _toggleLive,
              ),
            ],
          ),
        ),
        if (widget.liveQuotes.isStreaming)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(
              '${widget.liveQuotes.status.toUpperCase()} • '
              '${widget.liveQuotes.receivedTicks} TICKS • '
              '${widget.liveQuotes.emittedBatches} FRAMES • '
              'COALESCED ${(widget.liveQuotes.coalescedFraction * 100).toStringAsFixed(0)}%',
              style: AppTypography.mono(
                size: 9,
                color: AppColors.positive,
                letterSpacing: 0.4,
              ),
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
            child: Text(
              _error!,
              style: AppTypography.mono(size: 11, color: AppColors.negative),
            ),
          ),
        Expanded(
          child: _results.isEmpty
              ? const EmptyLine(text: 'NO INSTRUMENTS MATCH')
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final instrument = _results[index];
                    return _InstrumentRow(
                      instrument: instrument,
                      quote: _quotes[instrument.symbol],
                      selected: _selected?.symbol == instrument.symbol,
                      onTap: () {
                        if (MediaQuery.sizeOf(context).width >= 900) {
                          _select(instrument);
                        } else {
                          _openTicket(instrument);
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
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
    widget.onTraded();
    setState(() {
      _quotes = widget.quotes.getMany(_results.map((e) => e.symbol));
    });
    if (result != null && result.isFilled) {
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
  }

  // -------------------------------------------------------------------------
  // Detail / execution sheet
  // -------------------------------------------------------------------------

  Widget _detail() {
    final instrument = _selected;
    if (instrument == null) {
      return const EmptyLine(text: 'SELECT AN INSTRUMENT TO INSPECT AND TRADE');
    }

    final quote = _quotes[instrument.symbol];
    final candles = _candles['${instrument.symbol}:${_range.sessions}'] ?? const [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _detailHeader(instrument, quote),
          const SizedBox(height: AppSpacing.lg),
          Panel(
            title: instrument.assetClass == AssetClass.bond
                ? 'YIELD HISTORY'
                : 'PRICE HISTORY',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_loadingChart)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: Text(
                      'LOADING…',
                      style: AppTypography.mono(
                        size: 9,
                        color: AppColors.textMutedDark,
                      ),
                    ),
                  ),
                for (final range in ChartRange.values)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.xs),
                    child: _MiniChip(
                      label: range.label,
                      active: range == _range,
                      onTap: () {
                        setState(() => _range = range);
                        _loadCandles(instrument);
                      },
                    ),
                  ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_chartError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                      _chartError!,
                      style: AppTypography.mono(
                        size: 11,
                        color: AppColors.negative,
                      ),
                    ),
                  ),
                PriceChart(
                  candles: candles,
                  isYieldSeries: instrument.assetClass == AssetClass.bond,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Panel(
            title: 'METRICS',
            child: _metrics(instrument, quote, candles),
          ),
          const SizedBox(height: AppSpacing.lg),
          OrderTicket(
            key: ValueKey('ticket-${instrument.symbol}'),
            engine: widget.engine,
            marketData: widget.marketData,
            quotes: widget.quotes,
            instrument: instrument,
            onCompleted: (_) => widget.onTraded(),
          ),
        ],
      ),
    );
  }

  Widget _detailHeader(Instrument instrument, Quote? quote) {
    final change = quote?.change;
    final changePercent = quote?.changePercent;
    final colour = (change ?? 0) > 0
        ? AppColors.positive
        : (change ?? 0) < 0
            ? AppColors.negative
            : AppColors.textSecondaryDark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    instrument.symbol,
                    style: AppTypography.mono(
                      size: 22,
                      weight: FontWeight.w700,
                      color: AppColors.textPrimaryDark,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: 1,
                    ),
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
                        color: AppColors.textMutedDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                instrument.name,
                style: AppTypography.ui(
                  size: 13,
                  color: AppColors.textSecondaryDark,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatPrice(instrument, quote),
              style: AppTypography.mono(
                size: 22,
                weight: FontWeight.w600,
                color: AppColors.textPrimaryDark,
              ),
            ),
            Text(
              change == null
                  ? '—'
                  : '${change > 0 ? '+' : ''}${change.toStringAsFixed(2)}  '
                      '${changePercent != null ? '${changePercent > 0 ? '+' : ''}${changePercent.toStringAsFixed(2)}%' : ''}',
              style: AppTypography.mono(size: 12, color: colour),
            ),
          ],
        ),
      ],
    );
  }

  Widget _metrics(Instrument instrument, Quote? quote, List<Candle> candles) {
    final entries = <(String, String)>[
      ('LAST', _formatPrice(instrument, quote)),
      ('CHANGE %', quote?.changePercent == null
          ? '—'
          : '${quote!.changePercent! > 0 ? '+' : ''}${quote.changePercent!.toStringAsFixed(2)}%'),
      ('ISIN', instrument.isin ?? '—'),
      ('EXCHANGE', instrument.exchange ?? '—'),
      ('CURRENCY', instrument.currency),
    ];

    switch (instrument.assetClass) {
      case AssetClass.etf:
      case AssetClass.fund:
        entries.add((
          'EXPENSE RATIO',
          instrument.expenseRatio == null
              ? '—'
              : '${instrument.expenseRatio!.toStringAsFixed(3)}%',
        ));
      case AssetClass.crypto:
        if (candles.isNotEmpty) {
          final last = candles.last;
          entries
            ..add(('24H HIGH', formatMoney(last.high)))
            ..add(('24H LOW', formatMoney(last.low)))
            ..add((
              '24H VOLUME',
              last.volume == null
                  ? '—'
                  : last.volume!.toStringAsFixed(0),
            ));
        }
      case AssetClass.bond:
        entries.addAll(_bondMetrics(instrument, quote));
      case AssetClass.stock:
        break;
    }

    return Wrap(
      spacing: AppSpacing.xxl,
      runSpacing: AppSpacing.md,
      children: [
        for (final entry in entries)
          SizedBox(
            width: 170,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.$1,
                  style: AppTypography.label(AppColors.textMutedDark),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  entry.$2,
                  style: AppTypography.mono(
                    size: 13,
                    weight: FontWeight.w600,
                    color: AppColors.textPrimaryDark,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Bonds with a coupon schedule quote in clean price (% of par) and get a
  /// computed YTM and modified duration; yield series show their level in bp.
  List<(String, String)> _bondMetrics(Instrument instrument, Quote? quote) {
    final details = widget.instruments.bondDetails(instrument.symbol);
    final maturity = BondMath.parseDateUtc(details?.maturityDate);
    final rate = details?.couponRate;

    final entries = <(String, String)>[
      (
        'YIELD',
        quote == null ? '—' : '${quote.price.toStringAsFixed(3)}%'
      ),
      (
        'CHANGE (bp)',
        quote?.change == null
            ? '—'
            : '${quote!.change! >= 0 ? '+' : ''}'
                '${(quote.change! * 100).toStringAsFixed(1)}'
      ),
    ];

    if (details == null || rate == null || maturity == null) {
      entries.add(('COUPON', '—'));
      entries.add(('MATURITY', '—'));
      entries.add(('MODIFIED DURATION', '—'));
      entries.add(('SERIES TYPE', 'par-yield index (no coupon schedule)'));
      return entries;
    }

    final par = details.parValue ?? 100;
    final frequency = details.couponFrequency ?? 2;
    final asOf = DateTime.now().toUtc();
    final months = (maturity.year - asOf.year) * 12 +
        (maturity.month - asOf.month);
    final periods =
        ((months / (12 / frequency)).ceil()).clamp(1, 400).toInt();

    final ytm = quote == null
        ? null
        : BondMath.yieldToMaturity(
            price: quote.price,
            parValue: par,
            annualCouponRate: rate,
            paymentsPerYear: frequency,
            periodsToMaturity: periods,
          );
    final duration = ytm == null
        ? null
        : BondMath.modifiedDuration(
            parValue: par,
            annualCouponRate: rate,
            paymentsPerYear: frequency,
            annualYield: ytm,
            periodsToMaturity: periods,
          );

    entries
      ..add(('COUPON', '${(rate * 100).toStringAsFixed(3)}%'))
      ..add(('MATURITY', details.maturityDate!))
      ..add(('YTM', ytm == null ? '—' : '${(ytm * 100).toStringAsFixed(3)}%'))
      ..add((
        'MODIFIED DURATION',
        duration == null ? '—' : '${duration.toStringAsFixed(2)} yr',
      ))
      ..add(('FREQUENCY', '$frequency/yr'))
      ..add(('DAY COUNT', details.dayCount ?? '—'));
    return entries;
  }

  static String _formatPrice(Instrument instrument, Quote? quote) {
    if (quote == null) return '—';
    if (instrument.assetClass == AssetClass.bond) {
      return '${quote.price.toStringAsFixed(3)}%';
    }
    return formatMoney(quote.price);
  }
}

// ---------------------------------------------------------------------------
// List widgets
// ---------------------------------------------------------------------------

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
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
              focusNode: focusNode,
              onChanged: onChanged,
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
        _MiniChip(
          label: 'ALL',
          active: selected == null,
          onTap: () => onChanged(null),
        ),
        for (final assetClass in AssetClass.values)
          _MiniChip(
            label: assetClass.label.toUpperCase(),
            active: selected == assetClass,
            onTap: () => onChanged(assetClass),
          ),
      ],
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
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
          vertical: 3,
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
          label,
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
    required this.selected,
    required this.onTap,
  });

  final Instrument instrument;
  final Quote? quote;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hairline = Theme.of(context).dividerColor;
    final percent = quote?.changePercent;
    final changeColor = percent == null
        ? AppColors.neutral
        : percent > 0
            ? AppColors.positive
            : percent < 0
                ? AppColors.negative
                : AppColors.neutral;

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          color: selected ? AppColors.raisedDark : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: hairline, width: AppBorders.hairline),
            left: BorderSide(
              color: selected ? AppColors.focus : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
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
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: 96,
              child: Text(
                instrument.symbol,
                style: AppTypography.mono(
                  size: 12,
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
                  size: 11,
                  color: AppColors.textSecondaryDark,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: 84,
              child: Text(
                quote == null
                    ? '—'
                    : instrument.assetClass == AssetClass.bond
                        ? '${quote!.price.toStringAsFixed(3)}%'
                        : formatMoney(quote!.price),
                textAlign: TextAlign.right,
                style: AppTypography.mono(
                  size: 12,
                  weight: FontWeight.w600,
                  color: AppColors.textPrimaryDark,
                ),
              ),
            ),
            SizedBox(
              width: 62,
              child: Text(
                percent == null
                    ? ''
                    : '${percent > 0 ? '+' : ''}${percent.toStringAsFixed(2)}%',
                textAlign: TextAlign.right,
                style: AppTypography.mono(size: 11, color: changeColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
