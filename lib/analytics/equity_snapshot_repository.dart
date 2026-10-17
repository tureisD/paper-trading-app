import 'package:sqlite3/sqlite3.dart';

import '../data/app_database.dart';

/// One end-of-day portfolio valuation.
class EquitySnapshot {
  const EquitySnapshot({
    required this.day,
    required this.netLiquidation,
    required this.cash,
    required this.marketValue,
    required this.realisedPnl,
    required this.unrealisedPnl,
    required this.recordedAt,
  });

  final String day;
  final double netLiquidation;
  final double cash;
  final double marketValue;
  final double realisedPnl;
  final double unrealisedPnl;
  final DateTime recordedAt;

  factory EquitySnapshot.fromRow(Row row) => EquitySnapshot(
        day: row['day'] as String,
        netLiquidation: (row['net_liquidation'] as num).toDouble(),
        cash: (row['cash'] as num).toDouble(),
        marketValue: (row['market_value'] as num).toDouble(),
        realisedPnl: (row['realised_pnl'] as num).toDouble(),
        unrealisedPnl: (row['unrealised_pnl'] as num).toDouble(),
        recordedAt: DateTime.parse(row['recorded_at'] as String),
      );

  static String dayKey(DateTime at) {
    final utc = at.toUtc();
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    return '${utc.year}-$month-$day';
  }
}

/// Persists a true marked-to-market equity history (deferred from Phase 5).
///
/// One row per UTC day, upserted as the day progresses, so the equity curve
/// reflects live prices rather than only trade prices.
class EquitySnapshotRepository {
  EquitySnapshotRepository(this._db);

  final AppDatabase _db;

  static const String _upsertSql = '''
    INSERT INTO equity_snapshots (
      account_id, day, net_liquidation, cash, market_value, realised_pnl,
      unrealised_pnl, recorded_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(account_id, day) DO UPDATE SET
      net_liquidation = excluded.net_liquidation,
      cash = excluded.cash,
      market_value = excluded.market_value,
      realised_pnl = excluded.realised_pnl,
      unrealised_pnl = excluded.unrealised_pnl,
      recorded_at = excluded.recorded_at;
  ''';

  void record({
    required DateTime at,
    required double netLiquidation,
    required double cash,
    required double marketValue,
    required double realisedPnl,
    required double unrealisedPnl,
    String accountId = 'default',
  }) {
    _db.raw.execute(_upsertSql, [
      accountId,
      EquitySnapshot.dayKey(at),
      netLiquidation,
      cash,
      marketValue,
      realisedPnl,
      unrealisedPnl,
      at.toUtc().toIso8601String(),
    ]);
  }

  /// Snapshots for one portfolio, oldest first.
  List<EquitySnapshot> all({String? accountId}) {
    final rows = accountId == null
        ? _db.raw.select('SELECT * FROM equity_snapshots ORDER BY day;')
        : _db.raw.select(
            'SELECT * FROM equity_snapshots WHERE account_id = ? ORDER BY day;',
            [accountId],
          );
    return rows.map(EquitySnapshot.fromRow).toList(growable: false);
  }

  int count({String? accountId}) {
    final row = accountId == null
        ? _db.raw.select('SELECT count(*) AS c FROM equity_snapshots;').first
        : _db.raw.select(
            'SELECT count(*) AS c FROM equity_snapshots WHERE account_id = ?;',
            [accountId],
          ).first;
    return row['c'] as int;
  }
}
