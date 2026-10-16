import 'dart:convert';

import 'package:http/http.dart' as http;

import '../asset_class.dart';
import '../models/candle.dart';
import '../models/quote.dart';
import 'market_data_provider.dart';

/// Quotes and candles for stocks, ETFs and mutual funds via the public Yahoo
/// Finance chart endpoint (no API key).
///
/// Mutual funds are served by the same endpoint using their fund symbol
/// (e.g. `VFIAX`), which yields the End-of-Day NAV.
class YahooFinanceProvider implements MarketDataProvider {
  YahooFinanceProvider({http.Client? client, this.baseUrl = _base})
      : _client = client ?? http.Client();

  static const String _base = 'https://query1.finance.yahoo.com';

  /// Yahoo rejects requests without a browser-like User-Agent.
  static const Map<String, String> _headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
    'Accept': 'application/json',
  };

  final http.Client _client;
  final String baseUrl;

  @override
  String get id => 'yahoo';

  @override
  Set<AssetClass> get supported => const {
        AssetClass.stock,
        AssetClass.etf,
        AssetClass.fund,
      };

  @override
  Future<Quote> fetchQuote({
    required String symbol,
    required String providerSymbol,
    String currency = 'USD',
  }) async {
    final result = await _chart(providerSymbol, range: '1d', interval: '1d');
    final meta = result['meta'] as Map<String, dynamic>? ?? const {};

    final price = _asDouble(meta['regularMarketPrice']);
    if (price == null) {
      throw MarketDataException(
        'Yahoo response missing regularMarketPrice for $providerSymbol',
        source: id,
      );
    }
    final previousClose = _asDouble(meta['chartPreviousClose']) ??
        _asDouble(meta['previousClose']);

    return Quote.derive(
      symbol: symbol,
      price: price,
      previousClose: previousClose,
      currency: (meta['currency'] as String?) ?? currency,
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
    final range = _rangeFor(interval, limit);
    final result = await _chart(providerSymbol, range: range, interval: interval);

    final timestamps = (result['timestamp'] as List?)?.cast<num>() ?? const [];
    final indicators = result['indicators'] as Map<String, dynamic>? ?? const {};
    final quoteList = (indicators['quote'] as List?) ?? const [];
    if (quoteList.isEmpty) return const [];
    final quote = quoteList.first as Map<String, dynamic>;

    final opens = (quote['open'] as List?) ?? const [];
    final highs = (quote['high'] as List?) ?? const [];
    final lows = (quote['low'] as List?) ?? const [];
    final closes = (quote['close'] as List?) ?? const [];
    final volumes = (quote['volume'] as List?) ?? const [];

    final candles = <Candle>[];
    for (var i = 0; i < timestamps.length; i++) {
      final close = _asDouble(_at(closes, i));
      if (close == null) continue; // Yahoo pads gaps with nulls.
      candles.add(
        Candle(
          time: DateTime.fromMillisecondsSinceEpoch(
            timestamps[i].toInt() * 1000,
            isUtc: true,
          ),
          open: _asDouble(_at(opens, i)) ?? close,
          high: _asDouble(_at(highs, i)) ?? close,
          low: _asDouble(_at(lows, i)) ?? close,
          close: close,
          volume: _asDouble(_at(volumes, i)),
        ),
      );
    }
    // Keep the most recent `limit` bars.
    if (candles.length > limit) {
      return candles.sublist(candles.length - limit);
    }
    return candles;
  }

  Map<String, dynamic> _firstResult(Map<String, dynamic> body) {
    final chart = body['chart'] as Map<String, dynamic>?;
    final results = (chart?['result'] as List?) ?? const [];
    if (results.isEmpty) {
      final error = chart?['error'];
      throw MarketDataException('Yahoo returned no data ($error)', source: id);
    }
    return results.first as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _chart(
    String providerSymbol, {
    required String range,
    required String interval,
  }) async {
    final uri = Uri.parse('$baseUrl/v8/finance/chart/$providerSymbol')
        .replace(queryParameters: {'range': range, 'interval': interval});
    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw MarketDataException(
        'Yahoo HTTP ${response.statusCode} for $providerSymbol',
        source: id,
      );
    }
    return _firstResult(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static String _rangeFor(String interval, int limit) {
    if (interval.endsWith('m')) {
      return interval == '1m' ? '5d' : '1mo';
    }
    if (limit <= 7) return '5d';
    if (limit <= 30) return '1mo';
    if (limit <= 90) return '6mo';
    if (limit <= 365) return '1y';
    return '5y';
  }

  static double? _asDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  /// Safe list index access (Yahoo arrays may be shorter than `timestamp`).
  static Object? _at(List list, int index) =>
      index >= 0 && index < list.length ? list[index] : null;
}
