import 'package:flutter_test/flutter_test.dart';
import 'package:paper_trading_app/analytics/equity_curve.dart';
import 'package:paper_trading_app/analytics/equity_snapshot_repository.dart';
import 'package:paper_trading_app/analytics/portfolio_analytics.dart';
import 'package:paper_trading_app/analytics/trade_stats.dart';
import 'package:paper_trading_app/data/app_database.dart';
import 'package:paper_trading_app/data/models/ledger_event.dart';
import 'package:paper_trading_app/market/asset_class.dart';
import 'package:paper_trading_app/market/models/instrument.dart';
import 'package:paper_trading_app/market/models/quote.dart';
import 'package:paper_trading_app/trading/portfolio.dart';

const _apple = Instrument(
  symbol: 'AAPL',
  name: 'Apple Inc.',
  assetClass: AssetClass.stock,
  isin: 'US0378331005',
);

LedgerEvent _event({
  required String type,
  required String hlc,
  String? symbol,
  String? assetClass,
  double quantity = 0,
  double price = 0,
  double fee = 0,
  String id = 'e',
  String device = 'device_a',
}) {
  return LedgerEvent(
    eventId: id,
    hlcTimestamp: hlc,
    deviceId: device,
    eventType: type,
    symbol: symbol,
    assetClass: assetClass,
    quantity: quantity,
    executionPrice: price,
    fee: fee,
  );
}

void main() {
  group('PortfolioAnalyticsBuilder', () {
    test('derives NLV, day P&L, weights and allocation', () {
      final snapshot = PortfolioSnapshot(
        cash: 5000,
        positions: {
          'AAPL': const Position(
            symbol: 'AAPL',
            assetClass: AssetClass.stock,
            quantity: 10,
            averageCost: 100,
          ),
        },
      );

      final analytics = PortfolioAnalyticsBuilder.build(
        snapshot: snapshot,
        instruments: {'AAPL': _apple},
        quotes: {
          'AAPL': Quote.derive(
            symbol: 'AAPL',
            price: 110,
            previousClose: 105,
            source: 'test',
            asOf: DateTime.utc(2026, 1, 2),
          ),
        },
        bonds: const {},
        netDeposits: 6000,
        asOf: DateTime.utc(2026, 1, 2),
      );

      expect(analytics.marketValue, closeTo(1100, 1e-9));
      expect(analytics.netLiquidation, closeTo(6100, 1e-9));
      expect(analytics.unrealisedPnl, closeTo(100, 1e-9));
      expect(analytics.dayPnl, closeTo(50, 1e-9)); // 10 * (110 - 105)
      expect(analytics.buyingPower, closeTo(5000, 1e-9));
      expect(analytics.totalPnl, closeTo(100, 1e-9));
      expect(analytics.totalPnlPercent, closeTo(100 / 6000 * 100, 1e-9));
      expect(analytics.allocation[AssetClass.stock], closeTo(1100, 1e-9));

      final holding = analytics.holdings.single;
      expect(holding.isin, 'US0378331005');
      expect(holding.hasQuote, isTrue);
      expect(holding.weightPercent, closeTo(1100 / 6100 * 100, 1e-9));
      expect(holding.sign, PnlSign.positive);
    });

    test('falls back to average cost when no quote is available', () {
      final analytics = PortfolioAnalyticsBuilder.build(
        snapshot: const PortfolioSnapshot(
          cash: 0,
          positions: {
            'AAPL': Position(
              symbol: 'AAPL',
              assetClass: AssetClass.stock,
              quantity: 2,
              averageCost: 50,
            ),
          },
        ),
        instruments: const {},
        quotes: const {},
        bonds: const {},
        netDeposits: 100,
      );

      expect(analytics.holdings.single.price, 50);
      expect(analytics.unrealisedPnl, 0);
      expect(analytics.holdings.single.hasQuote, isFalse);
    });

    test('accrues bond interest receivable', () {
      final analytics = PortfolioAnalyticsBuilder.build(
        snapshot: const PortfolioSnapshot(
          cash: 0,
          positions: {
            'TESTBOND': Position(
              symbol: 'TESTBOND',
              assetClass: AssetClass.bond,
              quantity: 10,
              averageCost: 101.25,
            ),
          },
        ),
        instruments: const {},
        quotes: const {},
        bonds: const {
          'TESTBOND': BondDetails(
            symbol: 'TESTBOND',
            couponRate: 0.05,
            maturityDate: '2030-01-15',
            parValue: 100,
            couponFrequency: 2,
          ),
        },
        netDeposits: 2000,
        asOf: DateTime.utc(2029, 10, 15),
      );

      // Halfway through the Jul->Jan coupon period: 2.5 per unit * 10 units.
      expect(analytics.accruedInterestReceivable, closeTo(12.5, 1e-9));
    });
  });

  group('EquityCurve', () {
    test('marks historical points at trade prices and the last point live', () {
      final events = [
        _event(
          type: EventType.cashDeposit,
          hlc: '2026-01-01T00:00:00.000Z#000000',
          quantity: 10000,
          id: 'd1',
        ),
        _event(
          type: EventType.buy,
          hlc: '2026-01-02T00:00:00.000Z#000000',
          symbol: 'AAPL',
          assetClass: 'STOCK',
          quantity: 10,
          price: 100,
          id: 'b1',
        ),
      ];

      final curve = EquityCurve.fromLedger(
        events,
        livePrices: const {'AAPL': 120},
        now: DateTime.utc(2026, 1, 3),
      );

      // deposit point, buy point (marked at 100), and the live point at 120.
      expect(curve, hasLength(3));
      expect(curve[0].equity, closeTo(10000, 1e-9));
      expect(curve[1].equity, closeTo(10000, 1e-9)); // cash 9000 + 10*100
      expect(curve.last.equity, closeTo(10200, 1e-9)); // cash 9000 + 10*120
    });

    test('filters by window but always keeps the latest point', () {
      final points = [
        EquityPoint(DateTime.utc(2025, 1, 1), 100),
        EquityPoint(DateTime.utc(2026, 1, 1), 110),
        EquityPoint(DateTime.utc(2026, 1, 2), 120),
      ];
      final filtered = EquityCurve.filter(
        points,
        CurveRange.oneMonth,
        now: DateTime.utc(2026, 1, 2),
      );
      expect(filtered.last.equity, 120);
      expect(filtered.length, lessThan(points.length));
    });
  });

  group('CurveMetrics', () {
    test('computes maximum drawdown from the peak', () {
      final metrics = CurveMetrics.compute([
        EquityPoint(_t(1), 100),
        EquityPoint(_t(2), 120),
        EquityPoint(_t(3), 90),
        EquityPoint(_t(4), 130),
      ]);

      expect(metrics.maxDrawdownFraction, closeTo(-0.25, 1e-9));
      expect(metrics.maxDrawdownAmount, closeTo(-30, 1e-9));
    });

    test('computes an annualised Sharpe from daily observations', () {
      final metrics = CurveMetrics.compute([
        EquityPoint(DateTime.utc(2026, 1, 1), 100),
        EquityPoint(DateTime.utc(2026, 1, 2), 101),
        EquityPoint(DateTime.utc(2026, 1, 3), 102),
        EquityPoint(DateTime.utc(2026, 1, 4), 103),
      ]);

      expect(metrics.samples, 4);
      expect(metrics.hasSharpe, isTrue);
      expect(metrics.sharpe, greaterThan(0));
    });

    test('reports no Sharpe with too little history', () {
      final metrics = CurveMetrics.compute([
        EquityPoint(DateTime.utc(2026, 1, 1), 100),
        EquityPoint(DateTime.utc(2026, 1, 2), 101),
      ]);
      expect(metrics.hasSharpe, isFalse);
    });
  });

  group('TradeStats', () {
    test('extracts per-trade realisations with Weighted Average Cost', () {
      final events = [
        _event(
          type: EventType.buy,
          hlc: '2026-01-01T00:00:00.000Z#000000',
          symbol: 'AAPL',
          assetClass: 'STOCK',
          quantity: 10,
          price: 100,
          id: 'b1',
        ),
        _event(
          type: EventType.sell,
          hlc: '2026-01-02T00:00:00.000Z#000000',
          symbol: 'AAPL',
          assetClass: 'STOCK',
          quantity: 5,
          price: 120,
          id: 's1',
        ),
        _event(
          type: EventType.sell,
          hlc: '2026-01-03T00:00:00.000Z#000000',
          symbol: 'AAPL',
          assetClass: 'STOCK',
          quantity: 5,
          price: 90,
          id: 's2',
        ),
      ];

      final realisations = TradeStats.realisedTrades(events);
      expect(realisations, hasLength(2));
      expect(realisations[0], closeTo(100, 1e-9)); // 5 * (120 - 100)
      expect(realisations[1], closeTo(-50, 1e-9)); // 5 * (90 - 100)

      final stats = TradeStats.fromRealisations(realisations);
      expect(stats.wins, 1);
      expect(stats.losses, 1);
      expect(stats.winLossRatio, closeTo(1, 1e-9));
      expect(stats.winRate, closeTo(50, 1e-9));
      expect(stats.realisedTotal, closeTo(50, 1e-9));
      expect(stats.averageWin, closeTo(100, 1e-9));
      expect(stats.averageLoss, closeTo(-50, 1e-9));
    });

    test('reports an unbounded ratio when nothing has lost', () {
      final stats = TradeStats.fromRealisations(const [10, 20]);
      expect(stats.wins, 2);
      expect(stats.losses, 0);
      expect(stats.winLossRatio, isNull);
    });

    test('is empty for a portfolio that has never sold', () {
      expect(TradeStats.fromRealisations(const []), TradeStats.empty);
    });
  });

  group('Equity snapshots', () {
    test('records one row per UTC day and upserts the same day', () {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final repository = EquitySnapshotRepository(db);

      repository.record(
        at: DateTime.utc(2026, 1, 1, 9),
        netLiquidation: 100,
        cash: 100,
        marketValue: 0,
        realisedPnl: 0,
        unrealisedPnl: 0,
      );
      repository.record(
        at: DateTime.utc(2026, 1, 1, 17),
        netLiquidation: 110,
        cash: 110,
        marketValue: 0,
        realisedPnl: 0,
        unrealisedPnl: 0,
      );
      repository.record(
        at: DateTime.utc(2026, 1, 2, 9),
        netLiquidation: 120,
        cash: 120,
        marketValue: 0,
        realisedPnl: 0,
        unrealisedPnl: 0,
      );

      expect(repository.count(), 2);
      final all = repository.all();
      expect(all.first.netLiquidation, 110, reason: 'same-day upsert');
      expect(all.last.netLiquidation, 120);
    });

    test('builds a chronological curve from snapshots', () {
      final points = EquityCurve.fromSnapshots([
        EquitySnapshot(
          day: '2026-01-02',
          netLiquidation: 120,
          cash: 0,
          marketValue: 0,
          realisedPnl: 0,
          unrealisedPnl: 0,
          recordedAt: DateTime.utc(2026, 1, 2),
        ),
        EquitySnapshot(
          day: '2026-01-01',
          netLiquidation: 100,
          cash: 0,
          marketValue: 0,
          realisedPnl: 0,
          unrealisedPnl: 0,
          recordedAt: DateTime.utc(2026, 1, 1),
        ),
      ]);

      expect(points.map((p) => p.equity).toList(), [100, 120]);
      expect(points.first.time, DateTime.parse('2026-01-01T00:00:00.000Z'));
    });
  });
}

DateTime _t(int day) => DateTime.utc(2026, 1, day);
