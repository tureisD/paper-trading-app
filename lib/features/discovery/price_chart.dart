import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../market/models/candle.dart';

/// How the price history is drawn.
enum ChartStyle {
  candles('CANDLES'),
  line('LINE');

  const ChartStyle(this.label);

  final String label;

  ChartStyle get other => this == candles ? line : candles;
}

/// Price history: candlesticks with a volume strip, a line, or a yield line for
/// bond series (which have no intraday range).
///
/// Tapping the chart flips between candlesticks and line ([onToggleStyle]).
class PriceChart extends StatelessWidget {
  const PriceChart({
    super.key,
    required this.candles,
    this.isYieldSeries = false,
    this.height = 220,
    this.style = ChartStyle.candles,
    this.currentPrice,
    this.onToggleStyle,
  });

  final List<Candle> candles;
  final bool isYieldSeries;
  final double height;
  final ChartStyle style;

  /// Draws a dashed marker at the live level when supplied.
  final double? currentPrice;

  final VoidCallback? onToggleStyle;

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

    // A yield series has no open/high/low, so it is always a line.
    final effectiveStyle = isYieldSeries ? ChartStyle.line : style;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isYieldSeries ? null : onToggleStyle,
      child: MouseRegion(
        cursor: onToggleStyle == null || isYieldSeries
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _PricePainter(
              candles: candles,
              style: effectiveStyle,
              currentPrice: currentPrice,
              grid: AppColors.hairlineDark,
            ),
          ),
        ),
      ),
    );
  }
}

class _PricePainter extends CustomPainter {
  _PricePainter({
    required this.candles,
    required this.style,
    required this.grid,
    this.currentPrice,
  });

  final List<Candle> candles;
  final ChartStyle style;
  final Color grid;
  final double? currentPrice;

  static const double _axisRight = 62;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= _axisRight + 4 || size.height <= 8) return;

    final plotWidth = size.width - _axisRight;
    final showVolume = style == ChartStyle.candles;
    final volumeHeight = showVolume ? size.height * 0.2 : 0.0;
    final priceHeight = size.height - volumeHeight - 4;
    const priceTop = 2.0;

    var low = candles.first.low;
    var high = candles.first.high;
    for (final candle in candles) {
      if (candle.low < low) low = candle.low;
      if (candle.high > high) high = candle.high;
    }
    // Keep the live marker on screen.
    final marker = currentPrice;
    if (marker != null) {
      if (marker < low) low = marker;
      if (marker > high) high = marker;
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
      _text(
        canvas,
        (high - (span * i / 4)).toStringAsFixed(2),
        Offset(plotWidth + 6, y - 5),
        labelStyle,
      );
    }

    final slot = plotWidth / candles.length;
    final bodyWidth = (slot * 0.62).clamp(1.0, 14.0);
    final rising = candles.last.close >= candles.first.close;
    final accent = rising ? AppColors.positive : AppColors.negative;

    if (style == ChartStyle.line) {
      final line = Path();
      for (var i = 0; i < candles.length; i++) {
        final x = slot * (i + 0.5);
        final y = yFor(candles[i].close);
        if (i == 0) {
          line.moveTo(x, y);
        } else {
          line.lineTo(x, y);
        }
      }
      final area = Path.from(line)
        ..lineTo(plotWidth, priceTop + priceHeight)
        ..lineTo(0, priceTop + priceHeight)
        ..close();
      canvas.drawPath(area, Paint()..color = accent.withValues(alpha: 0.10));
      canvas.drawPath(
        line,
        Paint()
          ..color = accent
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawCircle(
        Offset(slot * (candles.length - 0.5), yFor(candles.last.close)),
        2.4,
        Paint()..color = accent,
      );
    } else {
      var maxVolume = 0.0;
      for (final candle in candles) {
        final v = candle.volume ?? 0;
        if (v > maxVolume) maxVolume = v;
      }

      for (var i = 0; i < candles.length; i++) {
        final candle = candles[i];
        final centre = slot * (i + 0.5);
        final candleRising = candle.close >= candle.open;
        final colour = candleRising ? AppColors.positive : AppColors.negative;
        final paint = Paint()..color = colour;

        canvas.drawRect(
          Rect.fromLTRB(
            centre - 0.5,
            yFor(candle.high),
            centre + 0.5,
            yFor(candle.low),
          ),
          paint,
        );

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

    // Dashed marker at the live price.
    if (marker != null && marker >= low && marker <= high) {
      final y = yFor(marker);
      _dashedLine(canvas, Offset(0, y), Offset(plotWidth, y), accent);
      _text(
        canvas,
        marker.toStringAsFixed(2),
        Offset(plotWidth + 6, y - 5),
        AppTypography.mono(
          size: 9,
          weight: FontWeight.w700,
          color: accent,
        ),
      );
    }
  }

  void _dashedLine(Canvas canvas, Offset from, Offset to, Color colour) {
    final paint = Paint()
      ..color = colour.withValues(alpha: 0.75)
      ..strokeWidth = 1;
    const dash = 4.0;
    const gap = 3.0;
    final total = (to - from).distance;
    if (total <= 0) return;
    final direction = (to - from) / total;
    var travelled = 0.0;
    while (travelled < total) {
      final end = (travelled + dash).clamp(0.0, total);
      canvas.drawLine(
        from + direction * travelled,
        from + direction * end,
        paint,
      );
      travelled = end + gap;
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
      oldDelegate.style != style ||
      oldDelegate.currentPrice != currentPrice ||
      oldDelegate.grid != grid;
}
