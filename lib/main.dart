import 'package:flutter/material.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/app_paths.dart';
import 'market/catalog_importer.dart';
import 'market/instrument_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final path = AppPaths.databasePath();
  final database = AppDatabase.open(path);

  // Seed the local instrument catalog on first launch (offline, bundled asset).
  // Network market data is fetched lazily afterwards.
  await CatalogImporter.seedIfEmpty(InstrumentRepository(database));

  runApp(PaperTradingApp(database: database, databasePath: path));
}
