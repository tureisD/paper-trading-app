/// Versioned SQLite schema.
///
/// Migrations are applied in order; `PRAGMA user_version` tracks the applied
/// version. Add a new list for each bump and never edit an existing one.
class Schema {
  const Schema._();

  /// Current schema version (== index of the last applied migration).
  static const int version = 6;

  /// Ordered migrations. `migrations[0]` takes the DB from v0 -> v1, etc.
  static const List<List<String>> migrations = <List<String>>[
    _v1,
    _v2,
    _v3,
    _v4,
    _v5,
    _v6,
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

  /// v2 — multi-asset instrument catalog, bond reference data and quote cache.
  static const List<String> _v2 = <String>[
    '''
    CREATE TABLE IF NOT EXISTS instruments (
        symbol          TEXT PRIMARY KEY,
        name            TEXT NOT NULL,
        asset_class     TEXT NOT NULL,
        exchange        TEXT,
        currency        TEXT NOT NULL DEFAULT 'USD',
        isin            TEXT,
        cusip           TEXT,
        provider        TEXT,
        provider_symbol TEXT,
        updated_at      TEXT
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_instruments_class ON instruments(asset_class);',
    'CREATE INDEX IF NOT EXISTS idx_instruments_isin ON instruments(isin);',
    '''
    CREATE TABLE IF NOT EXISTS bond_details (
        symbol           TEXT PRIMARY KEY,
        coupon_rate      REAL,
        maturity_date    TEXT,
        par_value        REAL,
        coupon_frequency INTEGER,
        day_count        TEXT,
        FOREIGN KEY (symbol) REFERENCES instruments(symbol) ON DELETE CASCADE
    );
    ''',
    '''
    CREATE TABLE IF NOT EXISTS quotes (
        symbol         TEXT PRIMARY KEY,
        price          REAL NOT NULL,
        previous_close REAL,
        change         REAL,
        change_percent REAL,
        currency       TEXT NOT NULL DEFAULT 'USD',
        as_of          TEXT NOT NULL,
        source         TEXT NOT NULL
    );
    ''',
  ];

  /// v3 — trading engine: accounts, working order book, position cache and
  /// idempotent bond coupon crediting.
  static const List<String> _v3 = <String>[
    '''
    CREATE TABLE IF NOT EXISTS accounts (
        account_id    TEXT PRIMARY KEY,
        name          TEXT NOT NULL,
        base_currency TEXT NOT NULL DEFAULT 'USD',
        created_at    TEXT NOT NULL
    );
    ''',
    '''
    CREATE TABLE IF NOT EXISTS pending_orders (
        order_id       TEXT PRIMARY KEY,
        account_id     TEXT NOT NULL,
        symbol         TEXT NOT NULL,
        asset_class    TEXT NOT NULL,
        side           TEXT NOT NULL,
        order_type     TEXT NOT NULL,
        quantity       REAL NOT NULL,
        limit_price    REAL,
        stop_price     REAL,
        status         TEXT NOT NULL,
        created_at     TEXT NOT NULL,
        updated_at     TEXT NOT NULL,
        filled_event_id TEXT,
        note           TEXT
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_pending_status ON pending_orders(status, symbol);',
    '''
    CREATE TABLE IF NOT EXISTS positions_cache (
        account_id   TEXT NOT NULL,
        symbol       TEXT NOT NULL,
        asset_class  TEXT NOT NULL,
        quantity     REAL NOT NULL,
        average_cost REAL NOT NULL,
        realised_pnl REAL NOT NULL,
        updated_at   TEXT NOT NULL,
        PRIMARY KEY (account_id, symbol)
    );
    ''',
    '''
    CREATE TABLE IF NOT EXISTS bond_coupon_credits (
        symbol      TEXT NOT NULL,
        coupon_date TEXT NOT NULL,
        event_id    TEXT NOT NULL,
        credited_at TEXT NOT NULL,
        PRIMARY KEY (symbol, coupon_date)
    );
    ''',
  ];

  /// v4 — fund/ETF cost data for the asset detail sheet.
  static const List<String> _v4 = <String>[
    'ALTER TABLE instruments ADD COLUMN expense_ratio REAL;',
  ];

  /// v5 — daily equity snapshots (a true marked-to-market curve) and a free-form
  /// metadata column on ledger events (order linkage, coupon dates).
  static const List<String> _v5 = <String>[
    '''
    CREATE TABLE IF NOT EXISTS equity_snapshots (
        day             TEXT PRIMARY KEY,
        net_liquidation REAL NOT NULL,
        cash            REAL NOT NULL,
        market_value    REAL NOT NULL,
        realised_pnl    REAL NOT NULL,
        unrealised_pnl  REAL NOT NULL,
        recorded_at     TEXT NOT NULL
    );
    ''',
    'ALTER TABLE ledger_events ADD COLUMN meta TEXT;',
  ];

  /// v6 — multiple portfolios: events and equity snapshots become account-scoped.
  static const List<String> _v6 = <String>[
    "ALTER TABLE ledger_events ADD COLUMN account_id TEXT NOT NULL DEFAULT 'default';",
    'CREATE INDEX IF NOT EXISTS idx_ledger_account ON ledger_events(account_id);',
    '''
    CREATE TABLE IF NOT EXISTS equity_snapshots_v2 (
        account_id      TEXT NOT NULL,
        day             TEXT NOT NULL,
        net_liquidation REAL NOT NULL,
        cash            REAL NOT NULL,
        market_value    REAL NOT NULL,
        realised_pnl    REAL NOT NULL,
        unrealised_pnl  REAL NOT NULL,
        recorded_at     TEXT NOT NULL,
        PRIMARY KEY (account_id, day)
    );
    ''',
    '''
    INSERT OR IGNORE INTO equity_snapshots_v2 (
        account_id, day, net_liquidation, cash, market_value, realised_pnl,
        unrealised_pnl, recorded_at
    ) SELECT 'default', day, net_liquidation, cash, market_value, realised_pnl,
             unrealised_pnl, recorded_at
      FROM equity_snapshots;
    ''',
    'DROP TABLE IF EXISTS equity_snapshots;',
    'ALTER TABLE equity_snapshots_v2 RENAME TO equity_snapshots;',
    '''
    CREATE TABLE IF NOT EXISTS bond_coupon_credits_v2 (
        account_id  TEXT NOT NULL,
        symbol      TEXT NOT NULL,
        coupon_date TEXT NOT NULL,
        event_id    TEXT NOT NULL,
        credited_at TEXT NOT NULL,
        PRIMARY KEY (account_id, symbol, coupon_date)
    );
    ''',
    '''
    INSERT OR IGNORE INTO bond_coupon_credits_v2 (
        account_id, symbol, coupon_date, event_id, credited_at
    ) SELECT 'default', symbol, coupon_date, event_id, credited_at
      FROM bond_coupon_credits;
    ''',
    'DROP TABLE IF EXISTS bond_coupon_credits;',
    'ALTER TABLE bond_coupon_credits_v2 RENAME TO bond_coupon_credits;',
  ];
}
