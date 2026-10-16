import 'dart:convert';

import '../data/models/ledger_event.dart';
import 'hlc.dart';

/// NDJSON codec for ledger shard files.
///
/// One ledger event per line, so appending is cheap and a partial/truncated
/// file still yields the lines that made it.
class ShardCodec {
  const ShardCodec._();

  static const String shardPrefix = 'ledger.';
  static const String shardSuffix = '.ndjson';
  static const String metaFileName = 'meta.json';

  /// `ledger.<device>.<yyyy-MM>.ndjson` — one immutable-ish file per device
  /// per month, so no shard ever grows without bound.
  static String shardFileName(String deviceId, DateTime month) {
    final m = month.month.toString().padLeft(2, '0');
    return '$shardPrefix$deviceId.${month.year}-$m$shardSuffix';
  }

  static bool isShardFile(String name) =>
      name.startsWith(shardPrefix) && name.endsWith(shardSuffix);

  static String encodeEvents(Iterable<LedgerEvent> events) {
    final sorted = events.toList()
      ..sort((a, b) => Hlc.parse(a.hlcTimestamp)
          .compareTo(Hlc.parse(b.hlcTimestamp)));
    final buffer = StringBuffer();
    for (final event in sorted) {
      buffer.writeln(jsonEncode(toJson(event)));
    }
    return buffer.toString();
  }

  static Map<String, Object?> toJson(LedgerEvent event) => <String, Object?>{
        'event_id': event.eventId,
        'hlc': event.hlcTimestamp,
        'device': event.deviceId,
        'type': event.eventType,
        if (event.symbol != null) 'symbol': event.symbol,
        if (event.assetClass != null) 'asset_class': event.assetClass,
        'quantity': event.quantity,
        'price': event.executionPrice,
        'accrued': event.accruedInterest,
        'fee': event.fee,
        'currency': event.currency,
      };

  /// Decodes a local event. Remote events are already durable on the cloud, so
  /// they are marked synced on insertion.
  static LedgerEvent fromJson(Map<String, dynamic> json, {bool synced = true}) {
    return LedgerEvent(
      eventId: json['event_id'] as String,
      hlcTimestamp: json['hlc'] as String,
      deviceId: (json['device'] as String?) ?? 'unknown_device',
      eventType: json['type'] as String,
      symbol: json['symbol'] as String?,
      assetClass: json['asset_class'] as String?,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      executionPrice: (json['price'] as num?)?.toDouble() ?? 0.0,
      accruedInterest: (json['accrued'] as num?)?.toDouble() ?? 0.0,
      fee: (json['fee'] as num?)?.toDouble() ?? 0.0,
      currency: (json['currency'] as String?) ?? 'USD',
      synced: synced,
    );
  }

  /// Decodes an NDJSON document, skipping blank or malformed lines.
  static List<LedgerEvent> decodeEvents(String ndjson) {
    final events = <LedgerEvent>[];
    for (final line in const LineSplitter().convert(ndjson)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        events.add(fromJson(jsonDecode(trimmed) as Map<String, dynamic>));
      } catch (_) {
        // A partially-written or future-schema line must not break the merge.
      }
    }
    return events;
  }
}
