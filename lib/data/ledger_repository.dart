import '../core/ids.dart';
import 'app_database.dart';
import 'models/ledger_event.dart';

/// Read/write access to the append-only event ledger.
///
/// There are deliberately no UPDATE or DELETE paths for events: the ledger is
/// immutable, and portfolio state is derived by replaying it.
class LedgerRepository {
  LedgerRepository(this._db);

  final AppDatabase _db;

  static const String _insertSql = '''
    INSERT INTO ledger_events (
      event_id, hlc_timestamp, device_id, event_type, symbol, asset_class,
      quantity, execution_price, accrued_interest, fee, currency, synced
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
  ''';

  /// Appends an event to the local ledger, queued for sync (`synced = 0`).
  void append(LedgerEvent event) {
    _db.raw.execute(_insertSql, event.toSqlParams());
  }

  /// Convenience builder that fills ids/timestamps/device automatically.
  LedgerEvent deposit({
    required double amount,
    String currency = 'USD',
    DateTime? at,
  }) {
    final now = at ?? DateTime.now();
    return LedgerEvent(
      eventId: Ids.uuidV7(now: now),
      hlcTimestamp: now.toUtc().toIso8601String(),
      deviceId: currentDeviceId(),
      eventType: EventType.cashDeposit,
      quantity: amount,
      currency: currency,
    );
  }

  /// Every event, oldest first (matches deterministic replay order).
  List<LedgerEvent> all() {
    final rows = _db.raw
        .select('SELECT * FROM ledger_events ORDER BY hlc_timestamp, event_id;');
    return rows.map(LedgerEvent.fromRow).toList(growable: false);
  }

  /// Events still awaiting push to the gist.
  int pendingCount() {
    final row = _db.raw
        .select('SELECT count(*) AS c FROM ledger_events WHERE synced = 0;')
        .first;
    return row['c'] as int;
  }

  /// Derived cash balance (never stored). Mirrors the replay rules in roadmap 5.2.
  double cashBalance() {
    final row = _db.raw.select('''
      SELECT COALESCE(SUM(
        CASE
          WHEN event_type IN ('CASH_DEPOSIT', 'BOND_COUPON') THEN quantity
          WHEN event_type = 'SELL'
            THEN quantity * (execution_price + accrued_interest) - fee
          WHEN event_type = 'BUY'
            THEN -(quantity * (execution_price + accrued_interest) + fee)
          ELSE 0
        END
      ), 0) AS cash
      FROM ledger_events;
    ''').first;
    return (row['cash'] as num).toDouble();
  }
}
