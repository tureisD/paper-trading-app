# Paper Terminal

High-performance multi-asset paper trading terminal for **Windows** and **Android**.

Built with Flutter (AOT-compiled, native rendering) and a local-first SQLite
engine. Portfolio state is never stored — it is replayed from an append-only
event ledger, which is what makes cross-device sync (via a GitHub Gist vault)
conflict-free.

See [`paper_trading_app_roadmap_architecture.md`](paper_trading_app_roadmap_architecture.md)
for the full roadmap and architecture.

## Status

| Phase | Scope | State |
| :--- | :--- | :--- |
| **1** | Core engine, local SQLite, design tokens | ✅ Done |
| **2** | Multi-asset market data (search + quotes) | ✅ Done |
| **3** | Double-entry trading engine | ✅ Done |
| **4** | GitHub Gist cross-device sync | ✅ Done |
| **5** | Tab 1 — Holdings, overview & P&L | ✅ Done |
| **6** | Tab 2 — Search & order ticket | ✅ Done |
| 7 | Profiling & native packaging | ⬜ Not started |

## Requirements

- **Flutter 3.47.7** (stable). In this environment the SDK lives at
  `C:\Users\Public\flutter` (outside the repo, and on a space-free path).
- **Visual Studio 2022 Build Tools** with the C++ desktop workload (present).
- Android builds additionally need the Android SDK/JDK (not yet installed).

## Run

```bash
flutter run -d windows          # debug
flutter build windows --release # portable desktop build
flutter test                    # engine + widget tests
flutter analyze
```

## Where the data lives

The local SQLite database is created per-user:

- Windows: `%APPDATA%\PaperTradingApp\paper_trading.db` (WAL mode)

## Layout

```
lib/
  analytics/       portfolio metrics, equity curve, trade statistics
  core/            ids (UUIDv7), formatting helpers
  data/            SQLite database, versioned schema, ledger repository
  design/          design tokens + Material theme
  features/common/ shared UI primitives
  features/discovery/ Tab 2 - search, chart, detail sheet
  features/home/   application shell (two-tab frame)
  features/portfolio/ Tab 1 - summary, holdings, analytics
  features/sync/   vault setup dialog
  features/trade/  order ticket
  market/          asset classes, providers, catalog search, quote cache
  sync/            HLC, shard codec, gist client, sync engine
  trading/         ledger replay, WAC accounting, matching engine
```

## Market data (Phase 2)

Keyless-first: no API keys are required for any provider shipped today.

| Asset class | Provider | Endpoint |
| :--- | :--- | :--- |
| Stocks, ETFs, Funds | `yahoo` | `query1.finance.yahoo.com/v8/finance/chart` |
| Crypto | `binance` | `api.binance.com/api/v3` (+ `data-api.binance.vision` mirror) |
| Bonds / yields | `fred` | `fred.stlouisfed.org/graph/fredgraph.csv` |

- **Local search:** the instrument catalog lives in SQLite and is queried through
  the FTS5 index (sub-millisecond, fully offline).
- **Routing:** each instrument stores `provider` + `provider_symbol`, so
  keyed providers (Finnhub, Alpaca, Polygon, Twelve Data) can be added as
  drop-in `MarketDataProvider` implementations without touching the UI.
- **Bulk refresh:** bounded concurrency (6 at a time), best-effort per symbol.
- **Seeds:** `assets/data/instruments.json` (~76 instruments covering every
  asset class). The schema/FTS index are sized for 50k+; expand by appending.
- **Not yet implemented:** ECB Data Portal provider, streaming WebSockets.

## Trading engine (Phase 3)

Fills are appended to the immutable `ledger_events` log; portfolio state (cash,
Weighted Average Cost, realised P&L) is always **re-derived by replay**, never
mutated in place (roadmap §4.1, §5.2).

| Asset class | Execution rules |
| :--- | :--- |
| Stocks / ETFs | Market, limit, stop; fractional quantities; ±0.02% simulated slippage |
| Crypto | 24/7; quantities down to 1e-8; 0.10% maker/taker fee |
| Funds | Intraday orders rest as `QUEUED_NAV` and settle at the next EOD NAV |
| Bonds | Quoted clean, settled dirty (clean + accrued interest); coupons credited once per coupon date |

- **Schema v3**: `accounts`, `pending_orders`, `positions_cache`,
  `bond_coupon_credits`.
- **Order book**: non-marketable orders rest locally and are re-evaluated on
  every quote update.
- **Risk checks**: buying power for buys, held quantity for sells. Rejections
  are recorded as rejected orders, not thrown.
- **Bond maths**: coupon dates and accrued interest are UTC-stable (a date parsed
  as local time shifts the schedule by a day — see `BondMath.parseDateUtc`).
- **Note**: pending orders are device-local working state; only fills enter the
  synced ledger.

## Cross-device sync (Phase 4)

Portfolio history syncs through **one secret GitHub Gist that you own** — no
backend, and no account beyond GitHub.

- **Ledger, not balances**: only immutable events move between devices. Both
  sides replay the same events and derive identical state.
- **Hybrid Logical Clock**: each event carries a UUIDv7 plus an HLC stamp
  (`<iso8601>#<counter>`) that stays monotonic even if the devices' clocks
  disagree.
- **One shard per device per month**: `ledger.<device>.<yyyy-MM>.ndjson`. A
  device only ever rewrites its own current-month file, so two devices cannot
  clobber each other and no shard grows without bound. `meta.json` lists the
  participating devices.
- **Cheap polling**: conditional `GET` with `If-None-Match`; a `304` costs no
  rate-limit budget, and nothing is pushed when there is nothing new.
- **Token at rest**: the GitHub token is encrypted with **Windows DPAPI**
  (`CryptProtectData`) through `dart:ffi` before being written to SQLite — no
  plugin, and only the same Windows user can decrypt it.

### Setup

1. Create a token with the `gists` scope (classic) or the **Gists** user
   permission, read and write (fine-grained).
2. In the app open **SYNC (GIST VAULT) → SETUP / SYNC**, paste the token, leave
   the gist id blank to create a vault (or paste an existing one to link a
   second device), then **CONNECT & SYNC**.

The header pill reports `SYNCED • GIST • 12ms`, `SYNCING…`,
`OFFLINE • QUEUED (n)` or `SYNC ERROR`.

A live two-device test is available (creates and deletes a temporary secret
gist):

```bash
TB_GIST_TOKEN=... flutter test test/sync_smoke.dart
```

## Portfolio analytics (Phase 5)

**Summary header** — Net Liquidation Value (cash + market value), Day P&L,
Total P&L (realised + unrealised), Buying Power and Accrued Bond Interest
Receivable. `MARK TO MARKET` refreshes quotes for everything held (Tab 1 also
marks the book once on first display).

**Holdings table** — symbol, ISIN, asset-class badge, quantity, average cost,
last price, market value, unrealised \$/%, and portfolio weight. Rows are sorted
by market value.

**Analytics drawer** — canvas equity curve with 1D/1W/1M/1Y/ALL ranges, plus
realised P&L, win/loss ratio, maximum drawdown and Sharpe ratio, and a
monochrome asset-allocation bar.

Bases worth knowing (all documented in the UI too):

- The **equity curve** marks each historical point at the *last traded price*
  per instrument (the only historical price the app stores) and the most recent
  point at live quotes. No historical price feed is required, and no backfilled
  fiction is invented.
- **Sharpe** uses daily observations, a 0% risk-free rate and √252
  annualisation; it reports `—` until there are at least three days of history.
- **Win/loss** counts closing (sell) trades by realised P&L under the same
  Weighted Average Cost replay used everywhere else.

## Discovery & execution (Phase 6)

**Split pane** at ≥900 px: the master list on the left, the detail/execution
sheet on the right. Below that width (Android) a row tap opens the ticket as a
modal instead.

- **Search** runs locally against the FTS5 index over symbol, name and ISIN,
  with asset-class filter pills. `/` jumps straight to the search box.
- **Chart** — candlesticks with a volume strip for equities, ETFs, funds and
  crypto; a yield line for bond series (which have no intraday range). Ranges:
  1M / 3M / 6M / 1Y.
- **Asset-specific metrics** — expense ratio for ETFs and funds; 24h high/low
  and volume for crypto; for bonds, the yield and change in bp, plus coupon,
  maturity, computed YTM and modified duration whenever a coupon schedule
  exists (par-yield indices have none and are labelled as such).
- **Order ticket** — buy/sell, market / limit / stop, and a units ⇄ cash sizing
  toggle. Market orders fill immediately; limit and stop orders rest in the
  local book and are re-evaluated on every quote update; funds queue for the
  next EOD NAV.
- **Keymap** — `Ctrl+1` / `Ctrl+2` tabs, `/` search, `Ctrl+R` refresh quotes,
  `Esc` dismiss.

Schema v4 adds `instruments.expense_ratio`, and the catalog carries a version so
existing installs refresh their instruments in place instead of re-seeding.

## Design review screenshots

Renders the app offscreen (no window, no network, deterministic fake provider)
to a PNG:

```bash
RENDER_SCREENSHOTS=1 RENDER_OUT=shot.png flutter test test/render_screenshots.dart
# add RENDER_VIEW=discovery for the Tab 2 split pane
```

Not part of the normal `flutter test` run.

## Notes & caveats

- **Developer Mode:** Flutter requires Windows Developer Mode to build with any
  native *plugin* (symlinks). This build intentionally uses **zero plugins**, so
  it compiles today. Enabling Developer Mode is required before Android work
  (and before re-introducing `path_provider` for Android data paths).
- `sqlite3_flutter_libs` is **not** used: `package:sqlite3` 3.x bundles SQLite
  via build hooks (the resulting `sqlite3.dll` ships next to the `.exe`).
- `path_provider` is intentionally omitted on Windows; data paths are resolved
  directly from the environment (`lib/data/app_paths.dart`).
