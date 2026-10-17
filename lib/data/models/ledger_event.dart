import 'package:sqlite3/sqlite3.dart';

/// Event types stored in `ledger_events`.
class EventType {
  const EventType._();

  static const String cashDeposit = 'CASH_DEPOSIT';
  static const String buy = 'BUY';
  static const String sell = 'SELL';
  static const String bondCoupon = 'BOND_COUPON';

  /// Working-order lifecycle, recorded so resting orders travel between devices.
  static const String orderPlaced = 'ORDER_PLACED';
  static const String orderCancelled = 'ORDER_CANCELLED';
  static const String orderFilled = 'ORDER_FILLED';
}

/// A single immutable row of the append-only portfolio ledger.
///
/// Portfolio state is never stored directly; it is always derived by replaying
/// these events, which is what makes cross-device sync conflict-free.
class LedgerEvent {
  const LedgerEvent({
    required this.eventId,
    required this.hlcTimestamp,
    required this.deviceId,
    required this.eventType,
    this.symbol,
    this.assetClass,
    this.quantity = 0.0,
    this.executionPrice = 0.0,
    this.accruedInterest = 0.0,
    this.fee = 0.0,
    this.currency = 'USD',
    this.synced = false,
    this.meta,
  });

  final String eventId;

  /// Hybrid-Logical-Clock timestamp; ISO-8601 placeholder until Phase 4.
  final String hlcTimestamp;
  final String deviceId;
  final String eventType;
  final String? symbol;
  final String? assetClass;
  final double quantity;
  final double executionPrice;
  final double accruedInterest;
  final double fee;
  final String currency;
  final bool synced;

  /// Free-form JSON payload (order linkage, coupon dates, ...). Never affects
  /// cash or positions during replay.
  final String? meta;

  factory LedgerEvent.fromRow(Row row) {
    return LedgerEvent(
      eventId: row['event_id'] as String,
      hlcTimestamp: row['hlc_timestamp'] as String,
      deviceId: row['device_id'] as String,
      eventType: row['event_type'] as String,
      symbol: row['symbol'] as String?,
      assetClass: row['asset_class'] as String?,
      quantity: (row['quantity'] as num).toDouble(),
      executionPrice: (row['execution_price'] as num).toDouble(),
      accruedInterest: (row['accrued_interest'] as num).toDouble(),
      fee: (row['fee'] as num).toDouble(),
      currency: row['currency'] as String,
      synced: (row['synced'] as int) != 0,
      meta: row['meta'] as String?,
    );
  }

  List<Object?> toSqlParams() => <Object?>[
        eventId,
        hlcTimestamp,
        deviceId,
        eventType,
        symbol,
        assetClass,
        quantity,
        executionPrice,
        accruedInterest,
        fee,
        currency,
        synced ? 1 : 0,
        meta,
      ];
}
