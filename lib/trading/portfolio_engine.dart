import '../data/models/ledger_event.dart';
import '../market/asset_class.dart';
import 'order.dart';
import 'portfolio.dart';

/// Deterministic transformation of the append-only ledger into portfolio state.
///
/// Both devices replay the same events in the same order and therefore arrive
/// at byte-identical cash, cost basis and realised P&L.
class PortfolioEngine {
  const PortfolioEngine._();

  static PortfolioSnapshot replay(Iterable<LedgerEvent> events) {
    final sorted = events.toList()
      ..sort((a, b) {
        final byTime = a.hlcTimestamp.compareTo(b.hlcTimestamp);
        return byTime != 0 ? byTime : a.eventId.compareTo(b.eventId);
      });

    var cash = 0.0;
    final positions = <String, Position>{};

    for (final event in sorted) {
      final symbol = event.symbol;
      final assetClass =
          AssetClass.tryParse(event.assetClass) ?? AssetClass.stock;

      switch (event.eventType) {
        case EventType.cashDeposit:
        case EventType.bondCoupon:
          cash += event.quantity;
          break;

        case EventType.cashWithdrawal:
          cash -= event.quantity;
          break;

        case EventType.buy:
        case EventType.sell:
          if (symbol == null) break;
          final side = event.eventType == EventType.buy
              ? OrderSide.buy
              : OrderSide.sell;
          // Bonds settle on the dirty price; other classes have zero accrued.
          final effectivePrice =
              event.executionPrice + event.accruedInterest;

          if (side == OrderSide.buy) {
            cash -= (event.quantity * effectivePrice) + event.fee;
          } else {
            cash += (event.quantity * effectivePrice) - event.fee;
          }

          positions[symbol] = applyTrade(
            positions[symbol] ?? Position.empty(symbol, assetClass),
            side: side,
            quantity: event.quantity,
            price: effectivePrice,
            fee: event.fee,
          );
          break;

        default:
          break;
      }
    }

    return PortfolioSnapshot(cash: cash, positions: positions);
  }

  /// Weighted Average Cost update (roadmap section 4.1).
  static Position applyTrade(
    Position position, {
    required OrderSide side,
    required double quantity,
    required double price,
    double fee = 0,
  }) {
    if (quantity <= 0) return position;

    if (side == OrderSide.buy) {
      final newQuantity = position.quantity + quantity;
      final newCostBasis =
          (position.quantity * position.averageCost) + (quantity * price) + fee;
      return position.copyWith(
        quantity: newQuantity,
        averageCost: newQuantity.abs() < 1e-12 ? 0 : newCostBasis / newQuantity,
      );
    }

    // SELL: realised P&L locks in; the average cost of remaining units stands.
    final realised =
        position.realisedPnl + (quantity * (price - position.averageCost)) - fee;
    final newQuantity = position.quantity - quantity;
    return position.copyWith(
      quantity: newQuantity,
      averageCost: newQuantity.abs() < 1e-12 ? 0 : position.averageCost,
      realisedPnl: realised,
    );
  }
}
