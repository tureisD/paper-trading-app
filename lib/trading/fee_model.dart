import '../market/asset_class.dart';
import 'order.dart';

/// Per-asset-class execution costs, slippage and quantity precision.
class FeeModel {
  const FeeModel._();

  /// Crypto maker/taker simulation (roadmap phase 3): 0.10%.
  static const double cryptoTakerBps = 10.0;

  /// Simulated bid/ask slippage for equities/ETFs when no book is available:
  /// 0.02%.
  static const double equitySlippageBps = 2.0;

  static double commissionBps(AssetClass assetClass) =>
      assetClass == AssetClass.crypto ? cryptoTakerBps : 0.0;

  static double slippageBps(AssetClass assetClass) =>
      (assetClass == AssetClass.stock || assetClass == AssetClass.etf)
          ? equitySlippageBps
          : 0.0;

  /// Applies slippage in the adverse direction for the given side.
  static double withSlippage(
    double price,
    AssetClass assetClass,
    OrderSide side,
  ) {
    final bps = slippageBps(assetClass);
    if (bps == 0) return price;
    final factor = bps / 10000.0;
    return side == OrderSide.buy ? price * (1 + factor) : price * (1 - factor);
  }

  static double commission(double notional, AssetClass assetClass) =>
      notional * commissionBps(assetClass) / 10000.0;

  /// Minimum tradeable increment for a quantity.
  static double quantityStep(AssetClass assetClass) {
    switch (assetClass) {
      case AssetClass.crypto:
        return 1e-8;
      case AssetClass.stock:
      case AssetClass.etf:
        return 1e-6;
      case AssetClass.fund:
        return 1e-3;
      case AssetClass.bond:
        return 1e-4;
    }
  }

  /// True when [quantity] is positive and a valid multiple of the step.
  static bool isValidQuantity(double quantity, AssetClass assetClass) {
    if (quantity <= 0) return false;
    final step = quantityStep(assetClass);
    final units = quantity / step;
    return (units - units.roundToDouble()).abs() < 1e-6;
  }
}
