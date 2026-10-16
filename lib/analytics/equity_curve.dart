import 'dart:math' as math;

import '../data/models/ledger_event.dart';
import '../sync/hlc.dart';

/// One point on the equity curve.
class EquityPoint {
  const EquityPoint(this.time, this.equity);

  final DateTime time;
  final double equity;
}

/// Chart ranges for the analytics drawer.
enum CurveRange {
  oneDay('1D', Duration(days: 1)),
  oneWeek('1W', Duration(days: 7)),
  oneMonth('1M', Duration(days: 30)),
  oneYear('1Y', Duration(days: 365)),
  all('ALL', null);

  const CurveRange(this.label, this.window);

  final String label;
  final Duration? window;
}

/// Builds equity curves from the append-only ledger.
///
/// Historical points are marked at the **last observed trade price** (the only
/// historical price the app stores); the final point is marked at live prices
/// when they are supplied. This is honest about its basis and needs no
/// historical price feed.
class EquityCurve {
  const EquityCurve._();

  static List<EquityPoint> fromLedger(
    Iterable<LedgerEvent> events, {
    Map<String, double> livePrices = const {},
    DateTime? now,
  }) {
    final sorted = events.toList()
      ..sort((a, b) =>
          Hlc.parse(a.hlcTimestamp).compareTo(Hlc.parse(b.hlcTimestamp)));

    var cash = 0.0;
    final quantities = <String, double>{};
    final marks = <String, double>{};
    final points = <EquityPoint>[];

    for (final event in sorted) {
      switch (event.eventType) {
        case EventType.cashDeposit:
        case EventType.bondCoupon:
          cash += event.quantity;
        case EventType.buy:
        case EventType.sell:
          final symbol = event.symbol;
          if (symbol == null) break;
          final effective = event.executionPrice + event.accruedInterest;
          if (event.eventType == EventType.buy) {
            cash -= (event.quantity * effective) + event.fee;
            quantities[symbol] =
                (quantities[symbol] ?? 0) + event.quantity;
          } else {
            cash += (event.quantity * effective) - event.fee;
            quantities[symbol] =
                (quantities[symbol] ?? 0) - event.quantity;
          }
          marks[symbol] = effective;
        default:
          break;
      }
      points.add(
        EquityPoint(_timeOf(event), _equity(cash, quantities, marks)),
      );
    }

    final live = <String, double>{...marks, ...livePrices};
    final stamp = (now ?? DateTime.now()).toUtc();
    if (points.isEmpty) {
      return [EquityPoint(stamp, 0)];
    }
    // Always append a "now" point so live marks show up on the curve.
    points.add(EquityPoint(stamp, _equity(cash, quantities, live)));
    return points;
  }

  /// Keeps only the points inside the selected window, always including the
  /// most recent point.
  static List<EquityPoint> filter(
    List<EquityPoint> points,
    CurveRange range, {
    DateTime? now,
  }) {
    final window = range.window;
    if (window == null || points.isEmpty) return points;
    final anchor = (now ?? points.last.time).toUtc();
    final cutoff = anchor.subtract(window);

    final inRange =
        points.where((p) => !p.time.toUtc().isBefore(cutoff)).toList();
    if (inRange.length >= 2) return inRange;
    // Not enough history in range: fall back to the last two points.
    return points.length <= 2 ? points : points.sublist(points.length - 2);
  }

  static double _equity(
    double cash,
    Map<String, double> quantities,
    Map<String, double> marks,
  ) {
    var total = cash;
    quantities.forEach((symbol, quantity) {
      final mark = marks[symbol];
      if (mark != null) total += quantity * mark;
    });
    return total;
  }

  static DateTime _timeOf(LedgerEvent event) =>
      Hlc.parse(event.hlcTimestamp).instant;
}

/// Risk-adjusted performance statistics (roadmap section 4.2).
class CurveMetrics {
  const CurveMetrics({
    required this.maxDrawdownFraction,
    required this.maxDrawdownAmount,
    required this.sharpe,
    required this.samples,
  });

  /// Worst peak-to-trough decline as a negative fraction (e.g. -0.12).
  final double maxDrawdownFraction;
  final double maxDrawdownAmount;

  /// Annualised Sharpe ratio; 0 when there is not enough data.
  final double sharpe;

  /// Number of distinct daily observations used.
  final int samples;

  bool get hasSharpe => samples >= 3 && sharpe != 0;

  static CurveMetrics compute(
    List<EquityPoint> points, {
    double riskFreeRateAnnual = 0,
    int annualisationFactor = 252,
  }) {
    if (points.isEmpty) {
      return const CurveMetrics(
        maxDrawdownFraction: 0,
        maxDrawdownAmount: 0,
        sharpe: 0,
        samples: 0,
      );
    }

    // Maximum drawdown.
    var peak = points.first.equity;
    var worstFraction = 0.0;
    var worstAmount = 0.0;
    for (final point in points) {
      if (point.equity > peak) peak = point.equity;
      if (peak > 0) {
        final decline = (point.equity - peak) / peak;
        if (decline < worstFraction) {
          worstFraction = decline;
          worstAmount = point.equity - peak;
        }
      }
    }

    // Sharpe from daily returns.
    final daily = _collapseToDaily(points);
    var sharpe = 0.0;
    if (daily.length >= 3) {
      final returns = <double>[];
      for (var i = 1; i < daily.length; i++) {
        final previous = daily[i - 1].equity;
        if (previous != 0) {
          returns.add((daily[i].equity - previous) / previous);
        }
      }
      if (returns.length >= 2) {
        final mean = returns.reduce((a, b) => a + b) / returns.length;
        final variance = returns
                .map((r) => math.pow(r - mean, 2).toDouble())
                .reduce((a, b) => a + b) /
            (returns.length - 1);
        final deviation = math.sqrt(variance);
        if (deviation > 0) {
          final riskFreeDaily = riskFreeRateAnnual / annualisationFactor;
          sharpe =
              ((mean - riskFreeDaily) / deviation) * math.sqrt(annualisationFactor);
        }
      }
    }

    return CurveMetrics(
      maxDrawdownFraction: worstFraction,
      maxDrawdownAmount: worstAmount,
      sharpe: sharpe,
      samples: daily.length,
    );
  }

  /// Keeps the last equity observation of each UTC day.
  static List<EquityPoint> _collapseToDaily(List<EquityPoint> points) {
    final byDay = <String, EquityPoint>{};
    for (final point in points) {
      final utc = point.time.toUtc();
      final key = '${utc.year}-${utc.month}-${utc.day}';
      byDay[key] = point;
    }
    final daily = byDay.values.toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    return daily;
  }
}
