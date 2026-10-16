import '../market/asset_class.dart';
import '../market/models/instrument.dart';
import '../market/models/quote.dart';
import '../trading/bond_math.dart';
import '../trading/portfolio.dart';

/// A holding marked to market, shaped for the Tab 1 table.
class HoldingView {
  const HoldingView({
    required this.position,
    required this.instrument,
    required this.quote,
    required this.price,
    required this.marketValue,
    required this.unrealisedPnl,
    required this.unrealisedPercent,
    required this.weightPercent,
    required this.sign,
  });

  final Position position;
  final Instrument? instrument;
  final Quote? quote;

  /// Live price, or average cost when no quote is available.
  final double price;
  final double marketValue;
  final double unrealisedPnl;
  final double unrealisedPercent;
  final double weightPercent;
  final PnlSign sign;

  String get symbol => position.symbol;
  String get isin => instrument?.isin ?? '—';
  AssetClass get assetClass => position.assetClass;
  double get quantity => position.quantity;
  double get averageCost => position.averageCost;
  bool get hasQuote => quote != null;
}

/// Account-level summary plus per-holding rows (roadmap Phase 5).
class PortfolioAnalytics {
  const PortfolioAnalytics({
    required this.cash,
    required this.marketValue,
    required this.netLiquidation,
    required this.dayPnl,
    required this.dayPnlPercent,
    required this.realisedPnl,
    required this.unrealisedPnl,
    required this.totalPnl,
    required this.totalPnlPercent,
    required this.buyingPower,
    required this.accruedInterestReceivable,
    required this.netDeposits,
    required this.holdings,
    required this.allocation,
  });

  final double cash;
  final double marketValue;

  /// Cash plus the market value of everything held.
  final double netLiquidation;

  /// Mark-to-market move against the previous close.
  final double dayPnl;
  final double dayPnlPercent;

  final double realisedPnl;
  final double unrealisedPnl;

  /// Realised plus unrealised.
  final double totalPnl;
  final double totalPnlPercent;

  /// Immediately tradable cash (no margin).
  final double buyingPower;

  /// Coupon income earned but not yet paid.
  final double accruedInterestReceivable;

  /// Total cash ever deposited.
  final double netDeposits;

  final List<HoldingView> holdings;

  /// Market value by asset class.
  final Map<AssetClass, double> allocation;

  bool get isEmpty => holdings.isEmpty;
}

/// Derives [PortfolioAnalytics] from replayed state plus market data.
class PortfolioAnalyticsBuilder {
  const PortfolioAnalyticsBuilder._();

  static PortfolioAnalytics build({
    required PortfolioSnapshot snapshot,
    required Map<String, Instrument> instruments,
    required Map<String, Quote> quotes,
    required Map<String, BondDetails> bonds,
    required double netDeposits,
    DateTime? asOf,
  }) {
    final at = (asOf ?? DateTime.now()).toUtc();
    final holdings = <HoldingView>[];
    final allocation = <AssetClass, double>{};

    var marketValue = 0.0;
    var unrealised = 0.0;
    var dayPnl = 0.0;
    var accruedReceivable = 0.0;

    for (final position in snapshot.openPositions) {
      final quote = quotes[position.symbol];
      final price = quote?.price ?? position.averageCost;

      final value = position.marketValue(price);
      final pnl = position.unrealisedPnl(price);

      marketValue += value;
      unrealised += pnl;

      // Day move: prefer the quote's own change, else recompute from close.
      final change = quote?.change ??
          ((quote?.previousClose ?? 0) != 0
              ? price - quote!.previousClose!
              : 0.0);
      dayPnl += position.quantity * change;

      accruedReceivable += _accruedFor(position, bonds[position.symbol], at);
      allocation.update(
        position.assetClass,
        (existing) => existing + value,
        ifAbsent: () => value,
      );

      holdings.add(
        HoldingView(
          position: position,
          instrument: instruments[position.symbol],
          quote: quote,
          price: price,
          marketValue: value,
          unrealisedPnl: pnl,
          unrealisedPercent: position.unrealisedPercent(price),
          weightPercent: 0, // filled in below once the total is known.
          sign: Position.signOf(pnl),
        ),
      );
    }

    final netLiquidation = snapshot.cash + marketValue;
    final realised = snapshot.realisedPnl;
    final totalPnl = realised + unrealised;

    final weighted = <HoldingView>[];
    for (final holding in holdings) {
      weighted.add(
        HoldingView(
          position: holding.position,
          instrument: holding.instrument,
          quote: holding.quote,
          price: holding.price,
          marketValue: holding.marketValue,
          unrealisedPnl: holding.unrealisedPnl,
          unrealisedPercent: holding.unrealisedPercent,
          weightPercent: netLiquidation == 0
              ? 0
              : (holding.marketValue / netLiquidation) * 100,
          sign: holding.sign,
        ),
      );
    }
    weighted.sort((a, b) => b.marketValue.compareTo(a.marketValue));

    return PortfolioAnalytics(
      cash: snapshot.cash,
      marketValue: marketValue,
      netLiquidation: netLiquidation,
      dayPnl: dayPnl,
      dayPnlPercent: (netLiquidation - dayPnl) == 0
          ? 0
          : (dayPnl / (netLiquidation - dayPnl)) * 100,
      realisedPnl: realised,
      unrealisedPnl: unrealised,
      totalPnl: totalPnl,
      totalPnlPercent: netDeposits == 0 ? 0 : (totalPnl / netDeposits) * 100,
      buyingPower: snapshot.cash,
      accruedInterestReceivable: accruedReceivable,
      netDeposits: netDeposits,
      holdings: weighted,
      allocation: allocation,
    );
  }

  static double _accruedFor(
    Position position,
    BondDetails? details,
    DateTime asOf,
  ) {
    if (position.assetClass != AssetClass.bond) return 0;
    final rate = details?.couponRate;
    final maturity = BondMath.parseDateUtc(details?.maturityDate);
    if (rate == null || maturity == null) return 0;
    final perUnit = BondMath.accruedAt(
      asOf: asOf,
      maturity: maturity,
      parValue: details!.parValue ?? 100,
      annualCouponRate: rate,
      paymentsPerYear: details.couponFrequency ?? 2,
    );
    return perUnit * position.quantity;
  }
}
