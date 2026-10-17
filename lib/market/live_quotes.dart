import 'dart:async';

import 'package:flutter/foundation.dart';

import '../trading/trading_engine.dart';
import 'models/instrument.dart';
import 'models/quote.dart';
import 'quote_repository.dart';
import 'streaming/binance_stream.dart';
import 'streaming/quote_batcher.dart';

/// Runs the live tick stream, coalesces it, persists it and re-evaluates
/// resting orders at most once per frame (roadmap Phase 7).
///
/// Notifies listeners once per emitted batch, never once per tick.
class LiveQuoteService extends ChangeNotifier {
  LiveQuoteService({
    required this.quotes,
    required this.engine,
    BinanceQuoteStream? stream,
    Duration frameInterval = const Duration(microseconds: 16600),
    this.onPersisted,
  })  : _stream = stream ?? BinanceQuoteStream(),
        frameInterval = frameInterval {
    _batcher = QuoteBatcher(
      onBatch: _handle,
      frameInterval: frameInterval,
    );
    _subscription = _stream.quotes.listen(_batcher.add);
  }

  final QuoteRepository quotes;
  final TradingEngine engine;

  /// Invoked after a batch is written, so derived views can refresh.
  final void Function(Map<String, Quote> batch)? onPersisted;

  final BinanceQuoteStream _stream;
  /// UI flush cadence (60 Hz by default, 120 Hz via `highRefreshInterval`).
  final Duration frameInterval;
  late final QuoteBatcher _batcher;
  late final StreamSubscription<Quote> _subscription;

  Map<String, Quote> _latest = const {};
  bool _streaming = false;
  String _status = 'idle';

  bool get isStreaming => _streaming;
  bool get isConnected => _stream.isConnected;

  /// Human-readable stream state for the UI.
  String get status => _status;

  /// Coalesced latest values (one per symbol, as of the last batch).
  Map<String, Quote> get latest => _latest;

  Quote? quoteFor(String symbol) => _latest[symbol];

  int get receivedTicks => _batcher.receivedTicks;
  int get emittedBatches => _batcher.emittedBatches;

  /// Share of ticks suppressed by coalescing.
  double get coalescedFraction => _batcher.coalescedFraction;

  /// Starts streaming for every crypto instrument supplied.
  ///
  /// Equities, ETFs, funds and bonds have no free push feed, so they stay on
  /// polling; only crypto is pushed.
  Future<void> start(Iterable<Instrument> instruments) async {
    final pairs = <String, String>{
      for (final instrument in instruments)
        if (instrument.assetClass.wire == 'CRYPTO')
          instrument.symbol:
              instrument.providerSymbol ?? instrument.symbol.replaceAll('-', ''),
    };

    if (pairs.isEmpty) {
      _status = 'no streamable instruments';
      _streaming = false;
      notifyListeners();
      return;
    }

    _streaming = true;
    _status = 'connecting…';
    notifyListeners();

    await _stream.subscribe(pairs);
    _status = 'live • ${pairs.length} pairs';
    notifyListeners();
  }

  Future<void> stop() async {
    _streaming = false;
    _status = 'stopped';
    await _stream.disconnect();
    notifyListeners();
  }

  void _handle(Map<String, Quote> batch) {
    _latest = <String, Quote>{..._latest, ...batch};
    quotes.saveAll(batch.values);
    for (final quote in batch.values) {
      engine.onQuote(quote);
    }
    onPersisted?.call(batch);
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription.cancel();
    _batcher.dispose();
    _stream.dispose();
    super.dispose();
  }
}
