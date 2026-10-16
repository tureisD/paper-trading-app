import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'schema.dart';

/// A thin, synchronous wrapper around the local SQLite database.
///
/// Synchronous access keeps local reads/writes sub-millisecond on the UI
/// thread (the ledger operations here are tiny). Heavy analytical queries will
/// be moved to a background isolate in a later phase.
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  /// Escape hatch for repositories that need the raw handle.
  Database get raw => _db;

  /// Opens a file-backed database and applies pragmas + migrations.
  factory AppDatabase.open(String path) {
    final file = File(path);
    final parent = file.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    final db = sqlite3.open(path);
    return AppDatabase._(_prepare(db));
  }

  /// Opens a throwaway in-memory database (used by tests).
  factory AppDatabase.inMemory() {
    return AppDatabase._(_prepare(sqlite3.openInMemory()));
  }

  static Database _prepare(Database db) {
    _applyPragmas(db);
    _migrate(db);
    return db;
  }

  static void _applyPragmas(Database db) {
    // Write-Ahead Logging: concurrent readers never block the writer.
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA synchronous = NORMAL;');
    db.execute('PRAGMA foreign_keys = ON;');
    db.execute('PRAGMA busy_timeout = 5000;');
    db.execute('PRAGMA temp_store = MEMORY;');
  }

  static void _migrate(Database db) {
    final current = db.userVersion;
    if (current >= Schema.version) return;

    db.execute('BEGIN;');
    try {
      for (var v = current; v < Schema.version; v++) {
        for (final statement in Schema.migrations[v]) {
          db.execute(statement);
        }
      }
      db.userVersion = Schema.version;
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    }
  }

  /// Effective journal mode, e.g. `wal` (file-backed) or `memory` (in-memory).
  String get journalMode {
    final row = _db.select('PRAGMA journal_mode;').first;
    return (row['journal_mode'] as String).toLowerCase();
  }

  /// Currently applied schema version.
  int get schemaVersion => _db.userVersion;

  /// Number of rows in the append-only ledger.
  int ledgerEventCount() =>
      _db.select('SELECT count(*) AS c FROM ledger_events;').first['c'] as int;

  /// Number of rows in the FTS5 instrument index.
  int instrumentCount() =>
      _db.select('SELECT count(*) AS c FROM instrument_search;').first['c']
          as int;

  /// Simple key/value accessor for sync bookkeeping (gist id, etag, ...).
  String? getSyncState(String key) {
    final rows =
        _db.select('SELECT value FROM sync_state WHERE key = ?;', [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  /// Upsert a sync bookkeeping value.
  void setSyncState(String key, String? value) {
    _db.execute(
      'INSERT INTO sync_state(key, value) VALUES(?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value;',
      [key, value],
    );
  }

  void close() => _db.close();
}
