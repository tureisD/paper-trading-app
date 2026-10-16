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
| 2 | Multi-asset market data | ⬜ Not started |
| 3 | Double-entry trading engine | ⬜ Not started |
| 4 | GitHub Gist cross-device sync | ⬜ Not started |
| 5 | Tab 1 — Holdings & P&L | ⬜ Not started |
| 6 | Tab 2 — Search & order ticket | ⬜ Not started |
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
  core/            ids (UUIDv7), formatting helpers
  data/            SQLite database, versioned schema, ledger repository
  design/          design tokens + Material theme
  features/home/   application shell (two-tab frame)
```

## Notes & caveats

- **Developer Mode:** Flutter requires Windows Developer Mode to build with any
  native *plugin* (symlinks). This build intentionally uses **zero plugins**, so
  it compiles today. Enabling Developer Mode is required before Android work
  (and before re-introducing `path_provider` for Android data paths).
- `sqlite3_flutter_libs` is **not** used: `package:sqlite3` 3.x bundles SQLite
  via build hooks (the resulting `sqlite3.dll` ships next to the `.exe`).
- `path_provider` is intentionally omitted on Windows; data paths are resolved
  directly from the environment (`lib/data/app_paths.dart`).
