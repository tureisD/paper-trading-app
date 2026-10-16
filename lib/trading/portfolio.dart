import '../market/asset_class.dart';

/// Direction of a P&L figure, for semantic colouring in the UI.
enum PnlSign { positive, negative, flat }

/// A single holding, expressed in Weighted Average Cost terms.
class Position {
  const Position({
    required this.symbol,
    required this.assetClass,
    this.quantity = 0.0,
    this.averageCost = 0.0,
    this.realisedPnl = 0.0,
  });

  final String symbol;
  final AssetClass assetClass;
  final double quantity;
  final double averageCost;
  final double realisedPnl;

  static Position empty(String symbol, AssetClass assetClass) =>
      Position(symbol: symbol, assetClass: assetClass);

  bool get isEmpty => quantity.abs() < 1e-12;

  double get costBasis => quantity * averageCost;

  double marketValue(double price) => quantity * price;

  /// Unrealised P&L, roadmap 4.1: Q_t * (P_mkt - C_avg).
  double unrealisedPnl(double price) => quantity * (price - averageCost);

  /// Unrealised return %, roadmap 4.1.
  double unrealisedPercent(double price) {
    if (averageCost == 0) return 0;
    return ((price - averageCost) / averageCost) * 100;
  }

  Position copyWith({
    double? quantity,
    double? averageCost,
    double? realisedPnl,
  }) {
    return Position(
      symbol: symbol,
      assetClass: assetClass,
      quantity: quantity ?? this.quantity,
      averageCost: averageCost ?? this.averageCost,
      realisedPnl: realisedPnl ?? this.realisedPnl,
    );
  }

  static PnlSign signOf(double value) {
    if (value > 0) return PnlSign.positive;
    if (value < 0) return PnlSign.negative;
    return PnlSign.flat;
  }
}

/// A position marked to a market price.
class PositionOverview {
  const PositionOverview({
    required this.position,
    required this.price,
    required this.marketValue,
    required this.unrealisedPnl,
    required this.unrealisedPercent,
    required this.sign,
  });

  final Position position;
  final double price;
  final double marketValue;
  final double unrealisedPnl;
  final double unrealisedPercent;
  final PnlSign sign;
}

/// Derived portfolio state — never persisted authoritatively, always replayable
/// from the append-only ledger.
class PortfolioSnapshot {
  const PortfolioSnapshot({required this.cash, required this.positions});

  final double cash;
  final Map<String, Position> positions;

  Iterable<Position> get openPositions =>
      positions.values.where((p) => !p.isEmpty);

  double get realisedPnl =>
      positions.values.fold(0.0, (sum, p) => sum + p.realisedPnl);

  /// Total capital currently tied up at cost.
  double get investedCost =>
      openPositions.fold(0.0, (sum, p) => sum + p.costBasis);

  Position positionFor(String symbol) => positions[symbol] ?? Position.empty(symbol, AssetClass.stock);

  PositionOverview overviewFor(String symbol, double price) {
    final position = positions[symbol] ?? Position.empty(symbol, AssetClass.stock);
    final pnl = position.unrealisedPnl(price);
    return PositionOverview(
      position: position,
      price: price,
      marketValue: position.marketValue(price),
      unrealisedPnl: pnl,
      unrealisedPercent: position.unrealisedPercent(price),
      sign: Position.signOf(pnl),
    );
  }
}
