import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paper_trading_app/core/ids.dart';
import 'package:paper_trading_app/data/app_database.dart';
import 'package:paper_trading_app/data/app_paths.dart';
import 'package:paper_trading_app/data/ledger_repository.dart';
import 'package:paper_trading_app/data/schema.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AppPaths', () {
    test('resolves a per-user database path', () {
      final path = AppPaths.databasePath();
      expect(p.basename(path), 'paper_trading.db');
      expect(Directory(p.dirname(path)).existsSync(), isTrue);
    });
  });
  group('AppDatabase', () {
    late Directory dir;
    late AppDatabase db;
    late LedgerRepository ledger;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('pt_db_test_');
      db = AppDatabase.open('${dir.path}${Platform.pathSeparator}test.db');
      ledger = LedgerRepository(db);
    });

    tearDown(() {
      db.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('enables WAL for file-backed databases', () {
      expect(db.journalMode, 'wal');
    });

    test('records the current schema version', () {
      expect(db.schemaVersion, Schema.version);
    });

    test('creates the ledger and FTS5 instrument index', () {
      expect(db.ledgerEventCount(), 0);
      expect(db.instrumentCount(), 0);
    });

    test('appends a deposit and derives cash from the ledger', () {
      ledger.append(ledger.deposit(amount: 250000));

      expect(db.ledgerEventCount(), 1);
      expect(ledger.cashBalance(), 250000.0);
      expect(ledger.pendingCount(), 1);
    });

    test('cash balance nets buys and sells', () {
      final raw = db.raw;
      raw.execute(
        'INSERT INTO ledger_events (event_id, hlc_timestamp, device_id, '
        'event_type, symbol, quantity, execution_price, fee) '
        "VALUES ('e1', '2026-01-01T00:00:00Z', 'windows_desktop', 'BUY', "
        "'AAPL', 10, 100, 5);",
      );
      raw.execute(
        'INSERT INTO ledger_events (event_id, hlc_timestamp, device_id, '
        'event_type, symbol, quantity, execution_price, fee) '
        "VALUES ('e2', '2026-01-02T00:00:00Z', 'windows_desktop', 'SELL', "
        "'AAPL', 4, 120, 3);",
      );

      // 10*100 + 5 spent, 4*120 - 3 received => -1005 + 477 = -528
      expect(ledger.cashBalance(), closeTo(-528.0, 1e-9));
    });

    test('persists sync bookkeeping values', () {
      db.setSyncState('gist_id', 'abc123');
      db.setSyncState('gist_etag', 'W/"deadbeef"');
      expect(db.getSyncState('gist_id'), 'abc123');
      expect(db.getSyncState('gist_etag'), 'W/"deadbeef"');
      expect(db.getSyncState('missing'), isNull);
    });
  });

  group('Ids.uuidV7', () {
    test('matches the UUID shape', () {
      final id = Ids.uuidV7();
      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('is lexicographically sortable by time', () {
      final earlier = Ids.uuidV7(now: DateTime.utc(2026, 1, 1));
      final later = Ids.uuidV7(now: DateTime.utc(2026, 1, 2));
      expect(earlier.compareTo(later), lessThan(0));
    });
  });
}
