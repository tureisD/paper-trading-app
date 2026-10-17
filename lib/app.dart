import 'package:flutter/material.dart';

import 'analytics/equity_snapshot_repository.dart';
import 'core/ids.dart';
import 'data/app_database.dart';
import 'data/ledger_repository.dart';
import 'data/schema.dart';
import 'design/app_theme.dart';
import 'features/home/home_shell.dart';
import 'market/instrument_repository.dart';
import 'market/market_data_service.dart';
import 'market/quote_repository.dart';
import 'sync/sync_config_store.dart';
import 'sync/sync_engine.dart';
import 'trading/pending_order_repository.dart';
import 'trading/position_repository.dart';
import 'trading/trading_engine.dart';

/// Root widget. The database handle is injected so tests can supply an
/// in-memory instance.
class PaperTradingApp extends StatelessWidget {
  const PaperTradingApp({
    super.key,
    required this.database,
    required this.databasePath,
  });

  final AppDatabase database;
  final String databasePath;

  @override
  Widget build(BuildContext context) {
    final instruments = InstrumentRepository(database);
    final quotes = QuoteRepository(database);
    final deviceId = currentDeviceId();
    final ledger = LedgerRepository(database, deviceId: deviceId);
    final positions = PositionRepository(database);
    final engine = TradingEngine(
      database: database,
      ledger: ledger,
      orders: PendingOrderRepository(database),
      positions: positions,
      instruments: instruments,
    );
    final syncEngine = SyncEngine(
      database: database,
      ledger: ledger,
      config: SyncConfigStore(database),
      deviceId: deviceId,
      schemaVersion: Schema.version,
      onMerged: engine.rebuildCache,
    );
    final snapshots = EquitySnapshotRepository(database);

    return MaterialApp(
      title: 'TureisBanking',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: HomeShell(
        database: database,
        databasePath: databasePath,
        ledger: ledger,
        instruments: instruments,
        quotes: quotes,
        marketData: MarketDataService(
          instruments: instruments,
          quotes: quotes,
        ),
        engine: engine,
        syncEngine: syncEngine,
        snapshots: snapshots,
      ),
    );
  }
}
