import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paper_trading_app/data/app_database.dart';
import 'package:paper_trading_app/market/asset_class.dart';
import 'package:paper_trading_app/market/catalog_importer.dart';
import 'package:paper_trading_app/market/instrument_repository.dart';

/// Measures first-run seeding of the full bundled catalog.
///
///   TB_SEED=1 flutter test test/catalog_seed_smoke.dart
void main() {
  final enabled = Platform.environment['TB_SEED'] == '1';

  test(
    'seeds the full bundled catalog and searches at scale',
    skip: !enabled,
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();

      final dir = Directory.systemTemp.createTempSync('tb_seed_');
      final db = AppDatabase.open(
        '${dir.path}${Platform.pathSeparator}catalog.db',
      );
      addTearDown(() {
        db.close();
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final repository = InstrumentRepository(db);
      final watch = Stopwatch()..start();
      final seeded = await CatalogImporter.seedIfNeeded(repository);
      watch.stop();

      final bySymbol = repository.search('AAPL', limit: 3).map((i) => i.symbol);
      final byName = repository.search('siemens', limit: 3).map((i) => i.symbol);
      final byIndexWord =
          repository.search('500', limit: 3).map((i) => i.symbol);
      final crypto = repository
          .search('', assetClass: AssetClass.crypto, limit: 3)
          .map((i) => i.symbol);

      // ignore: avoid_print
      print(
        'seeded=$seeded rows=${repository.count()} '
        'in ${watch.elapsedMilliseconds}ms | '
        'AAPL=$bySymbol siemens=$byName 500=$byIndexWord crypto=$crypto',
      );

      expect(seeded, greaterThan(5000));
      expect(repository.count(), greaterThan(5000));
      expect(bySymbol, contains('AAPL'));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
