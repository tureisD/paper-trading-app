import 'package:http/http.dart' as http;

import '../asset_class.dart';
import '../models/candle.dart';
import '../models/quote.dart';
import 'market_data_provider.dart';

/// Sovereign yield / obligation series from the FRED CSV endpoint.
///
/// Requires no API key. `providerSymbol` is a FRED series id such as `DGS10`
/// (10-year Treasury), `DGS2` or `DTB3`.
class FredProvider implements MarketDataProvider {
  FredProvider({http.Client? client, this.baseUrl = _base})
      : _client = client ?? http.Client();

  static const String _base = 'https://fred.stlouisfed.org';

  final http.Client _client;
  final String baseUrl;

  @override
  String get id => 'fred';

  @override
  Set<AssetClass> get supported => const {AssetClass.bond};

  @override
  Future<Quote> fetchQuote({
    required String symbol,
    required String providerSymbol,
    String currency = 'USD',
  }) async {
    final series = await _series(providerSymbol, days: 30);
    if (series.isEmpty) {
      throw MarketDataException(
        'FRED returned no observations for $providerSymbol',
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
    final series = await _series(providerSymbol, days: limit * 2);
    final recent = series.length > limit
        ? series.sublist(series.length - limit)
        : series;
    // A yield series has no intraday range, so OHLC collapse to the close.
    return recent
        .map((p) => Candle(
              time: p.date.toUtc(),
              open: p.value,
              high: p.value,
              low: p.value,
              close: p.value,
            ))
        .toList(growable: false);
  }

  Future<List<({DateTime date, double value})>> _series(
    String providerSymbol, {
    required int days,
  }) async {
    final start = DateTime.now().toUtc().subtract(Duration(days: days));
    final uri = Uri.parse('$baseUrl/graph/fredgraph.csv').replace(
      queryParameters: {
        'id': providerSymbol,
        'cosd': _isoDate(start),
      },
    );
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw MarketDataException(
        'FRED HTTP ${response.statusCode} for $providerSymbol',
        source: id,
      );
    }
    return _parse(response.body);
  }

  /// Parses `observation_date,<SERIES>` rows, skipping missing (`.`) values.
  static List<({DateTime date, double value})> _parse(String body) {
    final out = <({DateTime date, double value})>[];
    final lines = body.split('\n');
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final parts = line.split(',');
      if (parts.length < 2) continue;
      final date = DateTime.tryParse(parts[0].trim());
      final value = double.tryParse(parts[1].trim());
      if (date == null || value == null) continue;
      out.add((date: date, value: value));
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  static String _isoDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }
}
