import '../asset_class.dart';
import '../models/candle.dart';
import '../models/quote.dart';

/// Raised when a market-data provider cannot serve a request.
class MarketDataException implements Exception {
  MarketDataException(this.message, {this.source});

  final String message;
  final String? source;

  @override
  String toString() =>
      source == null ? 'MarketDataException: $message' : '[$source] $message';
}

/// A source of live quotes and historical candles.
///
/// Providers are stateless and take their HTTP client via constructor so they
/// can be exercised with a mock in tests.
abstract class MarketDataProvider {
  /// Stable identifier persisted on instruments (`binance`, `yahoo`, `fred`).
  String get id;

  /// Asset classes this provider can serve.
  Set<AssetClass> get supported;

  /// Fetches the latest quote. [symbol] is the canonical local symbol used on
  /// the returned [Quote]; [providerSymbol] is what the upstream API expects.
  Future<Quote> fetchQuote({
    required String symbol,
    required String providerSymbol,
    String currency = 'USD',
  });

  /// Fetches historical bars, oldest first.
  Future<List<Candle>> fetchCandles({
    required String providerSymbol,
    String interval = '1d',
    int limit = 90,
  });
}
