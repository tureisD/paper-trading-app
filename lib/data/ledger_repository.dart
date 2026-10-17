import '../core/ids.dart';
import '../sync/hlc.dart';
import 'app_database.dart';
import 'models/ledger_event.dart';

/// Read/write access to the append-only event ledger.
///
/// There are deliberately no UPDATE or DELETE paths for event content: the
/// ledger is immutable and portfolio state is derived by replaying it.
///
/// Events belong to a **portfolio** (`account_id`). Sync always moves every
/// portfolio at once; the UI scopes reads to the active one.
class LedgerRepository {
  LedgerRepository(this._db, {String? deviceId})
      : _deviceId = deviceId ?? currentDeviceId(),
        _clock = _initClock(_db);

  final AppDatabase _db;
  final String _deviceId;
  final HlcClock _clock;

  /// Identity stamped on events this repository writes.
  String get deviceId => _deviceId;

  HlcClock get clock => _clock;

  static const String defaultAccountId = 'default';

  static const String _insertSql = '''
    INSERT INTO ledger_events (
      event_id, hlc_timestamp, device_id, event_type, symbol, asset_class,
      quantity, execution_price, accrued_interest, fee, currency, synced, meta,
      account_id
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
  ''';

  static HlcClock _initClock(AppDatabase db) {
    final rows =
        db.raw.select('SELECT max(hlc_timestamp) AS m FROM ledger_events;');
    final value = rows.first['m'] as String?;
    return HlcClock(value == null ? null : Hlc.parse(value));
  }

  /// Builds a new event stamped with a UUIDv7 id and a monotonic HLC.
  LedgerEvent newEvent({
    required String eventType,
    String accountId = defaultAccountId,
    String? symbol,
    String? assetClass,
    double quantity = 0.0,
    double executionPrice = 0.0,
    double accruedInterest = 0.0,
    double fee = 0.0,
    String currency = 'USD',
    String? meta,
    DateTime? at,
  }) {
    final now = at ?? DateTime.now();
    return LedgerEvent(
      eventId: Ids.uuidV7(now: now),
      hlcTimestamp: _clock.next(now: now).encode(),
      deviceId: _deviceId,
      eventType: eventType,
      symbol: symbol,
      assetClass: assetClass,
      quantity: quantity,
      executionPrice: executionPrice,
      accruedInterest: accruedInterest,
      fee: fee,
      currency: currency,
      meta: meta,
      accountId: accountId,
    );
  }

  /// Appends an event to the local ledger, queued for sync (`synced = 0`).
  void append(LedgerEvent event) {
    _db.raw.execute(_insertSql, event.toSqlParams());
  }

  /// Inserts a remote event if we have not already seen its id.
  /// Returns true when the row was new.
  bool insertIfAbsent(LedgerEvent event) {
    final existing = _db.raw.select(
      'SELECT 1 FROM ledger_events WHERE event_id = ?;',
      [event.eventId],
    );
    if (existing.isNotEmpty) return false;
    _db.raw.execute(_insertSql, event.toSqlParams());
    return true;
  }

  /// Convenience builder for a cash deposit.
  LedgerEvent deposit({
    required double amount,
    String accountId = defaultAccountId,
    String currency = 'USD',
    DateTime? at,
  }) {
    return newEvent(
      eventType: EventType.cashDeposit,
      accountId: accountId,
      quantity: amount,
      currency: currency,
      at: at,
    );
  }

  /// Convenience builder for a cash withdrawal.
  LedgerEvent withdrawal({
    required double amount,
    String accountId = defaultAccountId,
    String currency = 'USD',
    DateTime? at,
  }) {
    return newEvent(
      eventType: EventType.cashWithdrawal,
      accountId: accountId,
      quantity: amount,
      currency: currency,
      at: at,
    );
  }

  /// Every event, oldest first (matches deterministic replay order).
  /// Pass [accountId] to scope to a single portfolio.
  List<LedgerEvent> all({String? accountId}) {
    final rows = accountId == null
        ? _db.raw.select(
            'SELECT * FROM ledger_events ORDER BY hlc_timestamp, event_id;',
          )
        : _db.raw.select(
            'SELECT * FROM ledger_events WHERE account_id = ? '
            'ORDER BY hlc_timestamp, event_id;',
            [accountId],
          );
    return rows.map(LedgerEvent.fromRow).toList(growable: false);
  }

  /// Events created on this device that still need to reach the vault
  /// (across every portfolio).
  List<LedgerEvent> pendingEvents() {
    final rows = _db.raw.select(
      'SELECT * FROM ledger_events WHERE synced = 0 ORDER BY hlc_timestamp;',
    );
    return rows.map(LedgerEvent.fromRow).toList(growable: false);
  }

  /// All events this device wrote in a given `yyyy-MM` month.
  List<LedgerEvent> deviceEventsInMonth(String deviceId, String monthKey) {
    final rows = _db.raw.select(
      'SELECT * FROM ledger_events WHERE device_id = ? AND hlc_timestamp LIKE ? '
      'ORDER BY hlc_timestamp;',
      [deviceId, '$monthKey%'],
    );
    return rows.map(LedgerEvent.fromRow).toList(growable: false);
  }

  /// Marks events as confirmed in the vault.
  void markSynced(Iterable<String> eventIds) {
    final ids = eventIds.toList(growable: false);
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(', ');
    _db.raw.execute(
      'UPDATE ledger_events SET synced = 1 WHERE event_id IN ($placeholders);',
      ids,
    );
  }

  /// Advances the HLC past a remote event so local writes sort after it.
  void observeHlc(String encoded) => _clock.observe(Hlc.parse(encoded));

  /// Events still awaiting push to the gist (every portfolio).
  int pendingCount() {
    final row = _db.raw
        .select('SELECT count(*) AS c FROM ledger_events WHERE synced = 0;')
        .first;
    return row['c'] as int;
  }

  /// Derived cash balance (never stored). Mirrors the replay rules in roadmap 5.2.
  double cashBalance({String? accountId}) {
    final row = _db.raw.select('''
      SELECT COALESCE(SUM(
        CASE
          WHEN event_type IN ('CASH_DEPOSIT', 'BOND_COUPON') THEN quantity
          WHEN event_type = 'CASH_WITHDRAWAL' THEN -quantity
          WHEN event_type = 'SELL'
            THEN quantity * (execution_price + accrued_interest) - fee
          WHEN event_type = 'BUY'
            THEN -(quantity * (execution_price + accrued_interest) + fee)
          ELSE 0
        END
      ), 0) AS cash
      FROM ledger_events
      ${accountId == null ? '' : 'WHERE account_id = ?'};
    ''', accountId == null ? const <Object?>[] : <Object?>[accountId]).first;
    return (row['cash'] as num).toDouble();
  }

  /// Net capital contributed: deposits minus withdrawals.
  double netDeposits({String? accountId}) {
    final row = _db.raw.select('''
      SELECT COALESCE(SUM(
        CASE
          WHEN event_type = 'CASH_DEPOSIT' THEN quantity
          WHEN event_type = 'CASH_WITHDRAWAL' THEN -quantity
          ELSE 0
        END
      ), 0) AS d
      FROM ledger_events
      ${accountId == null ? '' : 'WHERE account_id = ?'};
    ''', accountId == null ? const <Object?>[] : <Object?>[accountId]).first;
    return (row['d'] as num).toDouble();
  }

  /// Removes every local trace of a portfolio. Other synced devices will
  /// re-upload their copy, so this is a local reset, not a tombstone.
  void purgeAccount(String accountId) {
    if (accountId == defaultAccountId) return;
    _db.raw.execute('BEGIN;');
    try {
      _db.raw.execute('DELETE FROM ledger_events WHERE account_id = ?;', [
        accountId,
      ]);
      _db.raw.execute('DELETE FROM positions_cache WHERE account_id = ?;', [
        accountId,
      ]);
      _db.raw.execute('DELETE FROM equity_snapshots WHERE account_id = ?;', [
        accountId,
      ]);
      _db.raw.execute('DELETE FROM pending_orders WHERE account_id = ?;', [
        accountId,
      ]);
      _db.raw.execute('COMMIT;');
    } catch (_) {
      _db.raw.execute('ROLLBACK;');
      rethrow;
    }
  }
}
