# TureisBanking

A **local-first paper trading terminal** for **Windows and Android** — a
synced, open alternative to apps like *BestBrokers*.

Trade ~12,100 stocks, ETFs, funds, crypto, bonds and indices with simulated
money across US, European, Asian and Latin American markets, while your
portfolio syncs between your devices for free through a GitHub Gist.

No backend. No sign-up. No subscription. Your data stays yours.

<p align="center">
  <img src="docs/screenshot-portfolio-dark.png" width="49%" alt="Portfolio tab on desktop (dark)" />
  <img src="docs/screenshot-discovery.png" width="49%" alt="Discovery tab: search, chart and order ticket" />
</p>
<p align="center">
  <img src="docs/screenshot-android-portfolio.png" width="24%" alt="Portfolio on Android" />
  <img src="docs/screenshot-android-ticket.png" width="24%" alt="Order ticket on Android" />
  <img src="docs/screenshot-portfolio-light.png" width="49%" alt="Portfolio tab in the light theme" />
</p>

---

## Why this exists

I use **BestBrokers** on Android for paper trading and like it, but kept running
into small annoyances: I wanted the same portfolio on my PC *and* my phone, a
dense table that reads like a real terminal instead of a phone app stretched
across a monitor, real European and Asian listings (not just US tickers), a
proper order ticket with limit/stop orders, and analytics that are actually
correct — weighted-average cost, Sharpe, max drawdown, bond dirty pricing.

So this started as a **weekend project** to experiment with those things and
improve the basic features and quality-of-life: a free synced broker simulator
you own end-to-end. It grew a bit past the weekend, but the goal never changed —
keep it small, local-first and honest about its numbers.

**It never touches a real market.** Every fill is simulated against public
market data.

## Highlights

- **~12,100 instruments** — the complete US symbol directory (NASDAQ, NYSE,
  NYSE American, NYSE Arca, Cboe, IEX) plus curated EU/Asia/Americas listings and
  26 global indices. Instant offline search via SQLite FTS5.
- **Multiple portfolios** — separate cash, holdings and history; each named by
  you, all synced together.
- **Real market data, no API keys** — Yahoo Finance, Binance (REST **and** live
  WebSocket), FRED, and the ECB Data Portal.
- **Honest accounting** — an append-only event ledger, replayed on every read.
  Balances, cost basis and P&L are *derived*, never stored.
- **Free forever sync** — one secret GitHub Gist per user, hybrid logical clocks,
  per-device monthly shards.
- **Correct execution rules per asset class** — fractional shares and simulated
  spread on equities, 1e-8 precision and maker/taker fees on crypto,
  `QUEUED_NAV` settlement on funds, and clean-price quotes settled at dirty
  price with automatic coupon crediting on bonds.
- **Two themes**, keyboard-first on desktop, thumb-first on mobile.
- **Responsive by design** — one codebase, two real presentations. Phones get a
  compact top bar, stacked account metrics, holding *cards* with full-width trade
  buttons and modal sheets; desktop gets the dense 10-column table and split
  panes. Everything sits inside safe areas, clear of the status bar and the
  gesture/navigation bar.
- **Both platforms build today** — portable Windows `.exe`, Android `.apk`/`.aab`.

---

## Getting started

### Requirements

- [Flutter](https://docs.flutter.dev/get-started/install) 3.47.7 stable or newer
- **Windows:** Visual Studio 2022 with *Desktop development with C++*
- **Android:** Android SDK (platform 35+), build-tools, JDK 17

> The app uses **zero Flutter plugins**, so it builds without enabling Windows
> Developer Mode. Adding a plugin will require it.

### Run

```bash
flutter pub get
flutter run -d windows      # or: flutter run -d <android-device>
```

First launch seeds the catalog (~12,000 rows, ≈0.2 s) and opens a portfolio with
$100,000 of simulated cash.

### Install a release

Grab the latest build from the
[**Releases**](https://github.com/tureisD/paper-trading-app/releases) page:

| Asset | Notes |
| :--- | :--- |
| `TureisBanking-*-windows-x64-portable.zip` | Unzip anywhere and run `TureisBanking.exe`. No installer. |
| `TureisBanking-*-android-arm64-v8a.apk` | **Recommended**, ~20 MB. |
| `TureisBanking-*-android-armeabi-v7a.apk` | Older 32-bit devices, ~17 MB. |
| `TureisBanking-*-android-x86_64.apk` | Emulators and x86 tablets, ~21 MB. |
| `TureisBanking-*-android-universal.apk` | All ABIs in one file, ~55 MB. |
| `TureisBanking-*-android.aab` | Play Store upload bundle. |

Release Android builds are **debug-key signed**, so Android may warn when
sideloading. Fine for personal use; add a keystore before distributing.

---

## Using it

### Tab 1 — Portfolio

| Area | What it does |
| :--- | :--- |
| **Account header** | Net Liquidation Value, Day P&L, Total P&L, Buying Power, Accrued Bond Interest Receivable |
| **Holdings** | Symbol, ISIN, class, quantity, average cost, last price, market value, unrealised \$/%, weight |
| **Quick trade** | `BUY` / `SELL` / `ALL` on every row opens the ticket pre-filled — sell a slice or close the position |
| **Analytics** | Equity curve (1D/1W/1M/1Y/ALL), realised P&L, win/loss ratio, max drawdown, Sharpe, allocation bar |
| **Settings** | Theme, portfolios, add funds, remove funds |

- **DEPOSIT CASH** credits the amount configured in Settings.
- **MARK TO MARKET** refreshes your holdings' quotes and records today's
  valuation (this is what grows the equity curve into a real history).

### Settings

- **Appearance** — matte-carbon dark or crisp-paper light.
- **Portfolios** — create, rename, switch and remove. Every portfolio is
  isolated: its own ledger slice, cash, positions and snapshots. New portfolios
  start with the configured opening amount. Removing one is *local* — if it has
  already synced, another linked device will upload it again, and the dialog says
  so.
- **Add funds** — credit any amount, with quick presets.
- **Remove funds** — withdraw a specific amount, or **CLEAR ALL CASH**. Both are
  recorded as ledger events, so they sync and stay visible in the history.

### Tab 2 — Discovery

- **Search** tickers, names or ISINs instantly, offline.
- **Category pills**: All / Stocks / ETFs / Funds / Crypto / Bonds / Indices.
- **Detail sheet** (split pane on wide screens) — price header, history chart,
  asset metrics, order ticket.
- **Chart** — candlesticks with volume or a line; **click the chart to toggle**.
  A dashed line marks the live price, and the header shows the change across the
  selected window (`1W` uses hourly bars).
- **Metrics** adapt: expense ratio for ETFs/funds, 24h high/low/volume for
  crypto, and yield, coupon, maturity, computed YTM and modified duration for
  bonds.

### Order ticket

Buy/sell · market, limit or stop · sized in **units or cash**. Market orders fill
immediately; limit and stop orders rest locally and are re-evaluated on every
quote update; fund orders queue for the next end-of-day NAV.

### Keyboard (desktop)

| Key | Action |
| :--- | :--- |
| `Ctrl+1` / `Ctrl+2` | Switch tab |
| `/` | Jump to search |
| `Ctrl+R` | Refresh quotes (Discovery) |
| `Esc` | Dismiss |

---

## Cross-device sync

Your history syncs through **one secret GitHub Gist that you own**.

### Setup

1. Create a token with the **`gist`** scope (classic PAT), or the **Gists: read
   and write** account permission (fine-grained PAT).
2. In the app, click the status pill (top right) or **SYNC (GIST VAULT) →
   SETUP / SYNC**.
3. Paste the token, **leave the gist id blank** to create a vault, then
   **CONNECT & SYNC**. The pill turns green: `SYNCED • GIST • 12ms`.
4. On a second device, paste the same token and **the gist id from step 3**.

### How it works

- Only **events** travel. Balances, cost basis and P&L are recomputed locally, so
  two devices can never disagree about state.
- Every event carries a **UUIDv7** id and a **Hybrid Logical Clock** stamp that
  stays monotonic even if the clocks disagree.
- Each device writes **only its own monthly shard**
  (`ledger.<device>.<yyyy-MM>.ndjson`), so two devices cannot overwrite each
  other and no file grows without bound.
- All portfolios live in the same vault; `account_id` on each event keeps them
  apart.
- Pulls are conditional (`If-None-Match`): a `304` costs **zero** rate-limit
  budget, and unchanged shards are skipped by content hash.
- Rate limits are respected automatically (`Retry-After` / `x-ratelimit-reset`).
- The token is encrypted at rest with **Windows DPAPI** (user-scoped) before it
  touches the database.
- Resting limit/stop orders stay **device-local**; only fills sync.

---

## Market data

All providers are keyless. Quotes are display data, never ledger data, and are
never synced.

| Asset class | Provider | Source |
| :--- | :--- | :--- |
| Stocks, ETFs, Funds, Indices | `yahoo` | `query1.finance.yahoo.com` chart API |
| Crypto | `binance` | REST + WebSocket (`api.binance.com`, `data-api.binance.vision`) |
| US Treasury yields | `fred` | `fred.stlouisfed.org/graph/fredgraph.csv` |
| Euro-area yields | `ecb` | `data-api.ecb.europa.eu` (SDMX CSV) |

Adding a keyed provider (Finnhub, Alpaca, Polygon, Twelve Data) means
implementing one interface and registering it — the UI doesn't change.

---

## How it's built

### Stack

| Layer | Choice |
| :--- | :--- |
| UI | Flutter 3.47, AOT-compiled, Impeller/Skia rendering |
| Storage | SQLite via `package:sqlite3` 3.x (native binaries bundled through build hooks) |
| Networking | `package:http`, `dart:io` WebSocket |
| Secrets | Windows DPAPI through `dart:ffi` |
| Plugins | **None** — everything is Dart or FFI |

### Layout

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

### The central idea: replay, don't store

The portfolio is an **append-only ledger of events**:

```
CASH_DEPOSIT · CASH_WITHDRAWAL · BUY · SELL · BOND_COUPON
```

`PortfolioEngine.replay` folds that log into cash, positions (Weighted Average
Cost) and realised P&L. `positions_cache` is a disposable materialisation of
that fold; delete it and nothing is lost. This is what makes sync easy — there
is no state to merge, only events to insert once.

### Schema (SQLite, migrated forward via `PRAGMA user_version`)

| Table | Purpose |
| :--- | :--- |
| `ledger_events` | Append-only log: UUIDv7, HLC stamp, `account_id`, meta JSON |
| `instrument_search` | FTS5 index over symbol / name / ISIN |
| `instruments` | Catalog: class, exchange, currency, ISIN, provider, expense ratio |
| `bond_details` | Coupon rate, maturity, par, frequency, day count |
| `quotes` | Latest quote per symbol (device-local cache) |
| `accounts` | Portfolios (id, name, base currency) |
| `pending_orders`, `positions_cache` | Working book and replay cache |
| `bond_coupon_credits` | Idempotency ledger for coupon payments |
| `equity_snapshots` | Daily marked-to-market valuations, per portfolio |
| `sync_state` | Vault config, ETags, shard hashes, UI settings |

### Design decisions worth calling out

- **Replay over mutation** — identical state on any device, no conflict
  resolution, no merge UI.
- **Zero plugins** — everything is Dart or `dart:ffi`, so Developer Mode is never
  required and the token goes straight to DPAPI.
- **Shard per device per month** — removes write contention and gives rotation
  for free.
- **UTC-stable dates** — `DateTime.parse('2030-01-15')` is *local* and shifts by
  a day; every schedule goes through `parseDateUtc`.
- **Coalesced ticks** — `QuoteBatcher` guarantees at most one UI update, one
  cache write and one order-evaluation pass per frame (60/120 Hz).
- **Bulk seeding** — prepared statements in one transaction: 12k instruments in
  ~0.2 s instead of ~15 s.

---

## Testing

```bash
flutter analyze
flutter test
```

Covers the accounting and matching engine (WAC, fees, slippage, lot precision,
resting/stop orders, fund NAV settlement, bond accrual and coupon idempotency),
portfolio isolation and cash withdrawals, portfolio analytics, sync (two-device
convergence against a fake gist, ETag/304, rate-limit translation), streaming
(coalescing with `fake_async`, Binance parsing) and the providers (mocked HTTP).

Optional live checks, excluded from normal runs:

```bash
TB_GIST_TOKEN=... flutter test test/sync_smoke.dart          # real gist round-trip (self-cleaning)
TB_LIVE=1         flutter test test/live_stream_smoke.dart   # real Binance WebSocket
TB_SEED=1         flutter test test/catalog_seed_smoke.dart  # catalog seed timing
RENDER_SCREENSHOTS=1 RENDER_OUT=shot.png flutter test test/render_screenshots.dart
```

## Building releases

```bash
flutter build windows --release        # build/windows/x64/runner/Release/
flutter build apk --release            # universal APK
flutter build appbundle --release --obfuscate --split-debug-info=build/app/outputs/symbols
```

The Windows output is self-contained (`TureisBanking.exe` + `flutter_windows.dll`
+ `data/` + `sqlite3.dll`) — zip it for a portable build. R8 shrinks the Android
Java/Kotlin side and the Dart snapshot is obfuscated.

---

## Data & caveats

- Listings derive from the public **NASDAQ Trader symbol directory** plus a
  curated international set; Yahoo symbols encode the venue suffix (`.DE`, `.L`,
  `.T`, `.HK`, `.NS`, …).
- Market data comes from each provider's public endpoints and is subject to their
  terms.
- **London (`.L`) prices arrive in pence, not pounds.** Indices are tradable as
  synthetic instruments with no contract specification.
- **Not implemented:** resting-order sync across devices (needs a decision on
  cross-device cancel and partial fills), keyed data providers, and a licensed
  global dataset beyond the ~12,100 bundled instruments.

## Licence

Personal project, provided as-is for experimentation. Market data belongs to the
respective providers.
