import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'instrument_repository.dart';
import 'models/instrument.dart';

/// Parsed contents of the seed catalog.
class CatalogPayload {
  const CatalogPayload(this.instruments, this.bondDetails);

  final List<Instrument> instruments;
  final Map<String, BondDetails> bondDetails;
}

/// Loads the bundled instrument catalog into the local database.
class CatalogImporter {
  const CatalogImporter._();

  static const String assetPath = 'assets/data/instruments.json';

  /// Seeds the catalog from the bundled asset when the table is empty.
  /// Returns the number of instruments written (0 if already seeded).
  static Future<int> seedIfEmpty(InstrumentRepository repository) async {
    if (repository.count() > 0) return 0;
    final raw = await rootBundle.loadString(assetPath);
    final payload = parse(raw);
    repository.upsertAll(
      payload.instruments,
      bondDetails: payload.bondDetails,
    );
    return payload.instruments.length;
  }

  /// Parses the catalog JSON (pure function, unit-testable without Flutter).
  static CatalogPayload parse(String raw) {
    final root = jsonDecode(raw) as Map<String, dynamic>;
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
    return CatalogPayload(instruments, bonds);
  }
}
