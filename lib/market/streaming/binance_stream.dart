import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/quote.dart';

/// Live crypto ticks from Binance's public WebSocket stream.
///
/// No API key required. Reconnects with exponential backoff and falls back to
/// the `data-stream.binance.vision` mirror when the primary is blocked.
class BinanceQuoteStream {
  BinanceQuoteStream({
    this.primaryUrl = 'wss://stream.binance.com:9443',
    this.mirrorUrl = 'wss://data-stream.binance.vision',
  });

  final String primaryUrl;
  final String mirrorUrl;

  final StreamController<Quote> _controller =
      StreamController<Quote>.broadcast();

  /// Canonical symbol -> Binance stream name (e.g. `BTC-USD` -> `btcusdt@ticker`).
  final Map<String, String> _canonicalToStream = {};
  final Map<String, String> _streamToCanonical = {};

  WebSocket? _socket;
  Timer? _retry;
  bool _closed = false;
  int _attempt = 0;
  bool _useMirror = false;

  Stream<Quote> get quotes => _controller.stream;

  bool get isConnected => _socket != null;

  int get reconnectAttempts => _attempt;

  /// Subscribes to 24h rolling ticker updates for the given pairs.
  ///
  /// [canonicalToProvider] maps local symbols (`BTC-USD`) to Binance symbols
  /// (`BTCUSDT`).
  Future<void> subscribe(Map<String, String> canonicalToProvider) async {
    _canonicalToStream
      ..clear()
      ..addAll({
        for (final entry in canonicalToProvider.entries)
          entry.key: '${entry.value.toLowerCase()}@ticker',
      });
    _streamToCanonical
      ..clear()
      ..addAll({
        for (final entry in _canonicalToStream.entries) entry.value: entry.key,
      });
    await _connect();
  }

  Future<void> _connect() async {
    if (_closed || _canonicalToStream.isEmpty) return;
    await _closeSocket();

    final names = _canonicalToStream.values.toList();
    final base = _useMirror ? mirrorUrl : primaryUrl;
    final uri = Uri.parse('$base/stream?streams=${names.join('/')}');

    try {
      _socket = await WebSocket.connect(uri.toString());
      _attempt = 0;
      _socket!.listen(
        _onMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    final quote = parseMessage(raw, _streamToCanonical);
    if (quote != null) _controller.add(quote);
  }

  void _scheduleReconnect() {
    _socket = null;
    if (_closed) return;
    _attempt++;
    // After a few failures try the mirror, which is reachable where the main
    // host is blocked.
    if (_attempt >= 2) _useMirror = true;

    final seconds = (1 << (_attempt.clamp(1, 5))).clamp(1, 30);
    _retry?.cancel();
    _retry = Timer(Duration(seconds: seconds), _connect);
  }

  Future<void> _closeSocket() async {
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      await socket.close();
    }
  }

  /// Stops streaming but keeps the instance reusable.
  Future<void> disconnect() async {
    _retry?.cancel();
    _retry = null;
    await _closeSocket();
  }

  Future<void> dispose() async {
    _closed = true;
    await disconnect();
    await _controller.close();
  }

  /// Parses a combined-stream frame into a [Quote].
  ///
  /// Payload shape:
  /// `{"stream":"btcusdt@ticker","data":{"c":"65000","o":"64000","p":"1000",
  ///   "P":"1.56","E":1750000000000,...}}`
  static Quote? parseMessage(String raw, Map<String, String> streamToCanonical) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final stream = decoded['stream'] as String?;
      final data = decoded['data'];
      if (stream == null || data is! Map<String, dynamic>) return null;
      final canonical = streamToCanonical[stream];
      if (canonical == null) return null;
      return parseTicker(data, symbol: canonical);
    } catch (_) {
      return null;
    }
  }

  /// Pure parser for a Binance 24h ticker payload.
  static Quote? parseTicker(Map<String, dynamic> data, {required String symbol}) {
    final last = double.tryParse('${data['c']}');
    if (last == null) return null;
    final open = double.tryParse('${data['o']}');
    final eventTime = data['E'];
    final asOf = eventTime is num
        ? DateTime.fromMillisecondsSinceEpoch(eventTime.toInt(), isUtc: true)
        : DateTime.now().toUtc();

    return Quote.derive(
      symbol: symbol,
      price: last,
      previousClose: open,
      change: double.tryParse('${data['p']}'),
      changePercent: double.tryParse('${data['P']}'),
      asOf: asOf,
      source: 'binance-ws',
    );
  }
}
