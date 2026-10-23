import 'package:flutter/material.dart';

import 'analytics/equity_snapshot_repository.dart';
import 'core/ids.dart';
import 'data/app_database.dart';
import 'data/ledger_repository.dart';
import 'data/schema.dart';
import 'data/settings_store.dart';
import 'design/app_theme.dart';
import 'design/theme_controller.dart';
import 'features/home/home_shell.dart';
import 'market/instrument_repository.dart';
import 'market/market_data_service.dart';
import 'market/quote_repository.dart';
import 'sync/sync_config_store.dart';
import 'sync/sync_coordinator.dart';
import 'sync/sync_engine.dart';
import 'trading/account_repository.dart';
import 'trading/pending_order_repository.dart';
import 'trading/position_repository.dart';
import 'trading/trading_engine.dart';

/// Root widget. The database handle is injected so tests can supply an
/// in-memory instance.
class PaperTradingApp extends StatefulWidget {
  const PaperTradingApp({
    super.key,
    required this.database,
    required this.databasePath,
  });

  final AppDatabase database;
  final String databasePath;

  @override
  State<PaperTradingApp> createState() => _PaperTradingAppState();
}

class _PaperTradingAppState extends State<PaperTradingApp> {
  late final SettingsStore _settings;
  late final ThemeController _theme;
  late final InstrumentRepository _instruments;
  late final QuoteRepository _quotes;
  late final LedgerRepository _ledger;
  late final PositionRepository _positions;
  late final AccountRepository _accounts;
  late final EquitySnapshotRepository _snapshots;
  late final SyncCoordinator _sync;

  String _activeAccountId = AccountRepository.defaultAccountId;

  @override
  void initState() {
    super.initState();
    final database = widget.database;
    _settings = SettingsStore(database);
    _theme = ThemeController(_settings);
    _instruments = InstrumentRepository(database);
    _quotes = QuoteRepository(database);
    _ledger = LedgerRepository(database, deviceId: currentDeviceId());
    _positions = PositionRepository(database);
    _accounts = AccountRepository(database);
    _snapshots = EquitySnapshotRepository(database);
    _accounts.ensureDefault();
    _sync = SyncCoordinator(
      engine: SyncEngine(
        database: database,
        ledger: _ledger,
        config: SyncConfigStore(database),
        deviceId: _ledger.deviceId,
        schemaVersion: Schema.version,
        onMerged: () => _engine(_activeAccountId).rebuildCache(),
      ),
    );
    // Every local write schedules a debounced push.
    _ledger.onAppended = _sync.notifyLocalChange;
    _sync.start();
  }

  TradingEngine _engine(String accountId) => TradingEngine(
        database: widget.database,
        ledger: _ledger,
        orders: PendingOrderRepository(widget.database),
        positions: _positions,
        instruments: _instruments,
        accountId: accountId,
      );

  @override
  void dispose() {
    _sync.dispose();
    _theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = _accounts.get(_activeAccountId) ??
        _accounts.get(AccountRepository.defaultAccountId);
    final accountId = account?.accountId ?? AccountRepository.defaultAccountId;

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _theme,
      builder: (context, mode, _) => MaterialApp(
        // Re-keying on appearance forces every widget to re-read the palette.
        key: ValueKey<ThemeMode>(mode),
        title: 'TureisBanking',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        home: HomeShell(
          // Switching portfolio rebuilds the session (and its live stream).
          key: ValueKey<String>('shell-$accountId'),
          database: widget.database,
          databasePath: widget.databasePath,
          ledger: _ledger,
          instruments: _instruments,
          quotes: _quotes,
          marketData: MarketDataService(
            instruments: _instruments,
            quotes: _quotes,
          ),
          engine: _engine(accountId),
          sync: _sync,
          snapshots: _snapshots,
          settings: _settings,
          theme: _theme,
          accounts: _accounts,
          accountId: accountId,
          accountName: account?.name ?? 'Portfolio',
          onAccountChanged: (id) => setState(() => _activeAccountId = id),
        ),
      ),
    );
  }
}
