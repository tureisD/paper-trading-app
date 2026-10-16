import 'package:flutter_test/flutter_test.dart';
import 'package:paper_trading_app/data/app_database.dart';
import 'package:paper_trading_app/data/ledger_repository.dart';
import 'package:paper_trading_app/market/asset_class.dart';
import 'package:paper_trading_app/market/instrument_repository.dart';
import 'package:paper_trading_app/market/models/instrument.dart';
import 'package:paper_trading_app/market/models/quote.dart';
import 'package:paper_trading_app/trading/account_repository.dart';
import 'package:paper_trading_app/trading/bond_math.dart';
import 'package:paper_trading_app/trading/fee_model.dart';
import 'package:paper_trading_app/trading/order.dart';
import 'package:paper_trading_app/trading/pending_order_repository.dart';
import 'package:paper_trading_app/trading/portfolio.dart';
import 'package:paper_trading_app/trading/portfolio_engine.dart';
import 'package:paper_trading_app/trading/position_repository.dart';
import 'package:paper_trading_app/trading/trading_engine.dart';

const _stock = Instrument(
  symbol: 'AAPL',
  name: 'Apple Inc.',
  assetClass: AssetClass.stock,
);
const _crypto = Instrument(
  symbol: 'BTC-USD',
  name: 'Bitcoin',
  assetClass: AssetClass.crypto,
  provider: 'binance',
  providerSymbol: 'BTCUSDT',
);
const _fund = Instrument(
  symbol: 'VFIAX',
  name: 'Vanguard 500 Index Fund',
  assetClass: AssetClass.fund,
  provider: 'yahoo',
);
const _bond = Instrument(
  symbol: 'TESTBOND',
  name: 'Test 5% 2030',
  assetClass: AssetClass.bond,
);

final _t0 = DateTime.utc(2026, 1, 1, 9, 0, 0);
DateTime _at(int minutes) => _t0.add(Duration(minutes: minutes));

Quote _quote(String symbol, double price) => Quote.derive(
      symbol: symbol,
      price: price,
      source: 'test',
      asOf: _t0,
    );

class _Harness {
  _Harness() {
    db = AppDatabase.inMemory();
    ledger = LedgerRepository(db);
    instruments = InstrumentRepository(db);
    engine = TradingEngine(
      database: db,
      ledger: ledger,
      orders: PendingOrderRepository(db),
      positions: PositionRepository(db),
      instruments: instruments,
    );
    AccountRepository(db).ensureDefault();
  }

  late final AppDatabase db;
  late final LedgerRepository ledger;
  late final InstrumentRepository instruments;
  late final TradingEngine engine;

  void deposit(double amount, {int minutes = 0}) =>
      ledger.append(ledger.deposit(amount: amount, at: _at(minutes)));

  void dispose() => db.close();
}

void main() {
  group('PortfolioEngine (Weighted Average Cost)', () {
    test('blends cost basis on buys and locks realised P&L on sells', () {
      var position = PortfolioEngine.applyTrade(
        Position.empty('AAPL', AssetClass.stock),
        side: OrderSide.buy,
        quantity: 10,
        price: 100,
      );
      expect(position.quantity, 10);
      expect(position.averageCost, 100);

      position = PortfolioEngine.applyTrade(
        position,
        side: OrderSide.buy,
        quantity: 10,
        price: 200,
      );
      expect(position.quantity, 20);
      expect(position.averageCost, closeTo(150, 1e-9));

      position = PortfolioEngine.applyTrade(
        position,
        side: OrderSide.sell,
        quantity: 5,
        price: 300,
      );
      expect(position.quantity, 15);
      expect(position.averageCost, closeTo(150, 1e-9)); // unchanged on sell
      expect(position.realisedPnl, closeTo(750, 1e-9));
    });

    test('includes fees in cost basis', () {
      final position = PortfolioEngine.applyTrade(
        Position.empty('BTC-USD', AssetClass.crypto),
        side: OrderSide.buy,
        quantity: 1,
        price: 50000,
        fee: 50,
      );
      expect(position.averageCost, closeTo(50050, 1e-9));
    });
  });

  group('FeeModel', () {
    test('applies equity slippage in the adverse direction only', () {
      expect(FeeModel.withSlippage(100, AssetClass.stock, OrderSide.buy),
          closeTo(100.02, 1e-9));
      expect(FeeModel.withSlippage(100, AssetClass.stock, OrderSide.sell),
          closeTo(99.98, 1e-9));
      // Crypto and bonds have no simulated spread.
      expect(FeeModel.withSlippage(100, AssetClass.crypto, OrderSide.buy), 100);
      expect(FeeModel.withSlippage(100, AssetClass.bond, OrderSide.buy), 100);
    });

    test('charges 0.10% on crypto notional only', () {
      expect(FeeModel.commission(50000, AssetClass.crypto), closeTo(50, 1e-9));
      expect(FeeModel.commission(50000, AssetClass.stock), 0);
    });

    test('enforces per-class quantity precision', () {
      expect(FeeModel.isValidQuantity(1e-8, AssetClass.crypto), isTrue);
      expect(FeeModel.isValidQuantity(1e-9, AssetClass.crypto), isFalse);
      expect(FeeModel.isValidQuantity(0.5, AssetClass.stock), isTrue);
      expect(FeeModel.isValidQuantity(0, AssetClass.stock), isFalse);
    });
  });

  group('TradingEngine — market execution', () {
    late _Harness h;
    setUp(() => h = _Harness());
    tearDown(() => h.dispose());

    test('fills an equity buy with slippage and updates cash + cost basis', () {
      h.deposit(100000);

      final result = h.engine.submit(
        instrument: _stock,
        side: OrderSide.buy,
        type: OrderType.market,
        quantity: 10,
        quote: _quote('AAPL', 100),
        now: _at(1),
      );

      expect(result.isFilled, isTrue);
      expect(result.executionPrice, closeTo(100.02, 1e-9));
      expect(result.fee, 0);

      final state = h.engine.snapshot();
      expect(state.cash, closeTo(98999.8, 1e-6));
      expect(state.positions['AAPL']!.quantity, 10);
      expect(state.positions['AAPL']!.averageCost, closeTo(100.02, 1e-9));
    });

    test('nets multiple buys then realises P&L on a sell', () {
      h.deposit(100000);

      for (final (qty, price, minute) in [(10, 100.0, 1), (10, 200.0, 2)]) {
        h.engine.submit(
          instrument: _stock,
          side: OrderSide.buy,
          type: OrderType.market,
          quantity: qty.toDouble(),
          quote: _quote('AAPL', price),
          now: _at(minute),
        );
      }
      final sell = h.engine.submit(
        instrument: _stock,
        side: OrderSide.sell,
        type: OrderType.market,
        quantity: 5,
        quote: _quote('AAPL', 300),
        now: _at(3),
      );

      expect(sell.executionPrice, closeTo(299.94, 1e-9));
      final state = h.engine.snapshot();
      expect(state.cash, closeTo(98499.1, 1e-6));
      expect(state.positions['AAPL']!.quantity, 15);
      expect(state.positions['AAPL']!.averageCost, closeTo(150.03, 1e-9));
      expect(state.positions['AAPL']!.realisedPnl, closeTo(749.55, 1e-9));
    });

    test('charges the crypto taker fee', () {
      h.deposit(100000);
      final result = h.engine.submit(
        instrument: _crypto,
        side: OrderSide.buy,
        type: OrderType.market,
        quantity: 1,
        quote: _quote('BTC-USD', 50000),
        now: _at(1),
      );

      expect(result.fee, closeTo(50, 1e-9));
      expect(result.cashDelta, closeTo(-50050, 1e-9));
      expect(
        h.engine.snapshot().positions['BTC-USD']!.averageCost,
        closeTo(50050, 1e-9),
      );
    });

    test('supports fractional share quantities', () {
      h.deposit(1000);
      final result = h.engine.submit(
        instrument: _stock,
        side: OrderSide.buy,
        type: OrderType.market,
        quantity: 0.5,
        quote: _quote('AAPL', 100),
        now: _at(1),
      );
      expect(result.isFilled, isTrue);
      expect(h.engine.snapshot().positions['AAPL']!.quantity, closeTo(0.5, 1e-12));
    });

    test('rejects sub-step crypto quantities', () {
      h.deposit(100000);
      final result = h.engine.submit(
        instrument: _crypto,
        side: OrderSide.buy,
        type: OrderType.market,
        quantity: 1e-9,
        quote: _quote('BTC-USD', 50000),
        now: _at(1),
      );
      expect(result.isRejected, isTrue);
      expect(result.rejectionReason, contains('multiple'));
    });

    test('rejects a market order without a quote', () {
      h.deposit(100000);
      final result = h.engine.submit(
        instrument: _stock,
        side: OrderSide.buy,
        type: OrderType.market,
        quantity: 1,
        now: _at(1),
      );
      expect(result.isRejected, isTrue);
      expect(result.rejectionReason, contains('quote'));
    });

    test('rejects a buy that exceeds buying power', () {
      h.deposit(1000);
      final result = h.engine.submit(
        instrument: _stock,
        side: OrderSide.buy,
        type: OrderType.market,
        quantity: 100,
        quote: _quote('AAPL', 100),
        now: _at(1),
      );
      expect(result.isRejected, isTrue);
      expect(result.rejectionReason, contains('buying power'));
    });

    test('rejects selling more than is held', () {
      h.deposit(100000);
      h.engine.submit(
        instrument: _stock,
        side: OrderSide.buy,
        type: OrderType.market,
        quantity: 10,
        quote: _quote('AAPL', 100),
        now: _at(1),
      );
      final result = h.engine.submit(
        instrument: _stock,
        side: OrderSide.sell,
        type: OrderType.market,
        quantity: 20,
        quote: _quote('AAPL', 110),
        now: _at(2),
      );
      expect(result.isRejected, isTrue);
      expect(result.rejectionReason, contains('Insufficient position'));
    });
  });

  group('TradingEngine — resting orders', () {
    late _Harness h;
    setUp(() => h = _Harness());
    tearDown(() => h.dispose());

    test('rests a non-marketable limit order, then fills it on a cross', () {
      h.deposit(100000);

      final placed = h.engine.submit(
        instrument: _stock,
        side: OrderSide.buy,
        type: OrderType.limit,
        quantity: 1,
        limitPrice: 100,
        quote: _quote('AAPL', 105),
        now: _at(1),
      );
      expect(placed.status, OrderStatus.pending);
      expect(h.engine.workingOrders(), hasLength(1));
      expect(h.engine.snapshot().cash, closeTo(100000, 1e-9));

      final fills = h.engine.onQuote(_quote('AAPL', 99), now: _at(2));
      expect(fills, hasLength(1));
      expect(fills.single.executionPrice, closeTo(99.0198, 1e-6));
      expect(h.engine.workingOrders(), isEmpty);
    });

    test('fills an immediately marketable limit order', () {
      h.deposit(100000);
      final result = h.engine.submit(
        instrument: _stock,
        side: OrderSide.buy,
        type: OrderType.limit,
        quantity: 1,
        limitPrice: 110,
        quote: _quote('AAPL', 100),
        now: _at(1),
      );
      expect(result.isFilled, isTrue);
    });

    test('arms a stop order and triggers it on the way down', () {
      h.deposit(100000);
      h.engine.submit(
        instrument: _stock,
        side: OrderSide.buy,
        type: OrderType.market,
        quantity: 10,
        quote: _quote('AAPL', 100),
        now: _at(1),
      );

      final placed = h.engine.submit(
        instrument: _stock,
        side: OrderSide.sell,
        type: OrderType.stop,
        quantity: 5,
        stopPrice: 90,
        quote: _quote('AAPL', 95),
        now: _at(2),
      );
      expect(placed.status, OrderStatus.pending);

      final fills = h.engine.onQuote(_quote('AAPL', 89), now: _at(3));
      expect(fills, hasLength(1));
      expect(fills.single.executionPrice, closeTo(88.9822, 1e-6));

      final state = h.engine.snapshot();
      expect(state.positions['AAPL']!.quantity, 5);
    });

    test('cancels a working order', () {
      h.deposit(100000);
      final placed = h.engine.submit(
        instrument: _stock,
        side: OrderSide.buy,
        type: OrderType.limit,
        quantity: 1,
        limitPrice: 50,
        quote: _quote('AAPL', 100),
        now: _at(1),
      );
      final cancelled = h.engine.cancel(placed.order.orderId, now: _at(2));
      expect(cancelled.status, OrderStatus.cancelled);
      expect(h.engine.workingOrders(), isEmpty);
    });
  });

  group('TradingEngine — mutual funds', () {
    late _Harness h;
    setUp(() => h = _Harness());
    tearDown(() => h.dispose());

    test('queues intraday fund orders for the next NAV, then settles', () {
      h.deposit(100000);

      final placed = h.engine.submit(
        instrument: _fund,
        side: OrderSide.buy,
        type: OrderType.market,
        quantity: 1,
        quote: _quote('VFIAX', 700),
        now: _at(1),
      );
      expect(placed.status, OrderStatus.queuedNav);
      expect(placed.isWorking, isTrue);
      expect(h.engine.snapshot().cash, closeTo(100000, 1e-9));

      final settled = h.engine.settleFundNav('VFIAX', 701.25, now: _at(2));
      expect(settled, hasLength(1));
      expect(settled.single.status, OrderStatus.filled);

      final state = h.engine.snapshot();
      expect(state.cash, closeTo(100000 - 701.25, 1e-6));
      expect(state.positions['VFIAX']!.quantity, 1);
      expect(state.positions['VFIAX']!.averageCost, closeTo(701.25, 1e-9));
    });
  });

  group('TradingEngine — bonds', () {
    late _Harness h;
    setUp(() {
      h = _Harness();
      h.instruments.upsert(
        _bond,
        bondDetails: const BondDetails(
          symbol: 'TESTBOND',
          couponRate: 0.05,
          maturityDate: '2030-01-15',
          parValue: 100,
          couponFrequency: 2,
          dayCount: 'Actual/Actual',
        ),
      );
    });
    tearDown(() => h.dispose());

    test('settles on the dirty price (clean + accrued interest)', () {
      h.deposit(100000);

      // 2029-10-15 sits exactly halfway through the Jul->Jan coupon period.
      final result = h.engine.submit(
        instrument: _bond,
        side: OrderSide.buy,
        type: OrderType.market,
        quantity: 100,
        quote: _quote('TESTBOND', 100),
        now: DateTime.utc(2029, 10, 15),
      );

      expect(result.isFilled, isTrue);
      expect(result.accruedInterest, closeTo(1.25, 1e-9));
      expect(result.executionPrice, closeTo(100, 1e-9));
      expect(result.cashDelta, closeTo(-10125, 1e-6));

      final state = h.engine.snapshot();
      expect(state.cash, closeTo(89875, 1e-6));
      expect(state.positions['TESTBOND']!.averageCost, closeTo(101.25, 1e-9));
    });

    test('credits due coupons exactly once', () {
      h.deposit(100000);
      h.engine.submit(
        instrument: _bond,
        side: OrderSide.buy,
        type: OrderType.market,
        quantity: 100,
        quote: _quote('TESTBOND', 100),
        now: DateTime.utc(2029, 10, 15),
      );

      final first = h.engine.creditDueCoupons(
        asOf: DateTime.utc(2030, 1, 15),
        now: DateTime.utc(2030, 1, 15),
      );
      expect(first, 1);
      // 100 units * (100 par * 5% / 2) = 250 cash.
      expect(h.engine.snapshot().cash, closeTo(89875 + 250, 1e-6));

      final second = h.engine.creditDueCoupons(
        asOf: DateTime.utc(2030, 1, 15),
        now: DateTime.utc(2030, 1, 15),
      );
      expect(second, 0);
    });
  });

  group('BondMath', () {
    test('computes the coupon period and accrued interest', () {
      final period = BondMath.couponPeriod(
        asOf: DateTime.utc(2029, 10, 15),
        maturity: DateTime.utc(2030, 1, 15),
        paymentsPerYear: 2,
      );
      expect(period.previous, DateTime.utc(2029, 7, 15));
      expect(period.next, DateTime.utc(2030, 1, 15));
      expect(BondMath.daysBetween(period.previous, period.next), 184);

      expect(
        BondMath.accruedInterest(
          parValue: 100,
          annualCouponRate: 0.05,
          paymentsPerYear: 2,
          daysElapsed: 92,
          daysInPeriod: 184,
        ),
        closeTo(1.25, 1e-9),
      );
    });

    test('dirty and clean price are inverses', () {
      expect(BondMath.dirtyPrice(98.5, 1.25), closeTo(99.75, 1e-9));
      expect(BondMath.cleanPrice(99.75, 1.25), closeTo(98.5, 1e-9));
    });
  });
}
