import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../market/models/candle.dart';

/// Candlestick chart with a volume strip, or a yield line for bond series
/// (roadmap Phase 6). Hand-drawn on canvas: hairline grid, no decoration.
class PriceChart extends StatelessWidget {
  const PriceChart({
    super.key,
    required this.candles,
    this.isYieldSeries = false,
    this.height = 220,
  });

  final List<Candle> candles;
  final bool isYieldSeries;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (candles.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'NO CHART DATA',
            style: AppTypography.mono(
              size: 10,
              color: AppColors.textMutedDark,
              letterSpacing: 1.0,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _PricePainter(
          candles: candles,
          isYieldSeries: isYieldSeries,
          grid: AppColors.hairlineDark,
        ),
      ),
    );
  }
}

class _PricePainter extends CustomPainter {
  _PricePainter({
    required this.candles,
    required this.isYieldSeries,
    required this.grid,
  });

  final List<Candle> candles;
  final bool isYieldSeries;
  final Color grid;

  static const double _axisRight = 62;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= _axisRight + 4 || size.height <= 8) return;

    final plotWidth = size.width - _axisRight;
    final volumeHeight = isYieldSeries ? 0.0 : size.height * 0.2;
    final priceHeight = size.height - volumeHeight - 4;
    final priceTop = 2.0;

    var low = candles.first.low;
    var high = candles.first.high;
    for (final candle in candles) {
      if (candle.low < low) low = candle.low;
      if (candle.high > high) high = candle.high;
    }
    final span = (high - low).abs() < 1e-9 ? 1.0 : high - low;

    double yFor(double price) =>
        priceTop + priceHeight - ((price - low) / span) * priceHeight;

    // Hairline grid + right-hand price labels.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final labelStyle = AppTypography.mono(
      size: 9,
      color: AppColors.textMutedDark,
    );
    for (var i = 0; i <= 4; i++) {
      final y = priceTop + priceHeight * i / 4;
      canvas.drawLine(Offset(0, y), Offset(plotWidth, y), gridPaint);
      final price = high - (span * i / 4);
      _text(canvas, price.toStringAsFixed(isYieldSeries ? 3 : 2),
          Offset(plotWidth + 6, y - 5), labelStyle);
    }

    final slot = plotWidth / candles.length;
    final bodyWidth = (slot * 0.62).clamp(1.0, 14.0);

    if (isYieldSeries) {
      // Yields have no intraday range: draw a line through close values.
      final path = Path();
      for (var i = 0; i < candles.length; i++) {
        final x = slot * (i + 0.5);
        final y = yFor(candles[i].close);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.neutral
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
      return;
    }

    // Volume strip scale.
    var maxVolume = 0.0;
    for (final candle in candles) {
      final v = candle.volume ?? 0;
      if (v > maxVolume) maxVolume = v;
    }

    for (var i = 0; i < candles.length; i++) {
      final candle = candles[i];
      final centre = slot * (i + 0.5);
      final rising = candle.close >= candle.open;
      final colour = rising ? AppColors.positive : AppColors.negative;
      final paint = Paint()..color = colour;

      // Wick.
      canvas.drawRect(
        Rect.fromLTRB(
          centre - 0.5,
          yFor(candle.high),
          centre + 0.5,
          yFor(candle.low),
        ),
        paint,
      );

      // Body.
      final openY = yFor(candle.open);
      final closeY = yFor(candle.close);
      final top = openY < closeY ? openY : closeY;
      final bottom = openY < closeY ? closeY : openY;
      canvas.drawRect(
        Rect.fromLTRB(
          centre - bodyWidth / 2,
          top,
          centre + bodyWidth / 2,
          (bottom - top).abs() < 1 ? top + 1 : bottom,
        ),
        paint,
      );

      // Volume bar.
      final volume = candle.volume ?? 0;
      if (maxVolume > 0 && volume > 0) {
        final barHeight = (volume / maxVolume) * (volumeHeight - 4);
        canvas.drawRect(
          Rect.fromLTRB(
            centre - bodyWidth / 2,
            size.height - barHeight,
            centre + bodyWidth / 2,
            size.height,
          ),
          Paint()..color = colour.withValues(alpha: 0.35),
        );
      }
    }
  }

  void _text(Canvas canvas, String value, Offset at, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_PricePainter oldDelegate) =>
      oldDelegate.candles != candles ||
      oldDelegate.isYieldSeries != isYieldSeries ||
      oldDelegate.grid != grid;
}
