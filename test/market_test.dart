import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:paper_trading_app/data/app_database.dart';
import 'package:paper_trading_app/market/asset_class.dart';
import 'package:paper_trading_app/market/catalog_importer.dart';
import 'package:paper_trading_app/market/instrument_repository.dart';
import 'package:paper_trading_app/market/models/instrument.dart';
import 'package:paper_trading_app/market/models/quote.dart';
import 'package:paper_trading_app/market/providers/binance_provider.dart';
import 'package:paper_trading_app/market/providers/fred_provider.dart';
import 'package:paper_trading_app/market/providers/yahoo_provider.dart';
import 'package:paper_trading_app/market/quote_repository.dart';

http.Response _json(String body) =>
    http.Response(body, 200, headers: {'content-type': 'application/json'});

void main() {
  group('BinanceProvider', () {
    test('maps canonical pairs to Binance symbols', () {
      expect(BinanceProvider.toProviderSymbol('BTC-USD'), 'BTCUSDT');
      expect(BinanceProvider.toProviderSymbol('ETH-EUR'), 'ETHEUR');
      expect(BinanceProvider.toProviderSymbol('SOL-USDT'), 'SOLUSDT');
    });

    test('parses a 24h ticker into a derived quote', () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'api.binance.com');
        return _json(
          '{"symbol":"BTCUSDT","lastPrice":"65300.00","prevClosePrice":"63800.00",'
          '"priceChange":"1500.00","priceChangePercent":"2.35"}',
        );
      });
      final provider = BinanceProvider(client: client);

      final quote = await provider.fetchQuote(
        symbol: 'BTC-USD',
        providerSymbol: 'BTCUSDT',
      );

      expect(quote.symbol, 'BTC-USD');
      expect(quote.price, 65300.0);
      expect(quote.previousClose, 63800.0);
      expect(quote.change, 1500.0);
      expect(quote.changePercent, 2.35);
      expect(quote.source, 'binance');
    });

    test('falls back to the data-api mirror when the primary fails', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'api.binance.com') {
          return http.Response('blocked', 451);
        }
        expect(request.url.host, 'data-api.binance.vision');
        return _json('{"lastPrice":"100.0","prevClosePrice":"90.0"}');
      });
      final provider = BinanceProvider(client: client);

      final quote = await provider.fetchQuote(
        symbol: 'BTC-USD',
        providerSymbol: 'BTCUSDT',
      );
      expect(quote.price, 100.0);
    });
  });

  group('YahooFinanceProvider', () {
    test('parses a chart response into a quote and candles', () async {
      final client = MockClient((request) async {
        expect(request.url.path, contains('/v8/finance/chart/AAPL'));
        return _json('''
        {"chart":{"result":[{
          "meta":{"regularMarketPrice":195.5,"chartPreviousClose":193.0,"currency":"USD"},
          "timestamp":[1700000000,1700086400],
          "indicators":{"quote":[{
            "open":[190.0,192.0],"high":[196.0,197.0],"low":[189.0,191.0],
            "close":[195.5,196.2],"volume":[1000,2000]
          }]}
        }],"error":null}}
        ''');
      });
      final provider = YahooFinanceProvider(client: client);

      final quote = await provider.fetchQuote(
        symbol: 'AAPL',
        providerSymbol: 'AAPL',
      );
      expect(quote.price, 195.5);
      expect(quote.previousClose, 193.0);
      expect(quote.change, closeTo(2.5, 1e-9));
      expect(quote.source, 'yahoo');

      final candles = await provider.fetchCandles(
        providerSymbol: 'AAPL',
        limit: 10,
      );
      expect(candles, hasLength(2));
      expect(candles.last.close, 196.2);
      expect(candles.last.volume, 2000);
    });
  });

  group('FredProvider', () {
    test('parses CSV, skipping missing observations', () async {
      const csv = 'observation_date,DGS10\n'
          '2026-09-01,4.10\n'
          '2026-09-02,.\n'
          '2026-09-03,4.15\n';
      final client = MockClient((request) async {
        expect(request.url.queryParameters['id'], 'DGS10');
        return http.Response(csv, 200);
      });
      final provider = FredProvider(client: client);

      final quote = await provider.fetchQuote(
        symbol: 'DGS10',
        providerSymbol: 'DGS10',
      );

      expect(quote.price, 4.15);
      expect(quote.previousClose, 4.10);
      expect(quote.change, closeTo(0.05, 1e-9));
      expect(quote.source, 'fred');
    });
  });

  group('InstrumentRepository (FTS5)', () {
    late AppDatabase db;
    late InstrumentRepository instruments;

    setUp(() {
      db = AppDatabase.inMemory();
      instruments = InstrumentRepository(db);
    });
    tearDown(() => db.close());

    test('searches by symbol, name fragment and ISIN', () {
      instruments.upsertAll(const [
        Instrument(
          symbol: 'AAPL',
          name: 'Apple Inc.',
          assetClass: AssetClass.stock,
          isin: 'US0378331005',
          provider: 'yahoo',
        ),
        Instrument(
          symbol: 'BTC-USD',
          name: 'Bitcoin',
          assetClass: AssetClass.crypto,
          provider: 'binance',
          providerSymbol: 'BTCUSDT',
        ),
      ]);

      expect(instruments.search('aapl').single.symbol, 'AAPL');
      expect(instruments.search('appl').single.symbol, 'AAPL');
      expect(instruments.search('US0378331005').single.symbol, 'AAPL');
      expect(instruments.search('bitco').single.symbol, 'BTC-USD');
    });

    test('filters by asset class', () {
      instruments.upsertAll(const [
        Instrument(
          symbol: 'AAPL',
          name: 'Apple Inc.',
          assetClass: AssetClass.stock,
        ),
        Instrument(
          symbol: 'SPY',
          name: 'SPDR S&P 500 ETF Trust',
          assetClass: AssetClass.etf,
        ),
      ]);

      final etfs = instruments.search('', assetClass: AssetClass.etf);
      expect(etfs.map((e) => e.symbol), contains('SPY'));
      expect(etfs.map((e) => e.symbol), isNot(contains('AAPL')));
      expect(instruments.countByClass()[AssetClass.etf], 1);
    });

    test('stores bond reference data', () {
      instruments.upsert(
        const Instrument(
          symbol: 'DGS10',
          name: 'US Treasury 10-Year Yield',
          assetClass: AssetClass.bond,
          provider: 'fred',
        ),
        bondDetails: const BondDetails(
          symbol: 'DGS10',
          parValue: 100,
          couponFrequency: 2,
          dayCount: 'Actual/Actual',
        ),
      );
      final details = instruments.bondDetails('DGS10');
      expect(details?.dayCount, 'Actual/Actual');
      expect(details?.couponFrequency, 2);
    });
  });

  group('QuoteRepository', () {
    test('upserts and bulk-reads quotes', () {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final quotes = QuoteRepository(db);

      quotes.saveAll([
        Quote.derive(
          symbol: 'AAPL',
          price: 195.5,
          previousClose: 193.0,
          source: 'yahoo',
          asOf: DateTime.utc(2026, 1, 2),
        ),
        Quote.derive(
          symbol: 'BTC-USD',
          price: 65300,
          previousClose: 63800,
          source: 'binance',
          asOf: DateTime.utc(2026, 1, 2),
        ),
      ]);

      expect(quotes.count(), 2);
      final many = quotes.getMany(['AAPL', 'BTC-USD', 'MISSING']);
      expect(many.keys, containsAll(['AAPL', 'BTC-USD']));
      expect(many['AAPL']!.change, closeTo(2.5, 1e-9));
      expect(quotes.getMany(const []), isEmpty);
    });
  });

  group('CatalogImporter', () {
    test('parses instruments and bond details', () {
      const raw = '''
      {"version":1,"instruments":[
        {"symbol":"AAPL","name":"Apple Inc.","assetClass":"STOCK","provider":"yahoo"},
        {"symbol":"DGS10","name":"US Treasury 10-Year Yield","assetClass":"BOND",
         "provider":"fred","bond":{"parValue":100,"couponFrequency":2,"dayCount":"Actual/Actual"}}
      ]}''';

      final payload = CatalogImporter.parse(raw);

      expect(payload.instruments, hasLength(2));
      expect(payload.instruments.first.assetClass, AssetClass.stock);
      expect(payload.bondDetails['DGS10']!.parValue, 100);
      expect(payload.bondDetails.containsKey('AAPL'), isFalse);
    });

    test('the bundled catalog covers every asset class', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final raw = await rootBundle.loadString(CatalogImporter.assetPath);
      final payload = CatalogImporter.parse(raw);

      expect(payload.instruments.length, greaterThan(50));
      expect(
        payload.instruments.map((e) => e.assetClass).toSet(),
        containsAll(AssetClass.values),
      );
      expect(payload.version, greaterThanOrEqualTo(2));
      expect(
        payload.instruments
            .where((i) => i.assetClass == AssetClass.etf)
            .every((i) => i.expenseRatio != null),
        isTrue,
        reason: 'ETFs should carry an expense ratio for the detail sheet',
      );
    });

    test('parses the catalog version and expense ratios', () {
      const raw = '''
      {"version":7,"instruments":[
        {"symbol":"SPY","name":"SPDR S&P 500 ETF Trust","assetClass":"ETF",
         "expenseRatio":0.0945,"provider":"yahoo"}
      ]}''';

      final payload = CatalogImporter.parse(raw);
      expect(payload.version, 7);
      expect(payload.instruments.single.expenseRatio, closeTo(0.0945, 1e-9));
    });
  });
}
