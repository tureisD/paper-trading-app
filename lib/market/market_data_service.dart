import 'models/candle.dart';
import 'models/instrument.dart';
import 'models/quote.dart';
import 'instrument_repository.dart';
import 'providers/binance_provider.dart';
import 'providers/ecb_provider.dart';
import 'providers/fred_provider.dart';
import 'providers/market_data_provider.dart';
import 'providers/yahoo_provider.dart';
import 'quote_repository.dart';

/// Routes each instrument to the provider that can serve it and caches the
/// result locally.
class MarketDataService {
  MarketDataService({
    required this.instruments,
    required this.quotes,
    List<MarketDataProvider>? providers,
  }) : _providers = <String, MarketDataProvider>{
          for (final p in providers ?? defaultProviders()) p.id: p,
        };

  final InstrumentRepository instruments;
  final QuoteRepository quotes;
  final Map<String, MarketDataProvider> _providers;

  static List<MarketDataProvider> defaultProviders() => <MarketDataProvider>[
        BinanceProvider(),
        YahooFinanceProvider(),
        FredProvider(),
        EcbProvider(),
      ];

  Iterable<MarketDataProvider> get providers => _providers.values;

  /// Resolves the provider for an instrument: explicit `provider` first, then
  /// the first provider that supports its asset class.
  MarketDataProvider? providerFor(Instrument instrument) {
    final explicit = instrument.provider;
    if (explicit != null && _providers.containsKey(explicit)) {
      return _providers[explicit];
    }
    for (final provider in _providers.values) {
      if (provider.supported.contains(instrument.assetClass)) return provider;
    }
    return null;
  }

  /// Fetches a fresh quote for one instrument and caches it.
  Future<Quote> refreshQuote(Instrument instrument) async {
    final provider = providerFor(instrument);
    if (provider == null) {
      throw MarketDataException(
        'No provider supports ${instrument.assetClass.label} '
        '(${instrument.symbol})',
        source: 'service',
      );
    }
    final quote = await provider.fetchQuote(
      symbol: instrument.symbol,
      providerSymbol: instrument.providerSymbol ?? instrument.symbol,
      currency: instrument.currency,
    );
    quotes.save(quote);
    return quote;
  }

  /// Best-effort refresh across many instruments; failed symbols are skipped.
  ///
  /// Runs with bounded concurrency so a large result set still refreshes
  /// quickly without hammering any single provider.
  Future<List<Quote>> refreshQuotes(
    Iterable<Instrument> targets, {
    int concurrency = 6,
  }) async {
    final list = targets.toList(growable: false);
    final results = <Quote>[];

    for (var start = 0; start < list.length; start += concurrency) {
      final end = (start + concurrency < list.length)
          ? start + concurrency
          : list.length;
      final batch = list.sublist(start, end);
      final settled = await Future.wait(
        batch.map((instrument) async {
          try {
            return await refreshQuote(instrument);
          } on MarketDataException {
            return null; // Skip instruments the upstream could not serve.
          }
        }),
      );
      results.addAll(settled.whereType<Quote>());
    }
    return results;
  }

  /// Historical bars for an instrument, oldest first.
  Future<List<Candle>> candles(
    Instrument instrument, {
    String interval = '1d',
    int limit = 90,
  }) async {
    final provider = providerFor(instrument);
    if (provider == null) {
      throw MarketDataException(
        'No provider supports ${instrument.assetClass.label} '
        '(${instrument.symbol})',
        source: 'service',
      );
    }
    return provider.fetchCandles(
      providerSymbol: instrument.providerSymbol ?? instrument.symbol,
      interval: interval,
      limit: limit,
    );
  }
}
