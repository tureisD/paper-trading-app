import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'instrument_repository.dart';
import 'models/instrument.dart';

/// Parsed contents of the seed catalog.
class CatalogPayload {
  const CatalogPayload(this.version, this.instruments, this.bondDetails);

  final int version;
  final List<Instrument> instruments;
  final Map<String, BondDetails> bondDetails;
}

/// Loads the bundled instrument catalog into the local database.
class CatalogImporter {
  const CatalogImporter._();

  /// Curated catalog: crypto, funds, bonds, indices, key ETFs (with expense
  /// ratios) and a starter set of stocks.
  static const String assetPath = 'assets/data/instruments.json';

  /// Everything seeded on first run. Bulk lists come first so the curated file
  /// (which carries ISINs, exchange names and expense ratios) wins on conflicts.
  static const List<String> assetPaths = <String>[
    'assets/data/instruments_us.json',
    'assets/data/instruments_intl.json',
    assetPath,
  ];

  /// Seeds or refreshes the catalog.
  ///
  /// Runs when the table is empty, or when the bundled catalog version is newer
  /// than the one already imported — so existing installs pick up new fields
  /// (expense ratios, new instruments) without wiping local state.
  static Future<int> seedIfNeeded(InstrumentRepository repository) async {
    final payloads = <CatalogPayload>[];
    for (final path in assetPaths) {
      try {
        payloads.add(parse(await rootBundle.loadString(path)));
      } catch (_) {
        // A missing optional bulk file must not block seeding.
      }
    }
    if (payloads.isEmpty) return 0;

    final version = payloads
        .map((payload) => payload.version)
        .reduce((a, b) => a > b ? a : b);

    if (repository.count() > 0 && repository.catalogVersion == '$version') {
      return 0;
    }

    var imported = 0;
    final merged = <String, Instrument>{};
    final bonds = <String, BondDetails>{};
    for (final payload in payloads) {
      for (final instrument in payload.instruments) {
        merged[instrument.symbol] = instrument; // later files win
      }
      bonds.addAll(payload.bondDetails);
      imported += payload.instruments.length;
    }
    repository.bulkUpsert(merged.values, bondDetails: bonds);
    repository.catalogVersion = '$version';
    return imported;
  }

  /// Parses the catalog JSON (pure function, unit-testable without Flutter).
  static CatalogPayload parse(String raw) {
    final root = jsonDecode(raw) as Map<String, dynamic>;
    final version = (root['version'] as num?)?.toInt() ?? 1;
    final entries = (root['instruments'] as List?) ?? const [];
    final instruments = <Instrument>[];
    final bonds = <String, BondDetails>{};

    for (final entry in entries) {
      final json = (entry as Map).cast<String, dynamic>();
      instruments.add(Instrument.fromJson(json));
      final bond = json['bond'];
      if (bond is Map) {
        bonds[instruments.last.symbol] = BondDetails.fromJson(
          bond.cast<String, dynamic>(),
          symbol: instruments.last.symbol,
        );
      }
    }
    return CatalogPayload(version, instruments, bonds);
  }
}
