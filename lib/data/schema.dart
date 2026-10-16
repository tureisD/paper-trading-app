/// Versioned SQLite schema.
///
/// Migrations are applied in order; `PRAGMA user_version` tracks the applied
/// version. Add a new list for each bump and never edit an existing one.
class Schema {
  const Schema._();

  /// Current schema version (== index of the last applied migration).
  static const int version = 1;

  /// Ordered migrations. `migrations[0]` takes the DB from v0 -> v1, etc.
  static const List<List<String>> migrations = <List<String>>[
    _v1,
  ];

  /// v1 — append-only event ledger + FTS5 instrument index + sync bookkeeping.
  static const List<String> _v1 = <String>[
    '''
    CREATE TABLE IF NOT EXISTS ledger_events (
        event_id         TEXT PRIMARY KEY,
        hlc_timestamp    TEXT NOT NULL,
        device_id        TEXT NOT NULL,
        event_type       TEXT NOT NULL,
        symbol           TEXT,
        asset_class      TEXT,
        quantity         REAL NOT NULL DEFAULT 0.0,
        execution_price  REAL NOT NULL DEFAULT 0.0,
        accrued_interest REAL NOT NULL DEFAULT 0.0,
        fee              REAL NOT NULL DEFAULT 0.0,
        currency         TEXT NOT NULL DEFAULT 'USD',
        synced           INTEGER NOT NULL DEFAULT 0
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_ledger_hlc ON ledger_events(hlc_timestamp);',
    'CREATE INDEX IF NOT EXISTS idx_ledger_synced ON ledger_events(synced);',
    'CREATE INDEX IF NOT EXISTS idx_ledger_symbol ON ledger_events(symbol);',
    '''
    CREATE VIRTUAL TABLE IF NOT EXISTS instrument_search USING fts5(
        symbol,
        name,
        isin,
        asset_class,
        exchange,
        tokenize = 'unicode61'
    );
    ''',
    '''
    CREATE TABLE IF NOT EXISTS sync_state (
        key   TEXT PRIMARY KEY,
        value TEXT
    );
    ''',
  ];
}
