import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../design/tokens.dart';
import '../../market/asset_class.dart';
import '../../market/market_data_service.dart';
import '../../market/models/instrument.dart';
import '../../market/models/quote.dart';
import '../../market/providers/market_data_provider.dart';
import '../../market/quote_repository.dart';
import '../../trading/order.dart';
import '../../trading/trading_engine.dart';

/// Opens the compact market-order ticket and returns the resulting trade.
Future<TradeResult?> showOrderTicket(
  BuildContext context, {
  required TradingEngine engine,
  required MarketDataService marketData,
  required QuoteRepository quotes,
  required Instrument instrument,
}) {
  return showDialog<TradeResult>(
    context: context,
    barrierColor: const Color(0xCC000000),
    builder: (_) => _OrderTicket(
      engine: engine,
      marketData: marketData,
      quotes: quotes,
      instrument: instrument,
    ),
  );
}

class _OrderTicket extends StatefulWidget {
  const _OrderTicket({
    required this.engine,
    required this.marketData,
    required this.quotes,
    required this.instrument,
  });

  final TradingEngine engine;
  final MarketDataService marketData;
  final QuoteRepository quotes;
  final Instrument instrument;

  @override
  State<_OrderTicket> createState() => _OrderTicketState();
}

class _OrderTicketState extends State<_OrderTicket> {
  final TextEditingController _quantity = TextEditingController(text: '1');

  OrderSide _side = OrderSide.buy;
  Quote? _quote;
  bool _loadingQuote = false;
  bool _executing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _quote = widget.quotes.get(widget.instrument.symbol);
    if (_quote == null) _loadQuote();
  }

  @override
  void dispose() {
    _quantity.dispose();
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
    } finally {
      if (mounted) setState(() => _loadingQuote = false);
    }
  }

  double? get _parsedQuantity =>
      double.tryParse(_quantity.text.trim().replaceAll(',', ''));

  double? get _notional {
    final qty = _parsedQuantity;
    final quote = _quote;
    if (qty == null || quote == null) return null;
    if (widget.instrument.assetClass == AssetClass.bond) return null;
    return qty * quote.price;
  }

  Future<void> _execute() async {
    final qty = _parsedQuantity;
    if (qty == null || qty <= 0) {
      setState(() => _error = 'Enter a valid quantity');
      return;
    }

    setState(() {
      _executing = true;
      _error = null;
    });
    try {
      var quote = _quote;
      quote ??= await widget.marketData.refreshQuote(widget.instrument);

      final result = widget.engine.submit(
        instrument: widget.instrument,
        side: _side,
        type: OrderType.market,
        quantity: qty,
        quote: quote,
      );

      if (!mounted) return;
      if (result.isFilled || result.isWorking) {
        Navigator.of(context).pop(result);
      } else {
        setState(() => _error = result.rejectionReason ?? 'Order rejected');
      }
    } on MarketDataException catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _executing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final instrument = widget.instrument;
    final quote = _quote;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 420,
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
                  const SizedBox(height: AppSpacing.lg),
                  _row('LAST', _formatPrice(instrument, quote)),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'QUANTITY',
                    style: AppTypography.label(AppColors.textMutedDark),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _quantityField(),
                ],
              ),
            ),
            _footer(),
          ],
        ),
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
        height: 34,
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

  Widget _quantityField() {
    return Container(
      height: 36,
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
              controller: _quantity,
              autofocus: true,
              style: AppTypography.mono(
                size: 14,
                weight: FontWeight.w600,
                color: AppColors.textPrimaryDark,
              ),
              cursorColor: AppColors.focus,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '0.00',
                hintStyle: AppTypography.mono(
                  size: 14,
                  color: AppColors.textMutedDark,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Text(
            widget.instrument.symbol.contains('-')
                ? widget.instrument.symbol.split('-').first
                : 'UNITS',
            style: AppTypography.mono(
              size: 10,
              color: AppColors.textMutedDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    final hairline = Theme.of(context).dividerColor;
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
          if (_notional != null)
            _row('EST. NOTIONAL', formatMoney(_notional!)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
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
              Expanded(
                child: TextButton(
                  onPressed: _executing
                      ? null
                      : () => Navigator.of(context).pop(),
                  style: _buttonStyle(AppColors.textSecondaryDark),
                  child: Text('CANCEL'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextButton(
                  onPressed: _executing ? null : _execute,
                  style: _buttonStyle(
                    _side == OrderSide.buy
                        ? AppColors.positive
                        : AppColors.negative,
                  ),
                  child: Text(_executing ? 'EXECUTING…' : 'EXECUTE'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  ButtonStyle _buttonStyle(Color accent) => TextButton.styleFrom(
        minimumSize: const Size(0, 36),
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

  static String _formatPrice(Instrument instrument, Quote? quote) {
    if (quote == null) return '—';
    if (instrument.assetClass == AssetClass.bond) {
      return '${quote.price.toStringAsFixed(3)}%';
    }
    return formatMoney(quote.price);
  }
}
