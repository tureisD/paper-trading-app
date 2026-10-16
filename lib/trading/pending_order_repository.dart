import '../data/app_database.dart';
import 'order.dart';

/// Working (unfilled) orders: limit/stop orders at rest and fund orders queued
/// for the next NAV.
class PendingOrderRepository {
  PendingOrderRepository(this._db);

  final AppDatabase _db;

  static const String _upsertSql = '''
    INSERT INTO pending_orders (
      order_id, account_id, symbol, asset_class, side, order_type, quantity,
      limit_price, stop_price, status, created_at, updated_at, filled_event_id, note
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(order_id) DO UPDATE SET
      status = excluded.status,
      updated_at = excluded.updated_at,
      filled_event_id = excluded.filled_event_id,
      note = excluded.note;
  ''';

  void upsert(Order order) =>
      _db.raw.execute(_upsertSql, order.toSqlParams());

  Order? get(String orderId) {
    final rows = _db.raw
        .select('SELECT * FROM pending_orders WHERE order_id = ?;', [orderId]);
    return rows.isEmpty ? null : Order.fromRow(rows.first);
  }

  List<Order> byStatus(OrderStatus status) {
    final rows = _db.raw.select(
      'SELECT * FROM pending_orders WHERE status = ? ORDER BY created_at;',
      [status.wire],
    );
    return rows.map(Order.fromRow).toList(growable: false);
  }

  /// All orders that are still live (resting or awaiting NAV).
  List<Order> working() {
    final rows = _db.raw.select(
      'SELECT * FROM pending_orders WHERE status IN (?, ?) ORDER BY created_at;',
      [OrderStatus.pending.wire, OrderStatus.queuedNav.wire],
    );
    return rows.map(Order.fromRow).toList(growable: false);
  }

  List<Order> bySymbol(String symbol) {
    final rows = _db.raw.select(
      'SELECT * FROM pending_orders WHERE symbol = ? ORDER BY created_at;',
      [symbol],
    );
    return rows.map(Order.fromRow).toList(growable: false);
  }

  int count() => _db.raw
      .select('SELECT count(*) AS c FROM pending_orders;')
      .first['c'] as int;
}
