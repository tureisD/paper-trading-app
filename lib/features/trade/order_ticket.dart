import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/tokens.dart';
import '../../market/asset_class.dart';
import '../../market/market_data_service.dart';
import '../../market/models/instrument.dart';
import '../../market/models/quote.dart';
import '../../market/providers/market_data_provider.dart';
import '../../market/quote_repository.dart';
import '../../trading/fee_model.dart';
import '../../trading/order.dart';
import '../../trading/trading_engine.dart';

/// Sizing mode for the quantity field.
enum SizeMode {
  units('UNITS'),
  cash('CASH');

  const SizeMode(this.label);

  final String label;
}

/// Opens the order ticket in a modal (used on narrow layouts).
Future<TradeResult?> showOrderTicket(
  BuildContext context, {
  required TradingEngine engine,
  required MarketDataService marketData,
  required QuoteRepository quotes,
  required Instrument instrument,
  OrderSide initialSide = OrderSide.buy,
  double? initialQuantity,
}) {
  return showDialog<TradeResult>(
    context: context,
    barrierColor: const Color(0xCC000000),
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: SizedBox(
        width: 460,
        child: OrderTicket(
          engine: engine,
          marketData: marketData,
          quotes: quotes,
          instrument: instrument,
          initialSide: initialSide,
          initialQuantity: initialQuantity,
          onClose: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    ),
  );
}

/// The order ticket body. Embeds directly in the Tab 2 split pane, or inside a
/// dialog on narrow layouts.
class OrderTicket extends StatefulWidget {
  const OrderTicket({
    super.key,
    required this.engine,
    required this.marketData,
    required this.quotes,
    required this.instrument,
    this.onClose,
    this.onCompleted,
    this.initialSide = OrderSide.buy,
    this.initialQuantity,
  });

  final TradingEngine engine;
  final MarketDataService marketData;
  final QuoteRepository quotes;
  final Instrument instrument;
  final VoidCallback? onClose;
  final void Function(TradeResult result)? onCompleted;

  /// Pre-fills used by the holdings quick actions.
  final OrderSide initialSide;
  final double? initialQuantity;

  @override
  State<OrderTicket> createState() => _OrderTicketState();
}

class _OrderTicketState extends State<OrderTicket> {
  final TextEditingController _quantity = TextEditingController(text: '1');
  final TextEditingController _limitPrice = TextEditingController();
  final TextEditingController _stopPrice = TextEditingController();

  OrderSide _side = OrderSide.buy;
  OrderType _type = OrderType.market;
  SizeMode _mode = SizeMode.units;

  Quote? _quote;
  bool _loadingQuote = false;
  bool _submitting = false;
  String? _error;
  String? _notice;

  bool get _isBond => widget.instrument.assetClass == AssetClass.bond;

  @override
  void initState() {
    super.initState();
    _side = widget.initialSide;
    if (widget.initialQuantity != null) {
      _quantity.text = formatQuantity(widget.initialQuantity!);
    }
    _quote = widget.quotes.get(widget.instrument.symbol);
    if (_quote == null) _loadQuote();
  }

  @override
  void didUpdateWidget(OrderTicket oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.instrument.symbol != widget.instrument.symbol) {
      _quote = widget.quotes.get(widget.instrument.symbol);
      _error = null;
      _notice = null;
      if (_quote == null) _loadQuote();
    }
  }

  @override
  void dispose() {
    _quantity.dispose();
    _limitPrice.dispose();
    _stopPrice.dispose();
    super.dispose();
  }

  Future<void> _loadQuote() async {
    setState(() {
      _loadingQuote = true;
      _error = null;
    });
    try {
      final quote = await widget.marketData.refreshQuote(widget.instrument);
      if (mounted) setState(() => _quote = quote);
    } on MarketDataException catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } catch (e) {
      if (mounted) setState(() => _error = 'Quote unavailable: $e');
    } finally {
      if (mounted) setState(() => _loadingQuote = false);
    }
  }

  double? _parse(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', ''));

  /// Resolves the entered size into a unit quantity.
  double? get _quantityUnits {
    final entered = _parse(_quantity);
    final price = _quote?.price;
    if (entered == null || entered <= 0) return null;
    if (_mode == SizeMode.units) return entered;
    if (price == null || price <= 0) return null;
    return entered / price;
  }

  double? get _estimatedNotional {
    final units = _quantityUnits;
    final price = _quote?.price;
    if (units == null || price == null || _isBond) return null;
    return units * price;
  }

  Future<void> _submit() async {
    final units = _quantityUnits;
    if (units == null) {
      setState(() => _error = 'Enter a valid ${_mode.label.toLowerCase()} size');
      return;
    }

    final limit = _type == OrderType.limit ? _parse(_limitPrice) : null;
    final stop = _type == OrderType.stop ? _parse(_stopPrice) : null;
    if (_type == OrderType.limit && limit == null) {
      setState(() => _error = 'Enter a limit price');
      return;
    }
    if (_type == OrderType.stop && stop == null) {
      setState(() => _error = 'Enter a stop price');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
      _notice = null;
    });

    try {
      var quote = _quote;
      quote ??= await widget.marketData.refreshQuote(widget.instrument);

      final result = widget.engine.submit(
        instrument: widget.instrument,
        side: _side,
        type: _type,
        quantity: units,
        quote: quote,
        limitPrice: limit,
        stopPrice: stop,
      );

      if (!mounted) return;
      switch (result.status) {
        case OrderStatus.filled:
          setState(() {
            _notice = 'FILLED ${_side.wire} ${_trim(units)} @ '
                '${result.executionPrice?.toStringAsFixed(4)}'
                '${result.fee > 0 ? ' • fee ${formatMoney(result.fee)}' : ''}';
          });
          widget.onCompleted?.call(result);
        case OrderStatus.pending:
          setState(() =>
              _notice = 'RESTING — ${_type.wire} order waiting for a trigger');
          widget.onCompleted?.call(result);
        case OrderStatus.queuedNav:
          setState(() => _notice = 'QUEUED — will settle at the next EOD NAV');
          widget.onCompleted?.call(result);
        case OrderStatus.rejected:
        case OrderStatus.cancelled:
          setState(() => _error = result.rejectionReason ?? 'Order rejected');
      }
    } on MarketDataException catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final instrument = widget.instrument;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.panelDark,
        border: Border.all(
          color: AppColors.hairlineDark,
          width: AppBorders.hairline,
        ),
        borderRadius: AppRadii.mdAll,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(instrument),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sideToggle(),
                const SizedBox(height: AppSpacing.md),
                _chipRow(
                  label: 'ORDER TYPE',
                  options: OrderType.values,
                  selected: _type,
                  labelOf: (t) => t.wire,
                  onSelected: (t) => setState(() {
                    _type = t;
                    _error = null;
                  }),
                ),
                if (!_isBond) ...[
                  const SizedBox(height: AppSpacing.md),
                  _chipRow(
                    label: 'SIZE IN',
                    options: SizeMode.values,
                    selected: _mode,
                    labelOf: (m) => m.label,
                    onSelected: (m) => setState(() {
                      _mode = m;
                      _error = null;
                    }),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                _row('LAST', _formatPrice(_quote)),
                if (_type == OrderType.limit) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _labelledField('LIMIT PRICE', _limitPrice, hint: '0.00'),
                ],
                if (_type == OrderType.stop) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _labelledField('STOP PRICE', _stopPrice, hint: '0.00'),
                ],
                const SizedBox(height: AppSpacing.sm),
                _labelledField(
                  _mode == SizeMode.cash ? 'CASH AMOUNT' : 'QUANTITY',
                  _quantity,
                  hint: _mode == SizeMode.cash ? '0.00' : '0.00',
                  suffix: _mode == SizeMode.cash
                      ? 'USD'
                      : (_isBond ? 'UNITS' : _unitLabel(instrument)),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
          _footer(),
        ],
      ),
    );
  }

  Widget _header(Instrument instrument) {
    final hairline = Theme.of(context).dividerColor;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.raisedDark,
        border: Border(
          bottom: BorderSide(color: hairline, width: AppBorders.hairline),
        ),
      ),
      child: Row(
        children: [
          Text(
            instrument.symbol,
            style: AppTypography.mono(
              size: 14,
              weight: FontWeight.w700,
              color: AppColors.textPrimaryDark,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
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
          Text(
            instrument.assetClass.wire,
            style: AppTypography.mono(
              size: 10,
              color: AppColors.textMutedDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sideToggle() {
    return Row(
      children: [
        Expanded(child: _sideButton(OrderSide.buy, 'BUY', AppColors.positive)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _sideButton(OrderSide.sell, 'SELL', AppColors.negative)),
      ],
    );
  }

  Widget _sideButton(OrderSide side, String label, Color accent) {
    final active = _side == side;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        _side = side;
        _error = null;
      }),
      child: Container(
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.12) : Colors.transparent,
          border: Border.all(
            color: active ? accent : AppColors.hairlineDark,
            width: AppBorders.hairline,
          ),
          borderRadius: AppRadii.smAll,
        ),
        child: Text(
          label,
          style: AppTypography.mono(
            size: 12,
            weight: FontWeight.w700,
            letterSpacing: 0.8,
            color: active ? accent : AppColors.textMutedDark,
          ),
        ),
      ),
    );
  }

  Widget _chipRow<T>({
    required String label,
    required List<T> options,
    required T selected,
    required String Function(T) labelOf,
    required ValueChanged<T> onSelected,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: AppTypography.label(AppColors.textMutedDark),
          ),
        ),
        for (final option in options)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelected(option),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: option == selected
                      ? AppColors.panelDark
                      : Colors.transparent,
                  border: Border.all(
                    color: option == selected
                        ? AppColors.focus
                        : AppColors.hairlineDark,
                    width: AppBorders.hairline,
                  ),
                  borderRadius: AppRadii.smAll,
                ),
                child: Text(
                  labelOf(option),
                  style: AppTypography.mono(
                    size: 10,
                    weight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: option == selected
                        ? AppColors.textPrimaryDark
                        : AppColors.textMutedDark,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Text(label, style: AppTypography.label(AppColors.textMutedDark)),
          const Spacer(),
          Text(
            value,
            style: AppTypography.mono(
              size: 13,
              weight: FontWeight.w600,
              color: AppColors.textPrimaryDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _labelledField(
    String label,
    TextEditingController controller, {
    String? hint,
    String? suffix,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.label(AppColors.textMutedDark)),
        const SizedBox(height: AppSpacing.xs),
        Container(
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
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  style: AppTypography.mono(
                    size: 14,
                    weight: FontWeight.w600,
                    color: AppColors.textPrimaryDark,
                  ),
                  cursorColor: AppColors.focus,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: AppTypography.mono(
                      size: 14,
                      color: AppColors.textMutedDark,
                    ),
                  ),
                ),
              ),
              if (suffix != null)
                Text(
                  suffix,
                  style: AppTypography.mono(
                    size: 10,
                    color: AppColors.textMutedDark,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _footer() {
    final hairline = Theme.of(context).dividerColor;
    final accent = _side == OrderSide.buy
        ? AppColors.positive
        : AppColors.negative;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: hairline, width: AppBorders.hairline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loadingQuote)
            Text(
              'LOADING QUOTE…',
              style: AppTypography.mono(
                size: 10,
                color: AppColors.textMutedDark,
                letterSpacing: 0.6,
              ),
            ),
          if (_estimatedNotional != null)
            _row('EST. NOTIONAL', formatMoney(_estimatedNotional!)),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                _notice!,
                style: AppTypography.mono(
                  size: 11,
                  color: AppColors.positive,
                ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                _error!,
                style: AppTypography.mono(
                  size: 11,
                  color: AppColors.negative,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              if (widget.onClose != null) ...[
                Expanded(
                  child: TextButton(
                    onPressed: _submitting ? null : widget.onClose,
                    style: _buttonStyle(AppColors.textSecondaryDark),
                    child: const Text('CLOSE'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                flex: 2,
                child: TextButton(
                  onPressed: _submitting ? null : _submit,
                  style: _buttonStyle(accent),
                  child: Text(
                    _submitting
                        ? 'SUBMITTING…'
                        : '${_side.wire} ${_type.wire}',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  ButtonStyle _buttonStyle(Color accent) => TextButton.styleFrom(
        minimumSize: const Size(0, 34),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: accent, width: AppBorders.hairline),
          borderRadius: AppRadii.smAll,
        ),
        foregroundColor: accent,
        textStyle: AppTypography.mono(
          size: 11,
          weight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      );

  static String _unitLabel(Instrument instrument) {
    if (instrument.symbol.contains('-')) {
      return instrument.symbol.split('-').first;
    }
    return 'UNITS';
  }

  static String _trim(double value) {
    final text = value.toString();
    return text.length <= 10 ? text : value.toStringAsFixed(6);
  }

  String _formatPrice(Quote? quote) {
    if (quote == null) return '—';
    if (_isBond) return '${quote.price.toStringAsFixed(3)}%';
    return formatMoney(quote.price);
  }
}

/// Exposed for tests: resolve a size entry into units.
double? resolveUnits({
  required String entry,
  required SizeMode mode,
  required double? price,
}) {
  final value = double.tryParse(entry.trim().replaceAll(',', ''));
  if (value == null || value <= 0) return null;
  if (mode == SizeMode.units) return value;
  if (price == null || price <= 0) return null;
  return value / price;
}

/// Exposed for tests: the minimum tradeable step for an instrument.
double minimumStep(Instrument instrument) =>
    FeeModel.quantityStep(instrument.assetClass);

/// Formats a quantity without trailing zeros (0.5000000 -> 0.5).
String formatQuantity(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e12) {
    return value.toStringAsFixed(0);
  }
  final text = value.toStringAsFixed(8);
  return text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}
