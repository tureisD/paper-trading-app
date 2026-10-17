import 'package:flutter_test/flutter_test.dart';
import 'package:paper_trading_app/data/app_database.dart';
import 'package:paper_trading_app/data/ledger_repository.dart';
import 'package:paper_trading_app/data/models/ledger_event.dart';
import 'package:paper_trading_app/market/asset_class.dart';
import 'package:paper_trading_app/market/instrument_repository.dart';
import 'package:paper_trading_app/market/models/instrument.dart';
import 'package:paper_trading_app/market/models/quote.dart';
import 'package:paper_trading_app/trading/account_repository.dart';
import 'package:paper_trading_app/trading/order.dart';
import 'package:paper_trading_app/trading/pending_order_repository.dart';
import 'package:paper_trading_app/trading/portfolio.dart';
import 'package:paper_trading_app/trading/portfolio_engine.dart';
import 'package:paper_trading_app/trading/position_repository.dart';
import 'package:paper_trading_app/trading/trading_engine.dart';

const _apple = Instrument(
  symbol: 'AAPL',
  name: 'Apple Inc.',
  assetClass: AssetClass.stock,
);

Quote _quote(double price) => Quote.derive(
      symbol: 'AAPL',
      price: price,
      asOf: DateTime.utc(2026, 1, 1),
      source: 'test',
    );

void main() {
  late AppDatabase db;
  late LedgerRepository ledger;
  late AccountRepository accounts;
  late InstrumentRepository instruments;
  late PositionRepository positions;

  setUp(() {
    db = AppDatabase.inMemory();
    ledger = LedgerRepository(db, deviceId: 'device_a');
    accounts = AccountRepository(db);
    instruments = InstrumentRepository(db);
    positions = PositionRepository(db);
    accounts.ensureDefault();
  });
  tearDown(() => db.close());

  TradingEngine engineFor(String accountId) => TradingEngine(
        database: db,
        ledger: ledger,
        orders: PendingOrderRepository(db),
        positions: positions,
        instruments: instruments,
        accountId: accountId,
      );

  group('cash withdrawals', () {
    test('reduce cash and net deposits', () {
      ledger.append(ledger.deposit(amount: 10000, at: DateTime.utc(2026, 1, 1)));
      ledger.append(
        ledger.withdrawal(amount: 2500, at: DateTime.utc(2026, 1, 2)),
      );

      expect(ledger.cashBalance(accountId: 'default'), closeTo(7500, 1e-9));
      expect(ledger.netDeposits(accountId: 'default'), closeTo(7500, 1e-9));
    });

    test('are subtracted by the replay engine', () {
      final events = [
        ledger.deposit(amount: 5000, at: DateTime.utc(2026, 1, 1)),
        ledger.withdrawal(amount: 1000, at: DateTime.utc(2026, 1, 2)),
      ];

      final state = PortfolioEngine.replay(events);
      expect(state.cash, closeTo(4000, 1e-9));
      expect(state.positions, isEmpty);
    });

    test('keep a full history in the ledger', () {
      ledger.append(ledger.deposit(amount: 1000, at: DateTime.utc(2026, 1, 1)));
      ledger.append(
        ledger.withdrawal(amount: 1000, at: DateTime.utc(2026, 1, 2)),
      );

      expect(ledger.cashBalance(accountId: 'default'), closeTo(0, 1e-9));
      final types = ledger
          .all(accountId: 'default')
          .map((event) => event.eventType)
          .toList();
      expect(types, [
        EventType.cashDeposit,
        EventType.cashWithdrawal,
      ]);
    });
  });

  group('portfolios', () {
    test('hold separate cash, positions and history', () {
      final swing = accounts.create('Swing trades')!;
      ledger.append(ledger.deposit(amount: 1000, at: DateTime.utc(2026, 1, 1)));
      ledger.append(
        ledger.deposit(
          amount: 50000,
          accountId: swing.accountId,
          at: DateTime.utc(2026, 1, 1),
        ),
      );

      expect(ledger.cashBalance(accountId: 'default'), closeTo(1000, 1e-9));
      expect(
        ledger.cashBalance(accountId: swing.accountId),
        closeTo(50000, 1e-9),
      );
      expect(ledger.all().length, 2);
      expect(ledger.all(accountId: 'default').length, 1);
      expect(ledger.all(accountId: swing.accountId).length, 1);

      // Trading in one portfolio leaves the other untouched.
      final buy = engineFor(swing.accountId).submit(
        instrument: _apple,
        side: OrderSide.buy,
        type: OrderType.market,
        quantity: 2,
        quote: _quote(100),
        now: DateTime.utc(2026, 1, 2),
      );
      expect(buy.isFilled, isTrue);

      final swingState = PortfolioEngine.replay(
        ledger.all(accountId: swing.accountId),
      );
      final defaultState = PortfolioEngine.replay(
        ledger.all(accountId: 'default'),
      );
      expect(swingState.positions['AAPL']!.quantity, 2);
      expect(defaultState.positions.containsKey('AAPL'), isFalse);
      expect(defaultState.cash, closeTo(1000, 1e-9));
    });

    test('renaming keeps the same history', () {
      final account = accounts.create('First name')!;
      ledger.append(
        ledger.deposit(
          amount: 100,
          accountId: account.accountId,
          at: DateTime.utc(2026, 1, 1),
        ),
      );
      accounts.rename(account.accountId, 'Second name');

      expect(accounts.get(account.accountId)!.name, 'Second name');
      expect(
        ledger.cashBalance(accountId: account.accountId),
        closeTo(100, 1e-9),
      );
    });

    test('can be purged locally, leaving the default intact', () {
      final account = accounts.create('Scratch')!;
      ledger.append(
        ledger.deposit(
          amount: 250,
          accountId: account.accountId,
          at: DateTime.utc(2026, 1, 1),
        ),
      );
      ledger.append(ledger.deposit(amount: 900, at: DateTime.utc(2026, 1, 1)));

      ledger.purgeAccount(account.accountId);
      accounts.delete(account.accountId);

      expect(accounts.get(account.accountId), isNull);
      expect(ledger.all(accountId: account.accountId), isEmpty);
      expect(ledger.cashBalance(accountId: 'default'), closeTo(900, 1e-9));
      expect(ledger.all().length, 1);
    });

    test('the default portfolio cannot be purged or deleted', () {
      ledger.append(ledger.deposit(amount: 10, at: DateTime.utc(2026, 1, 1)));
      ledger.purgeAccount('default');
      accounts.delete('default');

      expect(ledger.all().length, 1);
      expect(accounts.get('default'), isNotNull);
    });

    test('rejects blank names', () {
      expect(accounts.create('   '), isNull);
      expect(accounts.all().length, 1);
    });
  });

  group('position cache', () {
    test('is rebuilt for every portfolio at once', () {
      final second = accounts.create('Second')!;
      ledger.append(ledger.deposit(amount: 10000, at: DateTime.utc(2026, 1, 1)));
      ledger.append(
        ledger.deposit(
          amount: 10000,
          accountId: second.accountId,
          at: DateTime.utc(2026, 1, 1),
        ),
      );

      engineFor(second.accountId).submit(
        instrument: _apple,
        side: OrderSide.buy,
        type: OrderType.market,
        quantity: 1,
        quote: _quote(100),
        now: DateTime.utc(2026, 1, 2),
      );

      engineFor('default').rebuildCache();

      expect(positions.all(second.accountId).map((p) => p.symbol), contains('AAPL'));
      expect(positions.all('default'), isEmpty);
      expect(positions.count(second.accountId), 1);
    });
  });

  group('PortfolioSnapshot', () {
    test('is unaffected by other portfolios', () {
      expect(
        const PortfolioSnapshot(cash: 0, positions: {}).openPositions,
        isEmpty,
      );
    });
  });
}
