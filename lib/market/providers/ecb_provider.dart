import 'package:http/http.dart' as http;

import '../../core/dates.dart';
import '../asset_class.dart';
import '../models/candle.dart';
import '../models/quote.dart';
import 'market_data_provider.dart';

/// Euro-area sovereign yields from the ECB Data Portal (deferred from Phase 2).
///
/// Requires no API key. `providerSymbol` is a full SDMX series key, e.g.
/// `YC/B.U2.EUR.4F.G_N_A.SV_C_YM.SR_10Y` (10-year government benchmark yield).
class EcbProvider implements MarketDataProvider {
  EcbProvider({http.Client? client, this.baseUrl = _base})
      : _client = client ?? http.Client();

  static const String _base = 'https://data-api.ecb.europa.eu';

  final http.Client _client;
  final String baseUrl;

  @override
  String get id => 'ecb';

  @override
  Set<AssetClass> get supported => const {AssetClass.bond};

  @override
  Future<Quote> fetchQuote({
    required String symbol,
    required String providerSymbol,
    String currency = 'EUR',
  }) async {
    final series = await _series(providerSymbol, observations: 10);
    if (series.isEmpty) {
      throw MarketDataException(
        'ECB returned no observations for $providerSymbol',
        source: id,
      );
    }
    final latest = series.last;
    final previous = series.length > 1 ? series[series.length - 2] : null;

    return Quote.derive(
      symbol: symbol,
      price: latest.value,
      previousClose: previous?.value,
      currency: currency,
      asOf: latest.date.toUtc(),
      source: id,
    );
  }

  @override
  Future<List<Candle>> fetchCandles({
    required String providerSymbol,
    String interval = '1d',
    int limit = 90,
  }) async {
    final series = await _series(providerSymbol, observations: limit);
    // Yields have no intraday range: OHLC collapse to the close.
    return series
        .map((point) => Candle(
              time: point.date.toUtc(),
              open: point.value,
              high: point.value,
              low: point.value,
              close: point.value,
            ))
        .toList(growable: false);
  }

  Future<List<({DateTime date, double value})>> _series(
    String providerSymbol, {
    required int observations,
  }) async {
    final uri = Uri.parse('$baseUrl/service/data/$providerSymbol').replace(
      queryParameters: {
        'format': 'csvdata',
        'lastNObservations': '$observations',
      },
    );
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw MarketDataException(
        'ECB HTTP ${response.statusCode} for $providerSymbol',
        source: id,
      );
    }
    return parseCsv(response.body);
  }

  /// Parses the SDMX CSV payload by locating the `TIME_PERIOD` / `OBS_VALUE`
  /// columns rather than assuming fixed positions.
  static List<({DateTime date, double value})> parseCsv(String body) {
    final lines = body
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    if (lines.length < 2) return const [];

    final header = _splitCsvLine(lines.first);
    final dateIndex = header.indexOf('TIME_PERIOD');
    final valueIndex = header.indexOf('OBS_VALUE');
    if (dateIndex == -1 || valueIndex == -1) return const [];

    final out = <({DateTime date, double value})>[];
    for (var i = 1; i < lines.length; i++) {
      final cells = _splitCsvLine(lines[i]);
      if (cells.length <= dateIndex || cells.length <= valueIndex) continue;
      final date = parseDateUtc(cells[dateIndex].trim());
      final value = double.tryParse(cells[valueIndex].trim());
      if (date == null || value == null) continue;
      out.add((date: date, value: value));
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  /// Minimal CSV splitter honouring double-quoted fields.
  static List<String> _splitCsvLine(String line) {
    final cells = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        quoted = !quoted;
      } else if (char == ',' && !quoted) {
        cells.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    cells.add(buffer.toString());
    return cells;
  }
}
