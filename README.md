# TureisBanking

A high-performance, **local-first paper trading terminal** for **Windows and
Android**. Trade stocks, ETFs, mutual funds, crypto, bonds and indices with
simulated money — across US, European, Asian and Latin American markets — while
your portfolio syncs between devices for free through a GitHub Gist.

No backend. No accounts. No subscription. Your data stays yours.

<p align="center">
  <img src="docs/screenshot-portfolio-dark.png" width="49%" alt="Portfolio tab (dark)" />
  <img src="docs/screenshot-discovery.png" width="49%" alt="Discovery tab with chart and order ticket" />
</p>
<p align="center">
  <img src="docs/screenshot-portfolio-light.png" width="70%" alt="Portfolio tab (light theme)" />
</p>

---

## What it is

A trading terminal that *feels* like one: dense hairline tables, tabular
numerals that never jitter, no gradients, no glassmorphism, no "AI template"
look. Everything renders locally at 60/120 Hz and works fully offline — market
data and sync are the only things that need a network.

**Core idea:** the portfolio is never stored as balances. It is an
**append-only ledger of events** (`CASH_DEPOSIT`, `BUY`, `SELL`, `BOND_COUPON`),
and every balance, cost basis and P&L figure is *derived by replaying it*. That
single decision is what makes cross-device sync trivial and conflict-free.

## Highlights

- **~12,100 instruments** — the full US symbol directory (NASDAQ, NYSE, NYSE
  American, NYSE Arca, Cboe, IEX) plus curated EU/Asia/Americas listings and 26
  global indices, all searchable instantly offline via SQLite FTS5.
- **Real market data, no API keys** — Yahoo Finance (stocks/ETFs/funds/indices),
  Binance (crypto REST **and** a live WebSocket stream), FRED (US Treasury
  yields), ECB Data Portal (euro-area yields).
- **Live streaming with frame coalescing** — crypto ticks are buffered and
  flushed at most once per frame (60 Hz, or 120 Hz), so a fast stream can never
  block the UI.
- **Asset-specific execution** — fractional shares and simulated spread on
  equities, 1e-8 precision and maker/taker fees on crypto, `QUEUED_NAV`
  settlement on funds, and clean-price quoting with dirty-price settlement plus
  automatic coupon crediting on bonds.
- **Proper risk analytics** — Weighted Average Cost basis, realised vs
  unrealised P&L, day P&L, equity curve, maximum drawdown, Sharpe ratio,
  win/loss ratio, and asset allocation.
- **Free forever sync** — one secret GitHub Gist per user, hybrid logical clocks,
  per-device monthly shards. See [Cross-device sync](#cross-device-sync).
- **Two themes** — matte-carbon dark and crisp paper light.
- **Both platforms build today** — portable Windows `.exe`, Android `.apk`/`.aab`.

---

## Getting started

### Requirements

- [Flutter](https://docs.flutter.dev/get-started/install) 3.47.7 (stable) or newer
- **Windows:** Visual Studio 2022 with the *Desktop development with C++* workload
- **Android:** Android SDK (platform 35+), build-tools, and a JDK 17

> The project uses **zero Flutter plugins**, so it builds without enabling
> Windows Developer Mode. Adding a plugin will require it.

### Run

```bash
flutter pub get
flutter run -d windows      # or: flutter run -d <android-device>
```

First launch seeds the instrument catalog (about 12,000 rows, ~0.2 s) and opens a
paper account with $100,000 of simulated cash.

### Build release artefacts

```bash
flutter build windows --release        # build/windows/x64/runner/Release/
flutter build apk --release            # universal APK
flutter build appbundle --release --obfuscate --split-debug-info=build/app/outputs/symbols
```

The Windows output folder is self-contained (`TureisBanking.exe` +
`flutter_windows.dll` + `data/` + `sqlite3.dll`); zip it for a portable build.

---

## Using the app

### Tab 1 — Portfolio

| Area | What it does |
| :--- | :--- |
| **Account header** | Net Liquidation Value, Day P&L, Total P&L (realised + unrealised), Buying Power, Accrued Bond Interest Receivable |
| **Holdings table** | Symbol, ISIN, asset-class badge, quantity, average cost, last price, market value, unrealised \$/%, portfolio weight |
| **Quick trade** | `BUY` / `SELL` / `ALL` on every row opens the order ticket pre-filled — sell a slice, or close the position outright |
| **Analytics** | Equity curve with 1D/1W/1M/1Y/ALL, realised P&L, win/loss ratio, maximum drawdown, Sharpe ratio, allocation bar |
| **Settings** | Switch dark/light theme and add a custom amount of simulated funds |

- **DEPOSIT CASH** credits the amount configured in Settings.
- **MARK TO MARKET** refreshes quotes for everything you hold and records today's
  valuation, which is what grows the equity curve into a real daily history.

### Tab 2 — Discovery

- **Search** tickers, company names or ISINs instantly (offline full-text).
- **Category pills**: All / Stocks / ETFs / Funds / Crypto / Bonds / Indices.
- **Detail sheet** (split pane on wide screens): price header with the live
  change, price history chart, asset metrics, and the order ticket.
- **Chart**: candlesticks with a volume strip or a line — **click the chart to
  toggle**. A dashed line marks the live price, and the header shows the
  percentage change across the selected window (`1W` uses hourly bars).
- **Metrics** adapt to the asset class: expense ratio for ETFs/funds, 24h
  high/low/volume for crypto, and yield, coupon, maturity, computed YTM and
  modified duration for bonds.

### Order ticket

Buy/sell · market, limit or stop · size in **units or cash**. Market orders fill
instantly; limit and stop orders rest locally and are re-evaluated on every
quote update; fund orders queue for the next end-of-day NAV.

### Keyboard

| Key | Action |
| :--- | :--- |
| `Ctrl+1` / `Ctrl+2` | Switch tab |
| `/` | Jump to search |
| `Ctrl+R` | Refresh quotes (Discovery) |
| `Esc` | Dismiss |

---

## Cross-device sync

Portfolio history syncs through **one secret GitHub Gist that you own**.

### Setup

1. Create a token with the **`gist`** scope (classic PAT) or the **Gists: read
   and write** account permission (fine-grained PAT).
2. In the app, click the status pill (top right) or **SYNC (GIST VAULT) →
   SETUP / SYNC**.
3. Paste the token, **leave the gist id blank** to create a vault, then
   **CONNECT & SYNC**. The header pill turns green: `SYNCED • GIST • 12ms`.
4. On a second device, paste the same token and **the gist id from step 3**.

### How it works

- Only **events** travel. Balances, cost basis and P&L are recomputed locally.
- Every event carries a **UUIDv7** id and a **Hybrid Logical Clock** stamp
  (`<iso8601>#<counter>`), which stays monotonic even if device clocks disagree.
- Each device writes **only its own monthly shard**
  (`ledger.<device>.<yyyy-MM>.ndjson`), so two devices can never overwrite each
  other and no file grows without bound. A `meta.json` lists devices.
- Pulls use conditional `GET` with `If-None-Match`; a `304` costs **zero**
  rate-limit budget, and unchanged shards are skipped by content hash.
- The token is encrypted at rest with **Windows DPAPI** (user-scoped) before it
  touches the database.
- Resting limit/stop orders are **device-local**; only fills are synced.

---

## Market data

All providers are keyless. Quotes are display data — never ledger data — and are
never synced.

| Asset class | Provider | Source |
| :--- | :--- | :--- |
| Stocks, ETFs, Funds, Indices | `yahoo` | `query1.finance.yahoo.com` chart API |
| Crypto | `binance` | REST (`api.binance.com`, `data-api.binance.vision` mirror) + WebSocket |
| US Treasury yields | `fred` | `fred.stlouisfed.org/graph/fredgraph.csv` |
| Euro-area yields | `ecb` | `data-api.ecb.europa.eu` (SDMX CSV) |

Adding a keyed provider (Finnhub, Alpaca, Polygon, Twelve Data) means
implementing one interface and registering it — the UI does not change.

---

## How it's built

### Stack

| Layer | Choice |
| :--- | :--- |
| UI | Flutter 3.47 (AOT-compiled, Impeller/Skia rendering) |
| Storage | SQLite via `package:sqlite3` 3.x, native binaries bundled through build hooks |
| Networking | `package:http`, `dart:io` WebSocket |
| Crypto at rest | Windows DPAPI through `dart:ffi` |
| Plugins | **None** — everything is Dart or FFI |

### Architecture

```
lib/
  analytics/   portfolio metrics, equity curve + snapshots, trade statistics
  core/        ids (UUIDv7), UTC date helpers, formatting
  data/        SQLite database, versioned schema, ledger repository, settings
  design/      design tokens + palette, Material theme, theme controller
  features/    common primitives, home shell, portfolio, discovery, trade,
               sync, settings
  market/      asset classes, providers, catalog + FTS5 search, quote cache,
               live streaming (coalescer, Binance WebSocket)
  sync/        HLC, shard codec, gist client, config store, sync engine
  trading/     ledger replay, WAC accounting, matching engine, bond math
```

**The ledger is the only source of truth.** `PortfolioEngine.replay` turns the
event log into cash, positions and realised P&L deterministically; the
`positions_cache` table is a disposable materialisation of that replay.

### Schema (SQLite, `PRAGMA user_version` migrates forward)

| Table | Purpose |
| :--- | :--- |
| `ledger_events` | Append-only event log (UUIDv7, HLC stamp, meta JSON) |
| `instrument_search` | FTS5 index over symbol / name / ISIN |
| `instruments` | Catalog: class, exchange, currency, ISIN, provider, expense ratio |
| `bond_details` | Coupon rate, maturity, par, frequency, day count |
| `quotes` | Latest quote per symbol (device-local cache) |
| `accounts`, `pending_orders`, `positions_cache` | Account, working book, replay cache |
| `bond_coupon_credits` | Idempotency ledger for coupon payments |
| `equity_snapshots` | Daily marked-to-market valuations |
| `sync_state` | Vault config, ETags, shard hashes, UI settings |

### Notable decisions

- **Replay over mutation.** Any device can rebuild identical state from the same
  events, which is why sync needs no conflict resolution.
- **Zero plugins.** Everything is Dart or `dart:ffi`, so Windows Developer Mode
  is never required. That is also why the GitHub token uses DPAPI directly.
- **Shard per device per month.** Removes write contention and gives shard
  rotation for free.
- **UTC-stable date parsing.** `DateTime.parse('2030-01-15')` is *local* and
  shifts by a day; every schedule goes through `parseDateUtc` instead.
- **Coalesced ticks.** `QuoteBatcher` guarantees at most one UI update, one cache
  write and one order-evaluation pass per frame.

---

## Roadmap

All seven phases are implemented — see
[`paper_trading_app_roadmap_architecture.md`](paper_trading_app_roadmap_architecture.md),
which also documents the mathematics (WAC, Sharpe, drawdown, bond pricing and
duration) and where the build deviated from the original plan.

| Phase | Scope | Status |
| :--- | :--- | :--- |
| 1 | Core engine, SQLite, design tokens | ✅ |
| 2 | Multi-asset market data | ✅ |
| 3 | Double-entry trading engine | ✅ |
| 4 | GitHub Gist cross-device sync | ✅ |
| 5 | Tab 1 — holdings, overview, P&L | ✅ |
| 6 | Tab 2 — search, chart, order ticket | ✅ |
| 7 | Live streaming, packaging | ✅ |

---

## Testing

```bash
flutter analyze
flutter test
```

The suite covers the accounting and matching engine (WAC, fees, slippage, lot
precision, resting/stop orders, fund NAV settlement, bond accrual and coupon
idempotency), portfolio analytics, sync (two-device convergence against a fake
gist, ETag/304, rate-limit translation), streaming (coalescing with `fake_async`,
Binance parsing), and the providers (mocked HTTP).

Optional live checks (excluded from normal runs):

```bash
TB_GIST_TOKEN=... flutter test test/sync_smoke.dart        # real gist round-trip, self-cleaning
TB_LIVE=1         flutter test test/live_stream_smoke.dart # real Binance WebSocket
TB_SEED=1         flutter test test/catalog_seed_smoke.dart# full catalog seed timing
RENDER_SCREENSHOTS=1 RENDER_OUT=shot.png flutter test test/render_screenshots.dart
```

---

## Data & licensing

- Instrument listings derive from the **NASDAQ Trader symbol directory** (public)
  and a curated international set; Yahoo symbols encode the venue suffix
  (`.DE`, `.L`, `.T`, `.HK`, `.NS`, …).
- Market data comes from each provider's public endpoints and is subject to
  their terms. This is a **simulation** — no orders ever reach a real market.
- **Known caveats:** London (`.L`) prices arrive in pence, not pounds. Indices are
  tradable as synthetic instruments with no contract specification.

## Limitations

- **Resting-order sync** is not implemented — pending orders stay on the device
  that placed them (a decision on cross-device cancel/partial-fill semantics is
  needed first).
- **Keyed providers** are not wired up (no API keys were available); the
  interface is ready for them.
- **Release APKs/AABs are debug-key signed** — add a keystore before
  distribution. An MSIX package needs a signing certificate, so the portable
  Windows folder/zip is the distribution path.
- **No 50k+ institutional dataset** — the ~12,100 bundled instruments cover the
  listed universe; a full global dataset needs a licensed source.
