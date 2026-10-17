# High-Performance Multi-Asset Paper Trading App: Master Roadmap & Architecture

**Target Platforms:** Windows (Native Desktop) & Android (Mobile)  
**Core Philosophy:** Sub-millisecond local-first responsiveness, Swiss financial typography, zero "AI vibe-code" visual bloat, multi-asset support (Stocks, ETFs, Crypto, Mutual Funds, Bonds/Obligations, Indices), and $0 always-on cross-device synchronization.

---

## Build status

**All seven phases are implemented and shipping in this repository.** The
sections below are the original plan; this table records what actually landed
and where the build deviated from it.

This began as a weekend project: a synced, open alternative to apps like
*BestBrokers* on the Play Store, built to experiment with the features I wanted
most — the same portfolio on desktop and mobile, dense terminal-style tables,
real European and Asian listings, limit/stop orders, and accounting that is
actually correct.

Additions beyond the original plan: **multiple named portfolios** (each with its
own ledger slice, cash, positions and snapshots, all synced together), **cash
withdrawals and "clear all cash"**, **dark/light themes**, and daily
marked-to-market **equity snapshots** with a risk-free rate for Sharpe.

| Phase | Planned | As built |
| :--- | :--- | :--- |
| **1** | Flutter/Tauri, SQLite + WAL, design tokens | ✅ Flutter 3.47, `package:sqlite3` 3.x (bundled via build hooks, no `sqlite3_flutter_libs`), Inter + JetBrains Mono, **zero plugins** |
| **2** | Finnhub/Alpaca/Polygon, Binance, Yahoo, FRED, ECB, 50k FTS5 index | ✅ **Keyless-first**: Yahoo (stocks/ETFs/funds/indices), Binance REST **and WebSocket**, FRED, ECB. **~12,100 instruments** seeded in ~0.2 s (full NASDAQ Trader directory + curated EU/Asia/Americas + 26 indices). Keyed providers remain drop-in. |
| **3** | Accounts, ledger, positions cache, pending orders, asset-specific rules | ✅ Schema v3 tables, WAC replay, market/limit/stop, fractional equity lots, crypto 1e-8 + 0.10% fee, fund `QUEUED_NAV`, bond clean→dirty settlement + idempotent coupons |
| **4** | HLC stamping, Turso/Cloudflare/Gist, status pill | ✅ **Gist-only by design.** HLC + UUIDv7, per-device monthly NDJSON shards, ETag conditional GET, shard-hash checkpoints, rate-limit auto-retry, DPAPI-encrypted token |
| **5** | Summary header, holdings table, analytics drawer | ✅ Plus **sell-all / partial-sell / buy-more quick actions**, **multiple named portfolios**, **cash withdrawals**, daily marked-to-market `equity_snapshots`, risk-free rate for Sharpe, **dark/light themes**, custom funding |
| **6** | Categorised search, split-pane detail sheet, order ticket | ✅ Split pane at ≥900 px, candlestick **and line** chart (click to toggle), dashed live-price line, per-window % change, `1W` hourly bars, expense ratios, computed YTM + modified duration, units⇄cash sizing |
| **7** | Frame throttling, `.exe`/`.msix`, R8 `.apk`/`.aab` | ✅ `QuoteBatcher` coalesces ticks to one flush per frame (60/120 Hz), live Binance stream with reconnect, portable Windows release, release APK (R8) + obfuscated AAB. **MSIX skipped** (needs a signing certificate). |

**Deferred on purpose:** syncing resting orders (needs a cross-device cancel /
partial-fill decision), keyed data providers (no keys supplied), and a licensed
50k+ dataset. See the README's *Limitations* section.

---

## 1. Visual & Interaction Design System (Anti-"Vibe-Code" Specification)

To avoid the generic "AI-generated template" look, the UI adheres strictly to institutional trading terminal ergonomics:

1. **Zero Decorative Bloat:** No purple/blue neon gradients, no glassmorphism (`backdrop-filter: blur`), no glowing background blobs, no oversized $24\text{ px}$ rounded cards, and no unlabelled sparklines.
2. **Swiss Financial Typography:**
   - **UI & Labels:** `Inter`, `Geist`, or `IBM Plex Sans`.
   - **Prices, Tickers & Quantities:** `JetBrains Mono` or `IBM Plex Mono` with strict tabular numerals (`font-variant-numeric: tabular-nums`) so digits align vertically and never jitter horizontally when live prices tick.
3. **High-Density Hairline Grid:**
   - **Dark Theme Surface:** Matte carbon (`#0D0E11`) primary background, `#13151A` elevated panel, and $1\text{ px}$ solid hairline borders (`#22252A`) instead of drop shadows.
   - **Light Theme Surface:** Crisp paper (`#F7F7F5`) primary background with `#E2E4E9` hairline dividers.
   - **Semantic Accents Only:** Muted Emerald (`#10B981`) strictly for positive P&L/bids, Muted Crimson (`#EF4444`) strictly for negative P&L/asks, and neutral slate for all structural chrome.
4. **Two-Tab Navigation Architecture:**
   - **Tab 1: Portfolio, Holdings & P&L Analytics** (Account overview, asset table, equity curve, risk metrics).
   - **Tab 2: Multi-Asset Discovery & Execution** (Instant local search across Stocks, Crypto, ETFs, Funds, and Bonds + rapid order ticket).
   - **Keyboard-First on Windows:** `Ctrl+1` (Tab 1), `Ctrl+2` (Tab 2), `/` (focus search immediately), `Enter` (open order ticket), `Esc` (dismiss modal).
   - **Thumb-First on Android:** Persistent bottom two-segment bar with zero transition animations ($0\text{ ms}$ tab switch).
5. **Two Appearances, One Layout:** Matte carbon (dark) and crisp paper (light) are both shipping. Surface and text tokens are palette-driven (`AppPalette` in `lib/design/tokens.dart`) while semantic accents stay constant, so switching appearance never changes geometry or meaning.

---

## 2. Free & Always-Available Sync Architecture via GitHub Gists (Windows $\leftrightarrow$ Android)

Most free cloud databases (such as the free tier of Supabase) pause after $7$ days of inactivity, and free container hosts (like Render) spin down and suffer $50\text{ s}$ cold starts. To achieve **100% free, instant, and always-available sync** without servers going to sleep, this build uses an **Append-Only Event Ledger** whose transport is a **single user-owned GitHub Gist**.

GitHub Gists are the ideal zero-cost sync vault for this app: they require no backend deployment, never hibernate or cold-start, retain **full git revision history** for free, and are reachable from both Windows and Android over plain HTTPS using one stored token.

### 2.1 The Golden Rule of Portfolio Sync: Sync Trades, Not Balances
Never sync mutable portfolio balances or live prices across devices. Instead, treat your SQLite database as an **immutable double-entry ledger** of events (`DEPOSIT_CASH`, `EXECUTE_BUY`, `EXECUTE_SELL`, `COUPON_PAYOUT`).
- Every event is assigned a deterministic **UUIDv7** (time-ordered unique ID) and a **Hybrid Logical Clock (HLC)** timestamp.
- When Windows and Android sync, they simply exchange missing rows from the `ledger_events` table.
- Because the ledger is append-only, **merge conflicts are mathematically impossible**. Both devices sort the ledger by timestamp and compute the exact same cash balance, Weighted Average Cost, and P&L locally in under $2\text{ ms}$.

### 2.2 GitHub Gist as the Sync Vault

| Property | How GitHub Gists Satisfy It |
| :--- | :--- |
| **Always available** | Hosted on GitHub's infrastructure; no cold starts and no $7$-day inactivity pause. |
| **$0$ cost** | Free for any GitHub account, on both public and secret gists. |
| **No backend to build or maintain** | The "server" is the Gist REST API (`api.github.com`). |
| **Versioned & recoverable** | Every write creates a git revision; `GET /gists/{id}/commits` exposes full history for rollback. |
| **Authenticated & private-ish** | A **secret** gist is unlisted and reachable only via its ID; it is not shown in search or on the profile. |
| **Deterministic ordering** | Combined with UUIDv7 + HLC stamping, the ledger stays conflict-free regardless of clock skew. |

**One secret gist per user** acts as the sync vault (created once on first run). Both devices point at the same gist ID. Gists are **not** a real-time push channel, so the app polls; this is acceptable because the event payloads are tiny and the UI is local-first.

### 2.3 Gist File Layout: One Shard Per Device

To guarantee that two devices can never clobber each other's writes, the vault gist holds **one append-only shard file per device** plus a small metadata file. GitHub's `PATCH /gists/{id}` updates only the files named in the request body, so a device only ever rewrites **its own** shard.

| File in the gist | Writer | Contents |
| :--- | :--- | :--- |
| `ledger.windows_desktop.ndjson` | Windows only | One JSON `ledger_events` row per line, newest appended last. |
| `ledger.android_mobile.ndjson` | Android only | Same schema, written only by the phone. |
| `meta.json` | Any (write-rarely) | `schema_version`, registered `device_id`s, shard/retention policy, optional encryption `kdf` params. |

- **NDJSON** (newline-delimited JSON) makes appends trivial: a device fetches its shard, appends its new lines, and re-uploads the file.
- Each device merges the **union** of all shards, ordered by `hlc_timestamp`, and replays it through the same deterministic engine (§5.2), so both platforms converge on identical balances.
- A device treats every shard except its own as **read-only input**.

### 2.4 Sync Lifecycle Flow
1. **App Launch (Cold Start $< 400\text{ ms}$):** App immediately renders Tab 1 from the local on-disk SQLite database (works $100\%$ offline). **No network on the render path.**
2. **Background Pull:** In a background thread, the app issues `GET /gists/{id}` with the last stored `ETag` in an `If-None-Match` header. A `304 Not Modified` (unchanged) costs **$0$ rate-limit budget** and touches nothing.
3. **Merge:** On a changed response, the device reads missing rows (`hlc_timestamp > :last_local_hlc`) from every shard, inserts them locally, and marks pulled rows `synced = 1`.
4. **Instant Push on Trade:** A trade writes to local SQLite immediately ($< 1\text{ ms}$), then an async worker appends the single ~$250$-byte JSON event to **this device's** shard and `PATCH`es the gist. Writes are batched/flushed within a ~$2\text{ s}$ debounce to cap request count.
5. **Peer update:** The other device picks up the change on its next poll (default ~$15\text{ s}$ foreground) or on app-focus, then recomputes Tab 1 locally.

### 2.5 Rate Limits, Size Limits & Guardrails

Gists are generous but not infinite; the architecture is designed to stay far inside every ceiling.

- **Rate limit:** $5{,}000$ authenticated REST requests/hour per user (shared across both devices, since their tokens belong to the same account). Conditional `GET`s that return `304` **do not** count. Worst case with a $15\text{ s}$ poll on one device ≈ $240$ requests/hour — under $5\%$ of budget. Pushes are one `PATCH` per debounced flush.
- **File size:** The API returns up to $1\text{ MB}$ per file and sets `truncated: true` beyond that; `raw_url` serves up to $10\text{ MB}$; larger content requires `git clone`. At ~$250$ B/event this is ~$4{,}000$ events per $1\text{ MB}$.
- **File count:** `GET /gists/{id}` lists at most $300$ files before truncating. Shard rotation keeps us at a handful.
- **Shard rotation:** On the first trading day of each month, the app starts a fresh shard (e.g. `ledger.windows_desktop.2026-11.ndjson`). Sealed shards are read once, cached locally, and never rewritten, so the active file never grows unbounded.
- **Checkpoints:** A periodic `checkpoint.<yyyy-mm>.json` (aggregated cash/holdings state + HLC high-water mark) lets a cold device skip replaying ancient shards. The raw ledger stays the source of truth and can always regenerate any checkpoint.
- **Backoff:** On `403`/`429`, honor `Retry-After` and `x-ratelimit-reset` and apply exponential backoff; never busy-retry.
- **Optional compression:** If a shard approaches $1\text{ MB}$, store it gzip-then-base64 (at the cost of human readability).
- **Escape hatch:** Because a gist is a real git repo, the entire ledger can be cloned via `git_pull_url` for manual recovery or migration.

### 2.6 Authentication, Privacy & Security

- **Token:** A **fine-grained PAT** with *Gists: Read and write* is preferred; a classic PAT restricted to only the `gist` scope also works. In this build the token is encrypted at rest with **Windows DPAPI** (`CryptProtectData`, user-scoped) through `dart:ffi` before it is written to SQLite — no plugin, and only the same Windows user can decrypt it. On Android the equivalent would be the Keystore.
- **Bootstrap:** Device A creates the secret gist and stores its ID; Device B is linked by entering the same **gist ID + PAT** (no OAuth flow, no server).
- **Privacy posture:** A secret gist is *unlisted*, not *encrypted* — GitHub (and anyone holding the ID plus a valid token) can read it. For stronger privacy, shard files can hold **AES-256-GCM ciphertext** with a key derived from a user passphrase (Argon2id). Trade-off: encrypted shards are not human-readable and cannot be diffed in the gist UI.

### 2.7 Failure Modes & Recovery

| Failure | Behavior |
| :--- | :--- |
| Offline / airplane mode | App fully functional on the local ledger; rows queue as `synced = 0`. |
| Token revoked / expired | Header shows `LOCAL OFFLINE • QUEUED (n)`; sync pauses until re-auth; **no data loss**. |
| Rate limited | Backoff until `x-ratelimit-reset`; queued events flush afterward. |
| Shard approaches $1\text{ MB}$ | Rotate to a new monthly shard; consider enabling compression and checkpoints. |
| Accidental bad write | Recover from gist revision history (`/gists/{id}/commits`) or a local backup export. |

### 2.8 Alternatives Considered (Parked, Not Used)

For the record, so the pivot is explicit: **Turso embedded replicas** and a **Cloudflare D1 worker** were the earlier candidates. Both are technically excellent but add a second vendor dependency and (for D1) a small always-on service to own. Since the append-only ledger is tiny, human-inspectable, and needs no query engine in the cloud, the **user-owned Gist vault** wins on simplicity and cost. A **Google Drive `appDataFolder`** snapshot remains a possible secondary backup, but is out of scope for the primary sync path.

---

## 3. Step-by-Step Implementation Roadmap

### Phase 1: Core Engine & Local Database Setup (Weeks 1–2)
- **Framework Selection:** Flutter (Dart) compiling ahead-of-time (AOT) to native ARM64 (Android) and native Win32/C++ (Windows), or Tauri v2 (Rust + SolidJS).
- **Local Storage:** Configure SQLite with `Drift` (Flutter) or `rusqlite`/`libSQL` (Rust). Enable Write-Ahead Logging (`PRAGMA journal_mode=WAL;`) for concurrent read/write speed.
- **Design Token Setup:** Lock in typography (`Inter` + `JetBrains Mono`), tabular numerals, $1\text{ px}$ border tokens, and keyboard shortcut listeners.

### Phase 2: Multi-Asset Market Data Aggregation (Weeks 3–4)
- **Stocks & ETFs:** Connect Finnhub, Alpaca Market Data, or Polygon.io (WebSockets for live trades, REST for historical candles).
- **Crypto:** Connect Binance or Coinbase public WebSocket streams (zero API key required for real-time order book/ticker streams).
- **Mutual Funds & Index Funds:** Pull End-of-Day (EOD) Net Asset Value (NAV) and expense ratios via Yahoo Finance / Twelve Data.
- **Bonds & Obligations (Sovereign & Corporate):**
  - Pull Treasury/Sovereign yield curves via FRED API and ECB Data Portal.
  - Store bond reference metadata locally: ISIN/CUSIP, Coupon Rate ($c$), Maturity Date, Par Value ($F_{\text{par}}$), Payment Frequency ($m$), and Day Count Convention ($30/360$ or $\text{Actual}/\text{Actual}$).
- **Sub-2ms Local Search Index:** Pre-bundle a compressed SQLite FTS5 (Full-Text Search) virtual table of $50,000+$ global tickers, names, and ISINs so searching works instantaneously without waiting on network requests.

### Phase 3: Double-Entry Paper Trading & Matching Engine (Weeks 5–6)
- **Ledger Schema:** Build `accounts`, `ledger_events`, `positions_cache`, and `pending_orders` tables.
- **Asset-Specific Execution Rules:**
  - *Equities/ETFs:* Market, Limit, and Stop orders; fractional share support; simulated bid-ask spread slippage (e.g., $\pm 0.02\%$ when Level 1 quotes are absent).
  - *Crypto:* $24/7$ execution, precision up to $10^{-8}$ units, maker/taker fee simulation ($0.10\%$).
  - *Funds:* Orders placed intra-day enter `QUEUED_NAV` state and settle automatically at the next published EOD NAV price.
  - *Bonds/Obligations:* Quote in **Clean Price** ($\%$ of par), settle in **Dirty Price** (Clean Price $+$ Accrued Interest). Automatically credit virtual coupon payments into cash on coupon dates.

### Phase 4: Cross-Device Sync Integration via GitHub Gists (Week 7)
- Implement **Hybrid Logical Clock (HLC)** event stamping on every trade and cash adjustment, plus deterministic **UUIDv7** event IDs.
- **Auth & vault setup:** store a fine-grained PAT (*Gists: Read and write*) in the OS credential store; create or link the single secret sync gist (per-device NDJSON shards + `meta.json`).
- **Push path:** a debounced async worker appends new events to this device's shard and `PATCH`es the gist, flipping rows to `synced = 1` on success.
- **Pull path:** conditional `GET /gists/{id}` (ETag / `If-None-Match`), merge missing rows across all shards by `hlc_timestamp`, then replay through the deterministic engine.
- **Guardrails:** `Retry-After` / `x-ratelimit-reset` backoff, monthly shard rotation, optional checkpoints, and a manual "Sync now" action.
- Add a subtle status indicator in the header: `SYNCED • gist • 12ms` (green dot), `SYNCING…` (slate dot), or `LOCAL OFFLINE • QUEUED (2)` (amber dot).

### Phase 5: Tab 1 — Account Holdings, Overview & P&L Stats (Weeks 8–9)
- **Account Summary Header:** Total Net Liquidation Value, Day P&L ($\$$ and $\%$), Total All-Time P&L ($\$$ and $\%$), Available Buying Power, and Accrued Bond Interest Receivable.
- **High-Density Holdings Table:** Columns for Symbol/ISIN, Asset Class badge, Quantity, Weighted Average Cost, Live Price, Market Value, Unrealised P&L ($\$$ and $\%$), and Portfolio Weight ($\%$).
- **Analytics Drawer:** High-frame-rate HTML5/Skia canvas equity curve ($1\text{D}$, $1\text{W}$, $1\text{M}$, $1\text{Y}$, $\text{ALL}$), Realised P&L, Win/Loss Ratio, Maximum Drawdown ($\text{MDD}$), Sharpe Ratio ($S_p$), and Asset Allocation bar.

### Phase 6: Tab 2 — Unified Multi-Asset Search & Order Ticket (Weeks 10–11)
- **Instant Categorised Search:** Single input querying SQLite FTS5 by Ticker (`AAPL`), Pair (`BTC-USD`), Issuer (`Vanguard`), or ISIN (`US912810TW80`).
- **Category Filter Pills:** `[All]` `[Stocks]` `[ETFs]` `[Funds]` `[Crypto]` `[Bonds]`.
- **Detail & Fast Execution Sheet:** Split-pane on Windows, bottom sheet on Android. Shows OHLCV/Yield chart, asset-specific metrics (Expense Ratio for ETFs/Funds; Coupon, Maturity, YTM, and Modified Duration for Bonds), and a one-click order ticket (Buy/Sell, Market/Limit, Units vs. Cash Amount toggle).

### Phase 7: Performance Profiling & Native Packaging (Week 12)
- **UI Frame Throttling:** Buffer high-frequency WebSocket ticks into $16.6\text{ ms}$ ($60\text{ Hz}$) or $8.3\text{ ms}$ ($120\text{ Hz}$) UI batch updates so fast crypto streams never block the main thread.
- **Packaging:** Build standalone portable `.exe` / `.msix` for Windows and R8-minified `.apk` / `.aab` for Android.

---

## 4. Mathematical Background & Financial Theory

To ensure institutional-grade accuracy across **Tab 1 (Holdings & P&L)** and **Tab 2 (Multi-Asset Pricing)**, the calculation engine implements the following quantitative models.

### 4.1 Position Accounting: Weighted Average Cost (WAC) & P&L

The portfolio engine uses the **Weighted Average Cost (WAC)** model. Unlike First-In, First-Out (FIFO), WAC treats all units of an identical instrument as fungible, recalculating the cost basis only when a position is increased and locking in realised gains or losses when a position is reduced.

#### Formulas and Variables
When purchasing additional units of an asset, the updated Weighted Average Cost ($C_{\text{avg}, t}$) is:

$$C_{\text{avg}, t} = \frac{(Q_{t-1} \cdot C_{\text{avg}, t-1}) + (q_{\text{buy}} \cdot P_{\text{buy}} + F_{\text{buy}})}{Q_{t-1} + q_{\text{buy}}}$$

For any open position, the **Unrealised Profit and Loss** ($\text{PnL}_{\text{unrealised}}$) and **Unrealised Return Percentage** ($R_{\text{unrealised}}$) are:

$$\text{PnL}_{\text{unrealised}} = Q_t \cdot (P_{\text{mkt}} - C_{\text{avg}, t})$$

$$R_{\text{unrealised}} = \left( \frac{P_{\text{mkt}} - C_{\text{avg}, t}}{C_{\text{avg}, t}} \right) \times 100$$

When selling $q_{\text{sell}}$ units, the average cost per remaining unit stays constant, and the **Realised Profit and Loss** ($\text{PnL}_{\text{realised}}$) is:

$$\text{PnL}_{\text{realised}} = q_{\text{sell}} \cdot (P_{\text{sell}} - C_{\text{avg}, t}) - F_{\text{sell}}$$

- $Q_{t-1}$: Existing quantity held prior to the trade.
- $Q_t$: Current total quantity held after the trade.
- $C_{\text{avg}, t-1}$ and $C_{\text{avg}, t}$: Weighted average cost per unit before and after the trade.
- $q_{\text{buy}}$ and $q_{\text{sell}}$: Quantity of units bought or sold in the transaction.
- $P_{\text{buy}}$ and $P_{\text{sell}}$: Execution price per unit for the buy or sell order.
- $P_{\text{mkt}}$: Current live market price per unit.
- $F_{\text{buy}}$ and $F_{\text{sell}}$: Transaction fees or simulated commissions.

---

### 4.2 Portfolio Performance & Risk-Adjusted Return Theory

Under Modern Portfolio Theory (MPT), raw return figures must be paired with volatility and drawdown metrics in Tab 1.

#### Formulas and Variables
The **Portfolio Weight** ($w_i$) of asset $i$ across $N$ holdings plus cash ($V_{\text{cash}}$) is:

$$w_i = \frac{Q_i \cdot P_{i, \text{mkt}}}{V_{\text{cash}} + \sum_{j=1}^{N} (Q_j \cdot P_{j, \text{mkt}})}$$

The annualised **Sharpe Ratio** ($S_p$) measures excess return per unit of volatility:

$$S_p = \frac{\bar{R}_p - R_f}{\sigma_p} \cdot \sqrt{K}$$

The **Maximum Drawdown** ($\text{MDD}$) measures the worst peak-to-trough decline in portfolio equity ($E_t$) over a time window $[0, T]$:

$$\text{MDD} = \min_{t \in [0, T]} \left( \frac{E_t - \max_{\tau \in [0, t]} E_\tau}{\max_{\tau \in [0, t]} E_\tau} \right)$$

- $\bar{R}_p$: Mean periodic portfolio return (e.g., daily return).
- $R_f$: Periodic risk-free rate (proxied by short-term sovereign T-bill yields).
- $\sigma_p$: Sample standard deviation of periodic portfolio returns.
- $K$: Annualisation factor ($K = 252$ for equity trading days, $K = 365$ for $24/7$ crypto portfolios).
- $E_t$: Total portfolio equity at time $t$.
- $\max_{\tau \in [0, t]} E_\tau$: The High-Water Mark (highest historical equity peak achieved up to time $t$).

---

### 4.3 Fixed Income Theory: Bond Pricing, Dirty Price, and Duration

While trading screens quote a bond's **Clean Price** to strip out daily interest accumulation, actual trade settlement calculates the **Dirty Price** (Invoice Price) using present value discounting and accrued interest theory.

#### Formulas and Variables
The **Dirty Price** ($P_{\text{dirty}}$) and **Clean Price** ($P_{\text{clean}}$) of a fixed-rate bond are related by Accrued Interest ($\text{AI}$):

$$P_{\text{dirty}} = \sum_{k=1}^{M} \frac{C / m}{\left(1 + \frac{y}{m}\right)^{k - v}} + \frac{F_{\text{par}}}{\left(1 + \frac{y}{m}\right)^{M - v}}$$

$$P_{\text{dirty}} = P_{\text{clean}} + \text{AI}$$

$$\text{AI} = \left( \frac{C}{m} \right) \cdot \left( \frac{d_{\text{elapsed}}}{d_{\text{period}}} \right)$$

To measure sensitivity to interest rate shifts, **Modified Duration** ($D_{\text{mod}}$) estimates the percentage price change for a given shift in yield ($\Delta y$):

$$\frac{\Delta P_{\text{dirty}}}{P_{\text{dirty}}} \approx -D_{\text{mod}} \cdot \Delta y$$

- $F_{\text{par}}$: Par (face) value of the obligation (typically $100$ or $1,000$).
- $C$: Annual coupon payment ($C = c \cdot F_{\text{par}}$, where $c$ is the annual coupon rate).
- $m$: Coupon payment frequency per year ($m = 1$ annual, $m = 2$ semi-annual).
- $y$: Yield to Maturity (YTM), expressed as an annualised decimal.
- $M$: Total number of remaining coupon periods until maturity.
- $\text{AI}$: Accrued Interest earned by the seller since the last coupon date.
- $d_{\text{elapsed}}$: Days elapsed since the last coupon payment.
- $d_{\text{period}}$: Total days in the current coupon period ($v = d_{\text{elapsed}} / d_{\text{period}}$).
- $D_{\text{mod}}$: Modified duration in years.

---

## 5. Reference Implementation: SQLite Sync Schema & Calculation Engine

### 5.1 Conflict-Free Append-Only SQLite Schema (`schema.sql`)

```sql
-- Immutable event log that syncs effortlessly between Windows and Android
CREATE TABLE IF NOT EXISTS ledger_events (
    event_id TEXT PRIMARY KEY,          -- UUIDv7 (time-sortable unique ID)
    hlc_timestamp TEXT NOT NULL,        -- Hybrid Logical Clock timestamp for deterministic ordering
    device_id TEXT NOT NULL,            -- 'windows_desktop' or 'android_mobile'
    event_type TEXT NOT NULL,           -- 'CASH_DEPOSIT', 'BUY', 'SELL', 'BOND_COUPON'
    symbol TEXT,                        -- e.g., 'AAPL', 'BTC-USD', 'DE0001102341'
    asset_class TEXT,                   -- 'STOCK', 'ETF', 'FUND', 'CRYPTO', 'BOND'
    quantity REAL DEFAULT 0.0,
    execution_price REAL DEFAULT 0.0,   -- Clean price for bonds, unit price for others
    accrued_interest REAL DEFAULT 0.0,  -- Used for bond settlement
    fee REAL DEFAULT 0.0,
    currency TEXT DEFAULT 'USD',
    synced INTEGER DEFAULT 0            -- 0 = pending push to gist, 1 = confirmed in the gist shard
);

CREATE INDEX IF NOT EXISTS idx_ledger_hlc ON ledger_events(hlc_timestamp);
CREATE INDEX IF NOT EXISTS idx_ledger_synced ON ledger_events(synced);

-- Fast local FTS5 search index for Tab 2 (<2ms search queries)
CREATE VIRTUAL TABLE IF NOT EXISTS instrument_search USING fts5(
    symbol,
    name,
    isin,
    asset_class,
    exchange
);
```

### 5.2 Core Accounting, Bond Pricing & Deterministic Sync Replay (`engine.py`)

```python
def process_paper_trade(
    current_quantity,
    average_cost,
    realised_pnl,
    trade_side,
    trade_quantity,
    trade_price,
    fee
):
    """Updates a holding using Weighted Average Cost (WAC) when buying or selling."""
    if trade_side == 'BUY':
        old_total_cost = current_quantity * average_cost
        new_order_cost = (trade_quantity * trade_price) + fee
        new_quantity = current_quantity + trade_quantity
        new_average_cost = (old_total_cost + new_order_cost) / new_quantity

        return {
            'quantity': new_quantity,
            'average_cost': new_average_cost,
            'realised_pnl': realised_pnl
        }

    elif trade_side == 'SELL':
        if trade_quantity > current_quantity:
            raise ValueError('Cannot sell more units than currently held in portfolio')

        trade_profit = (trade_quantity * (trade_price - average_cost)) - fee
        new_quantity = current_quantity - trade_quantity
        new_realised_pnl = realised_pnl + trade_profit
        new_average_cost = average_cost if new_quantity > 0 else 0.0

        return {
            'quantity': new_quantity,
            'average_cost': new_average_cost,
            'realised_pnl': new_realised_pnl
        }


def get_holding_overview(quantity, average_cost, live_market_price):
    """Calculates live unrealised P&L and semantic colour tokens for Tab 1."""
    if quantity == 0 or average_cost == 0:
        return {
            'market_value': 0.0,
            'unrealised_pnl': 0.0,
            'unrealised_percent': 0.0,
            'display_colour': 'neutral_slate'
        }

    market_value = quantity * live_market_price
    unrealised_pnl = quantity * (live_market_price - average_cost)
    unrealised_percent = ((live_market_price - average_cost) / average_cost) * 100

    if unrealised_pnl > 0:
        display_colour = 'emerald_green'
    elif unrealised_pnl < 0:
        display_colour = 'crimson_red'
    else:
        display_colour = 'neutral_slate'

    return {
        'market_value': round(market_value, 2),
        'unrealised_pnl': round(unrealised_pnl, 2),
        'unrealised_percent': round(unrealised_percent, 2),
        'display_colour': display_colour
    }


def calculate_bond_dirty_price(
    clean_price,
    par_value,
    annual_coupon_rate,
    payments_per_year,
    days_elapsed,
    days_in_period
):
    """Calculates Accrued Interest and Dirty Settlement Price for bonds & obligations."""
    periodic_coupon = (par_value * annual_coupon_rate) / payments_per_year
    accrued_interest = periodic_coupon * (days_elapsed / days_in_period)
    dirty_price = clean_price + accrued_interest

    return {
        'clean_price': round(clean_price, 4),
        'accrued_interest': round(accrued_interest, 4),
        'dirty_price': round(dirty_price, 4)
    }


def replay_synced_ledger(events):
    """
    Rebuilds the exact same portfolio state on both Windows and Android
    from the merged append-only ledger_events list sorted by hlc_timestamp.
    """
    cash_balance = 0.0
    holdings = {}

    for ev in sorted(events, key=lambda x: x['hlc_timestamp']):
        etype = ev['event_type']
        sym = ev.get('symbol')
        qty = ev.get('quantity', 0.0)
        price = ev.get('execution_price', 0.0)
        accrued = ev.get('accrued_interest', 0.0)
        fee = ev.get('fee', 0.0)

        if etype == 'CASH_DEPOSIT':
            cash_balance += qty
        elif etype == 'BOND_COUPON':
            cash_balance += qty
        elif etype in ('BUY', 'SELL'):
            pos = holdings.get(sym, {'quantity': 0.0, 'average_cost': 0.0, 'realised_pnl': 0.0})
            effective_price = price + accrued  # Includes accrued interest for bonds

            if etype == 'BUY':
                cash_balance -= (qty * effective_price) + fee
            else:
                cash_balance += (qty * effective_price) - fee

            holdings[sym] = process_paper_trade(
                current_quantity=pos['quantity'],
                average_cost=pos['average_cost'],
                realised_pnl=pos['realised_pnl'],
                trade_side=etype,
                trade_quantity=qty,
                trade_price=effective_price,
                fee=fee
            )

    return {'cash_balance': round(cash_balance, 2), 'holdings': holdings}
```