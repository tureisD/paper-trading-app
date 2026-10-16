import 'package:flutter/material.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/app_paths.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final path = AppPaths.databasePath();
  final database = AppDatabase.open(path);

  runApp(PaperTradingApp(database: database, databasePath: path));
}
