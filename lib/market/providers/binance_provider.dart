import 'dart:convert';

import 'package:http/http.dart' as http;

import '../asset_class.dart';
import '../models/candle.dart';
import '../models/quote.dart';
import 'market_data_provider.dart';

/// Live crypto prices and candles from Binance's public REST API.
///
/// Requires no API key. Uses `api.binance.com`, falling back to the
/// `data-api.binance.vision` mirror if the primary is unreachable.
class BinanceProvider implements MarketDataProvider {
  BinanceProvider({http.Client? client, this.baseUrl = _primary})
      : _client = client ?? http.Client();

  static const String _primary = 'https://api.binance.com';
  static const String _mirror = 'https://data-api.binance.vision';

  final http.Client _client;
  final String baseUrl;

  @override
  String get id => 'binance';

  @override
  Set<AssetClass> get supported => const {AssetClass.crypto};

  /// Maps a canonical pair (`BTC-USD`, `ETH-EUR`) to a Binance symbol.
  static String toProviderSymbol(String symbol) {
    final s = symbol.replaceAll('-', '').replaceAll('/', '').toUpperCase();
    if (s.endsWith('USDT')) return s;
    if (s.endsWith('USD')) return '${s.substring(0, s.length - 3)}USDT';
    return s;
  }

  @override
  Future<Quote> fetchQuote({
    required String symbol,
    required String providerSymbol,
    String currency = 'USD',
  }) async {
    final uri = Uri.parse('$baseUrl/api/v3/ticker/24hr')
        .replace(queryParameters: {'symbol': providerSymbol});
    final json = await _getJson(uri);

    final price = double.tryParse('${json['lastPrice']}');
    if (price == null) {
      throw MarketDataException(
        'Binance response missing lastPrice for $providerSymbol',
        source: id,
      );
    }
    return Quote.derive(
      symbol: symbol,
      price: price,
      previousClose: double.tryParse('${json['prevClosePrice']}'),
      change: double.tryParse('${json['priceChange']}'),
      changePercent: double.tryParse('${json['priceChangePercent']}'),
      currency: currency,
      asOf: DateTime.now().toUtc(),
      source: id,
    );
  }

  @override
  Future<List<Candle>> fetchCandles({
    required String providerSymbol,
    String interval = '1d',
    int limit = 90,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v3/klines').replace(queryParameters: {
      'symbol': providerSymbol,
      'interval': interval,
      'limit': '$limit',
    });
    final rows = await _getJsonList(uri);

    return rows.map((row) {
      final r = (row as List).cast<Object?>();
      return Candle(
        time: DateTime.fromMillisecondsSinceEpoch(r[0]! as int, isUtc: true),
        open: double.parse('${r[1]}'),
        high: double.parse('${r[2]}'),
        low: double.parse('${r[3]}'),
        close: double.parse('${r[4]}'),
        volume: double.tryParse('${r[5]}'),
      );
    }).toList(growable: false);
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _send(uri);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> _getJsonList(Uri uri) async {
    final response = await _send(uri);
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<http.Response> _send(Uri uri) async {
    var response = await _client.get(uri);
    if (response.statusCode != 200 && baseUrl == _primary) {
      final mirrored = uri.replace(
        scheme: Uri.parse(_mirror).scheme,
        host: Uri.parse(_mirror).host,
      );
      response = await _client.get(mirrored);
    }
    if (response.statusCode != 200) {
      throw MarketDataException(
        'Binance HTTP ${response.statusCode} for $uri',
        source: id,
      );
    }
    return response;
  }
}
