import 'package:flutter/material.dart';

import '../../analytics/equity_curve.dart';
import '../../design/tokens.dart';

/// Canvas equity curve (roadmap Phase 5). Deliberately flat and hairline-based:
/// no gradients, no glow.
class EquityChart extends StatelessWidget {
  const EquityChart({super.key, required this.points, this.height = 170});

  final List<EquityPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _EquityPainter(
          points: points,
          grid: AppColors.hairlineDark,
        ),
      ),
    );
  }
}

class _EquityPainter extends CustomPainter {
  _EquityPainter({required this.points, required this.grid});

  final List<EquityPoint> points;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    // Hairline grid: a baseline plus quarter lines.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (points.length < 2 || size.width <= 0 || size.height <= 0) return;

    var min = points.first.equity;
    var max = points.first.equity;
    for (final point in points) {
      if (point.equity < min) min = point.equity;
      if (point.equity > max) max = point.equity;
    }
    final span = (max - min).abs() < 1e-9 ? 1.0 : (max - min);

    Offset at(int index) {
      final x = size.width * index / (points.length - 1);
      final normalised = (points[index].equity - min) / span;
      final y = size.height - (normalised * size.height);
      return Offset(x, y);
    }

    final rising = points.last.equity >= points.first.equity;
    final colour = rising ? AppColors.positive : AppColors.negative;

    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      final point = at(i);
      line.lineTo(point.dx, point.dy);
    }

    // Subtle area fill under the curve.
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()..color = colour.withValues(alpha: 0.10),
    );

    canvas.drawPath(
      line,
      Paint()
        ..color = colour
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    // Latest value marker.
    canvas.drawCircle(at(points.length - 1), 2.4, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(_EquityPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.grid != grid;
}
