import '../data/app_database.dart';
import 'asset_class.dart';
import 'models/instrument.dart';

/// Reads and writes the local multi-asset instrument catalog.
///
/// Search is served entirely from the local SQLite FTS5 index, so it stays
/// sub-millisecond and works offline.
class InstrumentRepository {
  InstrumentRepository(this._db);

  final AppDatabase _db;

  static const String _upsertSql = '''
    INSERT INTO instruments (
      symbol, name, asset_class, exchange, currency, isin, cusip,
      provider, provider_symbol, expense_ratio, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(symbol) DO UPDATE SET
      name = excluded.name,
      asset_class = excluded.asset_class,
      exchange = excluded.exchange,
      currency = excluded.currency,
      isin = excluded.isin,
      cusip = excluded.cusip,
      provider = excluded.provider,
      provider_symbol = excluded.provider_symbol,
      expense_ratio = excluded.expense_ratio,
      updated_at = excluded.updated_at;
  ''';

  static const String _upsertBondSql = '''
    INSERT INTO bond_details (
      symbol, coupon_rate, maturity_date, par_value, coupon_frequency, day_count
    ) VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT(symbol) DO UPDATE SET
      coupon_rate = excluded.coupon_rate,
      maturity_date = excluded.maturity_date,
      par_value = excluded.par_value,
      coupon_frequency = excluded.coupon_frequency,
      day_count = excluded.day_count;
  ''';

  /// Inserts or updates an instrument and keeps the FTS index in sync.
  void upsert(Instrument instrument, {BondDetails? bondDetails}) {
    final now = DateTime.now().toUtc().toIso8601String();
    _db.raw.execute(
      _upsertSql,
      <Object?>[
        ...instrument.toSqlParams(),
        now,
      ],
    );

    _db.raw.execute(
      'DELETE FROM instrument_search WHERE symbol = ?;',
      [instrument.symbol],
    );
    _db.raw.execute(
      'INSERT INTO instrument_search(symbol, name, isin, asset_class, exchange) '
      'VALUES (?, ?, ?, ?, ?);',
      [
        instrument.symbol,
        instrument.name,
        instrument.isin,
        instrument.assetClass.wire,
        instrument.exchange,
      ],
    );

    if (bondDetails != null) {
      _db.raw.execute(
        _upsertBondSql,
        [
          instrument.symbol,
          bondDetails.couponRate,
          bondDetails.maturityDate,
          bondDetails.parValue,
          bondDetails.couponFrequency,
          bondDetails.dayCount,
        ],
      );
    }
  }

  /// Bulk insert inside a single transaction (used by the catalog importer).
  void upsertAll(
    Iterable<Instrument> instruments, {
    Map<String, BondDetails> bondDetails = const {},
  }) {
    _db.raw.execute('BEGIN;');
    try {
      for (final instrument in instruments) {
        upsert(instrument, bondDetails: bondDetails[instrument.symbol]);
      }
      _db.raw.execute('COMMIT;');
    } catch (_) {
      _db.raw.execute('ROLLBACK;');
      rethrow;
    }
  }

  Instrument? get(String symbol) {    final rows =
        _db.raw.select('SELECT * FROM instruments WHERE symbol = ?;', [symbol]);
    return rows.isEmpty ? null : Instrument.fromRow(rows.first);
  }

  BondDetails? bondDetails(String symbol) {
    final rows = _db.raw
        .select('SELECT * FROM bond_details WHERE symbol = ?;', [symbol]);
    return rows.isEmpty ? null : BondDetails.fromRow(rows.first);
  }

  /// Full-text search across symbol, name and ISIN, ranked by relevance.
  ///
  /// An empty query returns the alphabetically-first instruments.
  List<Instrument> search(
    String query, {
    AssetClass? assetClass,
    int limit = 50,
  }) {
    final match = _matchExpression(query);
    if (match == null) return _top(limit, assetClass);

    final sql = StringBuffer(
      'SELECT i.* FROM instrument_search '
      'JOIN instruments i ON i.symbol = instrument_search.symbol '
      'WHERE instrument_search MATCH ? ',
    );
    final params = <Object?>[match];
    if (assetClass != null) {
      sql.write('AND i.asset_class = ? ');
      params.add(assetClass.wire);
    }
    sql.write('ORDER BY rank LIMIT ?;');
    params.add(limit);

    final rows = _db.raw.select(sql.toString(), params);
    return rows.map(Instrument.fromRow).toList(growable: false);
  }

  List<Instrument> _top(int limit, AssetClass? assetClass) {
    final sql = StringBuffer('SELECT * FROM instruments ');
    final params = <Object?>[];
    if (assetClass != null) {
      sql.write('WHERE asset_class = ? ');
      params.add(assetClass.wire);
    }
    sql.write('ORDER BY symbol LIMIT ?;');
    params.add(limit);
    final rows = _db.raw.select(sql.toString(), params);
    return rows.map(Instrument.fromRow).toList(growable: false);
  }

  /// Bundled catalog version already imported into this database.
  String? get catalogVersion => _db.getSyncState('catalog.version');

  set catalogVersion(String? value) =>
      _db.setSyncState('catalog.version', value);

  int count() =>
      _db.raw.select('SELECT count(*) AS c FROM instruments;').first['c'] as int;

  Map<AssetClass, int> countByClass() {
    final rows = _db.raw.select(
      'SELECT asset_class, count(*) AS c FROM instruments GROUP BY asset_class;',
    );
    final result = <AssetClass, int>{};
    for (final row in rows) {
      result[AssetClass.fromWire(row['asset_class'] as String)] =
          row['c'] as int;
    }
    return result;
  }

  /// Builds a safe FTS5 prefix query from free text, or null if unusable.
  static String? _matchExpression(String input) {
    final tokens = input
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.isNotEmpty)
        .take(6)
        .toList();
    if (tokens.isEmpty) return null;
    return tokens.map((t) => '$t*').join(' AND ');
  }
}
