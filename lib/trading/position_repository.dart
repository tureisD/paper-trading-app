import '../data/app_database.dart';
import '../market/asset_class.dart';
import 'portfolio.dart';

/// Fast-read materialisation of [PortfolioEngine] output.
///
/// This is a pure cache: it can be dropped and rebuilt from the ledger at any
/// time, so it is never synced between devices.
class PositionRepository {
  PositionRepository(this._db);

  final AppDatabase _db;

  /// Replaces the cached positions for an account in a single transaction.
  void replaceAll(String accountId, Iterable<Position> positions) {
    final now = DateTime.now().toUtc().toIso8601String();
    _db.raw.execute('BEGIN;');
    try {
      _db.raw.execute(
        'DELETE FROM positions_cache WHERE account_id = ?;',
        [accountId],
      );
      for (final position in positions) {
        _db.raw.execute(
          'INSERT INTO positions_cache (account_id, symbol, asset_class, '
          'quantity, average_cost, realised_pnl, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?);',
          [
            accountId,
            position.symbol,
            position.assetClass.wire,
            position.quantity,
            position.averageCost,
            position.realisedPnl,
            now,
          ],
        );
      }
      _db.raw.execute('COMMIT;');
    } catch (_) {
      _db.raw.execute('ROLLBACK;');
      rethrow;
    }
  }

  List<Position> all(String accountId, {bool openOnly = true}) {
    final rows = _db.raw.select(
      'SELECT * FROM positions_cache WHERE account_id = ? '
      '${openOnly ? 'AND abs(quantity) > 1e-12 ' : ''}'
      'ORDER BY symbol;',
      [accountId],
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Position? get(String accountId, String symbol) {
    final rows = _db.raw.select(
      'SELECT * FROM positions_cache WHERE account_id = ? AND symbol = ?;',
      [accountId, symbol],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  int count(String accountId) => _db.raw
      .select(
        'SELECT count(*) AS c FROM positions_cache WHERE account_id = ? '
        'AND abs(quantity) > 1e-12;',
        [accountId],
      )
      .first['c'] as int;

  static Position _fromRow(dynamic row) => Position(
        symbol: row['symbol'] as String,
        assetClass: AssetClass.fromWire(row['asset_class'] as String),
        quantity: (row['quantity'] as num).toDouble(),
        averageCost: (row['average_cost'] as num).toDouble(),
        realisedPnl: (row['realised_pnl'] as num).toDouble(),
      );
}
