import 'package:sqlite3/sqlite3.dart';

import '../market/asset_class.dart';

/// Direction of an order.
enum OrderSide {
  buy('BUY'),
  sell('SELL');

  const OrderSide(this.wire);

  final String wire;

  static OrderSide fromWire(String value) =>
      value.toUpperCase() == 'SELL' ? sell : buy;

  OrderSide get opposite => this == buy ? sell : buy;
}

/// Order execution style.
enum OrderType {
  market('MARKET'),
  limit('LIMIT'),
  stop('STOP');

  const OrderType(this.wire);

  final String wire;

  static OrderType fromWire(String value) => values.firstWhere(
        (t) => t.wire == value.toUpperCase(),
        orElse: () => market,
      );
}

/// Lifecycle state of an order.
enum OrderStatus {
  /// Resting in the local book, waiting for a trigger.
  pending('PENDING'),

  /// A fund order accepted intraday; settles at the next published EOD NAV.
  queuedNav('QUEUED_NAV'),

  filled('FILLED'),
  cancelled('CANCELLED'),
  rejected('REJECTED');

  const OrderStatus(this.wire);

  final String wire;

  bool get isWorking => this == pending || this == queuedNav;

  static OrderStatus fromWire(String value) => values.firstWhere(
        (s) => s.wire == value.toUpperCase(),
        orElse: () => pending,
      );
}

/// A paper order. Working orders live in `pending_orders`; once filled, the
/// economic effect is recorded as an immutable ledger event.
class Order {
  const Order({
    required this.orderId,
    required this.accountId,
    required this.symbol,
    required this.assetClass,
    required this.side,
    required this.type,
    required this.quantity,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.limitPrice,
    this.stopPrice,
    this.filledEventId,
    this.note,
  });

  final String orderId;
  final String accountId;
  final String symbol;
  final AssetClass assetClass;
  final OrderSide side;
  final OrderType type;
  final double quantity;
  final double? limitPrice;
  final double? stopPrice;
  final OrderStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? filledEventId;
  final String? note;

  factory Order.fromRow(Row row) => Order(
        orderId: row['order_id'] as String,
        accountId: row['account_id'] as String,
        symbol: row['symbol'] as String,
        assetClass: AssetClass.fromWire(row['asset_class'] as String),
        side: OrderSide.fromWire(row['side'] as String),
        type: OrderType.fromWire(row['order_type'] as String),
        quantity: (row['quantity'] as num).toDouble(),
        limitPrice: (row['limit_price'] as num?)?.toDouble(),
        stopPrice: (row['stop_price'] as num?)?.toDouble(),
        status: OrderStatus.fromWire(row['status'] as String),
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
        filledEventId: row['filled_event_id'] as String?,
        note: row['note'] as String?,
      );

  List<Object?> toSqlParams() => <Object?>[
        orderId,
        accountId,
        symbol,
        assetClass.wire,
        side.wire,
        type.wire,
        quantity,
        limitPrice,
        stopPrice,
        status.wire,
        createdAt.toUtc().toIso8601String(),
        updatedAt.toUtc().toIso8601String(),
        filledEventId,
        note,
      ];

  Order copyWith({
    OrderStatus? status,
    DateTime? updatedAt,
    String? filledEventId,
    String? note,
  }) {
    return Order(
      orderId: orderId,
      accountId: accountId,
      symbol: symbol,
      assetClass: assetClass,
      side: side,
      type: type,
      quantity: quantity,
      limitPrice: limitPrice,
      stopPrice: stopPrice,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      filledEventId: filledEventId ?? this.filledEventId,
      note: note ?? this.note,
    );
  }
}
