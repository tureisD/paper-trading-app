import '../data/app_database.dart';
import 'models/quote.dart';

/// Local cache of the most recent quote per instrument.
///
/// Quotes are display data, never ledger data: they are safe to overwrite and
/// are never synced between devices.
class QuoteRepository {
  QuoteRepository(this._db);

  final AppDatabase _db;

  static const String _upsertSql = '''
    INSERT INTO quotes (
      symbol, price, previous_close, change, change_percent, currency, as_of, source
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(symbol) DO UPDATE SET
      price = excluded.price,
      previous_close = excluded.previous_close,
      change = excluded.change,
      change_percent = excluded.change_percent,
      currency = excluded.currency,
      as_of = excluded.as_of,
      source = excluded.source;
  ''';

  void save(Quote quote) => _db.raw.execute(_upsertSql, quote.toSqlParams());

  void saveAll(Iterable<Quote> quotes) {
    _db.raw.execute('BEGIN;');
    try {
      for (final quote in quotes) {
        save(quote);
      }
      _db.raw.execute('COMMIT;');
    } catch (_) {
      _db.raw.execute('ROLLBACK;');
      rethrow;
    }
  }

  Quote? get(String symbol) {
    final rows =
        _db.raw.select('SELECT * FROM quotes WHERE symbol = ?;', [symbol]);
    return rows.isEmpty ? null : Quote.fromRow(rows.first);
  }

  Map<String, Quote> getMany(Iterable<String> symbols) {
    final list = symbols.toList(growable: false);
    if (list.isEmpty) return const {};
    final placeholders = List.filled(list.length, '?').join(', ');
    final rows = _db.raw
        .select('SELECT * FROM quotes WHERE symbol IN ($placeholders);', list);
    return {
      for (final row in rows) row['symbol'] as String: Quote.fromRow(row),
    };
  }

  int count() =>
      _db.raw.select('SELECT count(*) AS c FROM quotes;').first['c'] as int;
}
