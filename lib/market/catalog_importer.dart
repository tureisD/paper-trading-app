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

  static const String assetPath = 'assets/data/instruments.json';

  /// Seeds or refreshes the catalog.
  ///
  /// Runs when the table is empty, or when the bundled catalog version is newer
  /// than the one already imported — so existing installs pick up new fields
  /// (expense ratios, new instruments) without wiping local state.
  static Future<int> seedIfNeeded(InstrumentRepository repository) async {
    final raw = await rootBundle.loadString(assetPath);
    final payload = parse(raw);
    final imported = repository.catalogVersion;

    if (repository.count() > 0 && imported == '${payload.version}') return 0;

    repository.upsertAll(
      payload.instruments,
      bondDetails: payload.bondDetails,
    );
    repository.catalogVersion = '${payload.version}';
    return payload.instruments.length;
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
