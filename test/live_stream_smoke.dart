import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paper_trading_app/market/streaming/binance_stream.dart';
import 'package:paper_trading_app/market/streaming/quote_batcher.dart';

/// Live smoke test for the Binance WebSocket stream (Phase 7).
///
/// Not auto-discovered; run explicitly:
///
///   TB_LIVE=1 flutter test test/live_stream_smoke.dart
void main() {
  final enabled = Platform.environment['TB_LIVE'] == '1';

  test(
    'receives live ticks and coalesces them into frames',
    skip: !enabled,
    () async {
      final stream = BinanceQuoteStream();
      final batcher = QuoteBatcher(onBatch: (batch) {});
      final subscription = stream.quotes.listen(batcher.add);

      await stream.subscribe({'BTC-USD': 'BTCUSDT', 'ETH-USD': 'ETHUSDT'});
      await Future<void>.delayed(const Duration(seconds: 12));
      batcher.flushNow();

      // ignore: avoid_print
      print(
        'connected=${stream.isConnected} '
        'ticks=${batcher.receivedTicks} '
        'frames=${batcher.emittedBatches} '
        'coalesced=${(batcher.coalescedFraction * 100).toStringAsFixed(1)}%',
      );

      await subscription.cancel();
      batcher.dispose();
      await stream.dispose();

      expect(
        batcher.receivedTicks,
        greaterThan(0),
        reason: 'expected live ticks from Binance',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
