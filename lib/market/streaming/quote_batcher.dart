import 'dart:async';

import '../models/quote.dart';

/// Coalesces a high-frequency tick stream into fixed-interval batches so the UI
/// repaints at a bounded rate (roadmap Phase 7).
///
/// Only the latest quote per symbol survives a window, so a 50-tick/second
/// crypto stream still yields at most one update per symbol per frame.
class QuoteBatcher {
  QuoteBatcher({
    required this.onBatch,
    this.frameInterval = const Duration(microseconds: 16600), // 60 Hz
  });

  /// 120 Hz variant.
  static const Duration highRefreshInterval = Duration(microseconds: 8300);

  final void Function(Map<String, Quote> batch) onBatch;
  final Duration frameInterval;

  final Map<String, Quote> _pending = <String, Quote>{};
  Timer? _timer;

  int _received = 0;
  int _emitted = 0;

  /// Ticks seen (before coalescing).
  int get receivedTicks => _received;

  /// Batches delivered to [onBatch].
  int get emittedBatches => _emitted;

  /// Fraction of ticks suppressed by coalescing (0..1); 1.0 means everything
  /// collapsed into a single batch.
  double get coalescedFraction =>
      _received == 0 ? 0 : 1 - (_emitted / _received);

  int get pendingSymbols => _pending.length;

  void add(Quote quote) {
    _pending[quote.symbol] = quote; // latest wins within the window
    _received++;
    _timer ??= Timer(frameInterval, _flush);
  }

  void addAll(Iterable<Quote> quotes) {
    for (final quote in quotes) {
      add(quote);
    }
  }

  /// Flushes immediately (tab switch, shutdown) instead of waiting for the tick.
  void flushNow() {
    _timer?.cancel();
    _timer = null;
    _flush();
  }

  void _flush() {
    _timer = null;
    if (_pending.isEmpty) return;
    final batch = Map<String, Quote>.of(_pending);
    _pending.clear();
    _emitted++;
    onBatch(batch);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }
}
