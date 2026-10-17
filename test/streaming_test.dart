import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:paper_trading_app/market/models/quote.dart';
import 'package:paper_trading_app/market/providers/ecb_provider.dart';
import 'package:paper_trading_app/market/streaming/binance_stream.dart';
import 'package:paper_trading_app/market/streaming/quote_batcher.dart';

Quote _quote(String symbol, double price) => Quote.derive(
      symbol: symbol,
      price: price,
      source: 'test',
      asOf: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('QuoteBatcher', () {
    test('coalesces a burst into one batch and keeps the latest value', () {
      fakeAsync((async) {
        final batches = <Map<String, Quote>>[];
        final batcher = QuoteBatcher(onBatch: batches.add);

        for (var i = 0; i < 20; i++) {
          batcher.add(_quote('BTC-USD', 100 + i.toDouble()));
        }
        batcher.add(_quote('ETH-USD', 50));

        expect(batches, isEmpty, reason: 'nothing emitted mid-frame');

        async.elapse(QuoteBatcher.highRefreshInterval * 3);

        expect(batches, hasLength(1));
        expect(batches.single, hasLength(2));
        expect(batches.single['BTC-USD']!.price, 119, reason: 'latest wins');
        expect(batcher.receivedTicks, 21);
        expect(batcher.emittedBatches, 1);
        expect(batcher.coalescedFraction, closeTo(1 - 1 / 21, 1e-9));
        batcher.dispose();
      });
    });

    test('emits one batch per frame window', () {
      fakeAsync((async) {
        final batches = <Map<String, Quote>>[];
        final batcher = QuoteBatcher(
          onBatch: batches.add,
          frameInterval: const Duration(milliseconds: 16),
        );

        batcher.add(_quote('A', 1));
        async.elapse(const Duration(milliseconds: 16));
        batcher.add(_quote('A', 2));
        async.elapse(const Duration(milliseconds: 16));

        expect(batches, hasLength(2));
        expect(batches.first['A']!.price, 1);
        expect(batches.last['A']!.price, 2);
        batcher.dispose();
      });
    });

    test('flushNow drains immediately', () {
      fakeAsync((async) {
        final batches = <Map<String, Quote>>[];
        final batcher = QuoteBatcher(onBatch: batches.add);
        batcher.add(_quote('A', 1));
        batcher.flushNow();
        expect(batches, hasLength(1));
        batcher.dispose();
      });
    });

    test('120 Hz interval is half the 60 Hz interval', () {
      expect(
        QuoteBatcher.highRefreshInterval.inMicroseconds * 2,
        closeTo(16600, 1),
      );
    });
  });

  group('BinanceQuoteStream', () {
    test('parses a 24h ticker frame', () {
      final quote = BinanceQuoteStream.parseTicker(
        {
          'c': '65000.5',
          'o': '64000.0',
          'p': '1000.5',
          'P': '1.56',
          'E': 1750000000000,
        },
        symbol: 'BTC-USD',
      );

      expect(quote, isNotNull);
      expect(quote!.price, 65000.5);
      expect(quote.previousClose, 64000);
      expect(quote.change, 1000.5);
      expect(quote.changePercent, 1.56);
      expect(quote.source, 'binance-ws');
      expect(
        quote.asOf,
        DateTime.fromMillisecondsSinceEpoch(1750000000000, isUtc: true),
      );
    });

    test('parses a combined-stream envelope and maps the stream name', () {
      final raw = jsonEncode({
        'stream': 'btcusdt@ticker',
        'data': {'c': '100', 'o': '90', 'E': 1},
      });

      final quote = BinanceQuoteStream.parseMessage(raw, {
        'btcusdt@ticker': 'BTC-USD',
      });

      expect(quote!.symbol, 'BTC-USD');
      expect(quote.price, 100);
      expect(quote.change, closeTo(10, 1e-9)); // derived from the open
    });

    test('ignores malformed payloads and unknown streams', () {
      expect(BinanceQuoteStream.parseMessage('not json', const {}), isNull);
      expect(
        BinanceQuoteStream.parseMessage(
          jsonEncode({'stream': 'btcusdt@ticker', 'data': {'c': '1'}}),
          const {},
        ),
        isNull,
        reason: 'stream not subscribed',
      );
      expect(
        BinanceQuoteStream.parseMessage(
          jsonEncode({'stream': 'x@ticker', 'data': <String, dynamic>{}}),
          {'x@ticker': 'X'},
        ),
        isNull,
        reason: 'no last price',
      );
    });
  });

  group('EcbProvider', () {
    const csv = 'KEY,FREQ,TIME_PERIOD,OBS_VALUE\n'
        'YC.B.U2.SR_10Y,B,2026-09-01,3.10\n'
        'YC.B.U2.SR_10Y,B,2026-09-02,3.25\n'
        'YC.B.U2.SR_10Y,B,2026-09-03,3.30\n';

    test('parses SDMX CSV by column name', () {
      final series = EcbProvider.parseCsv(csv);
      expect(series, hasLength(3));
      expect(series.last.value, 3.30);
      expect(series.last.date, DateTime.utc(2026, 9, 3));
    });

    test('handles quoted fields and missing values', () {
      const quoted = 'KEY,TIME_PERIOD,OBS_VALUE\n'
          '"YC,B.U2","2026-09-01","3.10"\n'
          '"YC,B.U2","2026-09-02",""\n';
      final series = EcbProvider.parseCsv(quoted);
      expect(series, hasLength(1));
      expect(series.single.value, 3.10);
    });

    test('fetches a quote from the latest observation', () async {
      final client = MockClient((request) async {
        expect(request.url.path, contains('/service/data/'));
        expect(request.url.queryParameters['format'], 'csvdata');
        expect(request.url.queryParameters['lastNObservations'], isNotNull);
        return http.Response(csv, 200);
      });

      final provider = EcbProvider(client: client);
      final quote = await provider.fetchQuote(
        symbol: 'EU10Y',
        providerSymbol: 'YC/B.U2.EUR.4F.G_N_A.SV_C_YM.SR_10Y',
      );

      expect(quote.price, 3.30);
      expect(quote.previousClose, 3.25);
      expect(quote.currency, 'EUR');
      expect(quote.source, 'ecb');
    });
  });
}
