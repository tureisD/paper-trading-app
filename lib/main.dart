import 'package:flutter/material.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/app_paths.dart';
import 'data/ledger_repository.dart';
import 'market/catalog_importer.dart';
import 'market/instrument_repository.dart';
import 'trading/account_repository.dart';
import 'trading/pending_order_repository.dart';import 'trading/position_repository.dart';
import 'trading/trading_engine.dart';

/// Virtual cash placed in a brand-new paper account.
const double kOpeningBalance = 100000.0;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final path = AppPaths.databasePath();
  final database = AppDatabase.open(path);

  // Seed the local instrument catalog on first launch (offline, bundled asset).
  final instruments = InstrumentRepository(database);
  await CatalogImporter.seedIfNeeded(instruments);

  // Default account + opening paper balance for every portfolio.
  final accounts = AccountRepository(database);
  accounts.ensureDefault();
  final ledger = LedgerRepository(database);
  for (final account in accounts.all()) {
    if (ledger.all(accountId: account.accountId).isEmpty) {
      ledger.append(
        ledger.deposit(
          amount: kOpeningBalance,
          accountId: account.accountId,
        ),
      );
    }
  }

  // Materialise the position cache from the ledger.
  TradingEngine(
    database: database,
    ledger: ledger,
    orders: PendingOrderRepository(database),
    positions: PositionRepository(database),
    instruments: instruments,
    accountId: AccountRepository.defaultAccountId,
  ).rebuildCache();

  runApp(PaperTradingApp(database: database, databasePath: path));
}
