import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/app_paths.dart';
import 'data/ledger_repository.dart';
import 'design/tokens.dart';
import 'market/catalog_importer.dart';
import 'market/instrument_repository.dart';
import 'trading/account_repository.dart';
import 'trading/pending_order_repository.dart';
import 'trading/position_repository.dart';
import 'trading/trading_engine.dart';

/// Virtual cash placed in a brand-new paper account.
const double kOpeningBalance = 100000.0;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
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
  } catch (error, stack) {
    // Never fail to a black screen: show what went wrong instead.
    debugPrint('Startup failed: $error\n$stack');
    runApp(StartupFailureApp(error: error));
  }
}

/// Rendered when the app cannot initialise, so the failure is visible and
/// reportable rather than a blank window.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: AppColors.carbon,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TUREISBANKING FAILED TO START',
                    style: AppTypography.mono(
                      size: 13,
                      weight: FontWeight.w700,
                      color: AppColors.negative,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    '$error',
                    style: AppTypography.mono(
                      size: 12,
                      color: AppColors.textPrimaryDark,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'platform: ${Platform.operatingSystem} '
                    '${Platform.operatingSystemVersion}\n'
                    'data dir: ${_safeDataDir()}',
                    style: AppTypography.mono(
                      size: 11,
                      color: AppColors.textMutedDark,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _safeDataDir() {
    try {
      return AppPaths.dataDirectory().path;
    } catch (error) {
      return 'unavailable ($error)';
    }
  }
}
