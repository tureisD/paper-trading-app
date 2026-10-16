import '../data/models/ledger_event.dart';
import '../sync/hlc.dart';

/// Realised-trade statistics for the analytics drawer.
class TradeStats {
  const TradeStats({
    required this.wins,
    required this.losses,
    required this.total,
    required this.averageWin,
    required this.averageLoss,
    required this.realisedTotal,
  });

  final int wins;
  final int losses;
  final int total;
  final double averageWin;
  final double averageLoss;
  final double realisedTotal;

  static const TradeStats empty = TradeStats(
    wins: 0,
    losses: 0,
    total: 0,
    averageWin: 0,
    averageLoss: 0,
    realisedTotal: 0,
  );

  double get winRate => total == 0 ? 0 : (wins / total) * 100;

  /// Wins per loss. Returns null when there are no losses to divide by.
  double? get winLossRatio => losses == 0 ? null : wins / losses;

  static TradeStats fromRealisations(Iterable<double> realisations) {
    final values = realisations.toList(growable: false);
    if (values.isEmpty) return empty;

    var wins = 0;
    var losses = 0;
    var winSum = 0.0;
    var lossSum = 0.0;
    var total = 0.0;

    for (final value in values) {
      total += value;
      if (value > 0) {
        wins++;
        winSum += value;
      } else if (value < 0) {
        losses++;
        lossSum += value;
      }
    }

    return TradeStats(
      wins: wins,
      losses: losses,
      total: values.length,
      averageWin: wins == 0 ? 0 : winSum / wins,
      averageLoss: losses == 0 ? 0 : lossSum / losses,
      realisedTotal: total,
    );
  }

  /// Realised P&L for each closing (SELL) trade, using Weighted Average Cost,
  /// matching the replay used everywhere else.
  static List<double> realisedTrades(Iterable<LedgerEvent> events) {
    final sorted = events.toList()
      ..sort((a, b) =>
          Hlc.parse(a.hlcTimestamp).compareTo(Hlc.parse(b.hlcTimestamp)));

    final quantities = <String, double>{};
    final averageCosts = <String, double>{};
    final realisations = <double>[];

    for (final event in sorted) {
      final symbol = event.symbol;
      if (symbol == null) continue;
      final effective = event.executionPrice + event.accruedInterest;

      switch (event.eventType) {
        case EventType.buy:
          final quantity = (quantities[symbol] ?? 0) + event.quantity;
          final cost =
              (quantities[symbol] ?? 0) * (averageCosts[symbol] ?? 0) +
                  event.quantity * effective +
                  event.fee;
          quantities[symbol] = quantity;
          averageCosts[symbol] = quantity == 0 ? 0 : cost / quantity;
        case EventType.sell:
          final costBasis = averageCosts[symbol] ?? 0;
          realisations.add(
            event.quantity * (effective - costBasis) - event.fee,
          );
          final remaining = (quantities[symbol] ?? 0) - event.quantity;
          quantities[symbol] = remaining;
          if (remaining.abs() < 1e-12) averageCosts[symbol] = 0;
        default:
          break;
      }
    }
    return realisations;
  }
}
