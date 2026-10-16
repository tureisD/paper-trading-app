import 'package:flutter/material.dart';

import 'data/app_database.dart';
import 'data/ledger_repository.dart';
import 'design/app_theme.dart';
import 'features/home/home_shell.dart';

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
    return MaterialApp(
      title: 'TureisBanking',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: HomeShell(
        database: database,
        ledger: LedgerRepository(database),
        databasePath: databasePath,
      ),
    );
  }
}
