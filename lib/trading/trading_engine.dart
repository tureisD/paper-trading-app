import '../core/ids.dart';
import '../data/app_database.dart';
import '../data/ledger_repository.dart';
import '../data/models/ledger_event.dart';
import '../market/asset_class.dart';
import '../market/instrument_repository.dart';
import '../market/models/instrument.dart';
import '../market/models/quote.dart';
import 'account_repository.dart';
import 'bond_math.dart';
import 'fee_model.dart';
import 'order.dart';
import 'pending_order_repository.dart';
import 'portfolio.dart';
import 'portfolio_engine.dart';
import 'position_repository.dart';

/// Outcome of submitting or evaluating an order.
class TradeResult {
  const TradeResult({
    required this.order,
    this.event,
    this.rejectionReason,
    this.executionPrice,
    this.fee = 0.0,
    this.accruedInterest = 0.0,
    this.cashDelta = 0.0,
  });

  final Order order;
  final LedgerEvent? event;
  final String? rejectionReason;
  final double? executionPrice;
  final double fee;
  final double accruedInterest;
  final double cashDelta;

  OrderStatus get status => order.status;
  bool get isFilled => order.status == OrderStatus.filled;
  bool get isWorking => order.status.isWorking;
  bool get isRejected => order.status == OrderStatus.rejected;
}

/// The paper matching + settlement engine.
///
/// Filled orders are recorded as immutable ledger events; portfolio state is
/// always re-derived by replay rather than mutated in place.
class TradingEngine {
  TradingEngine({
    required this.database,
    required this.ledger,
    required this.orders,
    required this.positions,
    required this.instruments,
  });

  final AppDatabase database;
  final LedgerRepository ledger;
  final PendingOrderRepository orders;
  final PositionRepository positions;
  final InstrumentRepository instruments;

  /// Derived portfolio state straight from the ledger.
  PortfolioSnapshot snapshot() => PortfolioEngine.replay(ledger.all());

  /// Rebuilds the position cache from the ledger.
  void rebuildCache({
    String accountId = AccountRepository.defaultAccountId,
  }) {
    final state = snapshot();
    positions.replaceAll(accountId, state.positions.values.toList());
  }

  /// Submits an order. Marketable orders fill immediately; otherwise the order
  /// rests in the local book (or queues for the next fund NAV).
  TradeResult submit({
    required Instrument instrument,
    required OrderSide side,
    required OrderType type,
    required double quantity,
    Quote? quote,
    double? limitPrice,
    double? stopPrice,
    DateTime? now,
    String accountId = AccountRepository.defaultAccountId,
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final orderId = Ids.uuidV7(now: timestamp);

    // --- Parameter + precision validation ---
    if (!FeeModel.isValidQuantity(quantity, instrument.assetClass)) {
      return _reject(
        orderId: orderId,
        accountId: accountId,
        instrument: instrument,
        side: side,
        type: type,
        quantity: quantity,
        limitPrice: limitPrice,
        stopPrice: stopPrice,
        timestamp: timestamp,
        reason: 'Quantity must be a positive multiple of '
            '${FeeModel.quantityStep(instrument.assetClass)}',
      );
    }
    if (type == OrderType.limit && limitPrice == null) {
      return _reject(
        orderId: orderId,
        accountId: accountId,
        instrument: instrument,
        side: side,
        type: type,
        quantity: quantity,
        limitPrice: limitPrice,
        stopPrice: stopPrice,
        timestamp: timestamp,
        reason: 'Limit price is required for a limit order',
      );
    }
    if (type == OrderType.stop && stopPrice == null) {
      return _reject(
        orderId: orderId,
        accountId: accountId,
        instrument: instrument,
        side: side,
        type: type,
        quantity: quantity,
        limitPrice: limitPrice,
        stopPrice: stopPrice,
        timestamp: timestamp,
        reason: 'Stop price is required for a stop order',
      );
    }

    Order order = Order(
      orderId: orderId,
      accountId: accountId,
      symbol: instrument.symbol,
      assetClass: instrument.assetClass,
      side: side,
      type: type,
      quantity: quantity,
      limitPrice: limitPrice,
      stopPrice: stopPrice,
      status: OrderStatus.pending,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    // --- Funds: intraday orders always queue for the next published NAV. ---
    if (instrument.assetClass == AssetClass.fund) {
      order = order.copyWith(
        status: OrderStatus.queuedNav,
        note: 'Awaiting next EOD NAV',
      );
      orders.upsert(order);
      return TradeResult(order: order);
    }

    // --- Decide whether it can execute against the supplied quote. ---
    final shouldExecute = quote != null && _shouldExecute(order, quote);

    if (!shouldExecute) {
      // Resting order (or one we cannot yet evaluate).
      if (quote == null && type == OrderType.market) {
        return _reject(
          orderId: orderId,
          accountId: accountId,
          instrument: instrument,
          side: side,
          type: type,
          quantity: quantity,
          limitPrice: limitPrice,
          stopPrice: stopPrice,
          timestamp: timestamp,
          reason: 'A market order requires a current quote',
        );
      }
      orders.upsert(order);
      return TradeResult(order: order);
    }

    return _fill(
      order: order,
      instrument: instrument,
      price: quote.price,
      timestamp: timestamp,
    );
  }

  /// Evaluates resting orders for a symbol against a new quote.
  List<TradeResult> onQuote(Quote quote, {DateTime? now}) {
    final results = <TradeResult>[];
    for (final order in orders.bySymbol(quote.symbol)) {
      if (order.status != OrderStatus.pending) continue;
      final instrument = _resolveInstrument(order);
      if (!_shouldExecute(order, quote)) continue;
      results.add(
        _fill(
          order: order,
          instrument: instrument,
          price: quote.price,
          timestamp: (now ?? DateTime.now()).toUtc(),
        ),
      );
    }
    return results;
  }

  /// Settles fund orders queued for the next published NAV.
  List<TradeResult> settleFundNav(
    String symbol,
    double nav, {
    DateTime? now,
  }) {
    final results = <TradeResult>[];
    for (final order in orders.bySymbol(symbol)) {
      if (order.status != OrderStatus.queuedNav) continue;
      results.add(
        _fill(
          order: order,
          instrument: _resolveInstrument(order),
          price: nav,
          timestamp: (now ?? DateTime.now()).toUtc(),
        ),
      );
    }
    return results;
  }

  /// Cancels a working order.
  TradeResult cancel(String orderId, {DateTime? now}) {
    final order = orders.get(orderId);
    final timestamp = (now ?? DateTime.now()).toUtc();
    if (order == null) {
      throw StateError('Unknown order $orderId');
    }
    if (!order.status.isWorking) return TradeResult(order: order);

    final cancelled =
        order.copyWith(status: OrderStatus.cancelled, updatedAt: timestamp);
    orders.upsert(cancelled);
    return TradeResult(order: cancelled);
  }

  List<Order> workingOrders() => orders.working();

  /// Credits bond coupons that have come due since the last credit.
  /// Returns the number of coupon payments written to the ledger.
  int creditDueCoupons({required DateTime asOf, DateTime? now}) {
    final timestamp = (now ?? asOf).toUtc();
    final state = snapshot();
    var credited = 0;

    for (final position in state.openPositions) {
      if (position.assetClass != AssetClass.bond || position.quantity <= 0) {
        continue;
      }
      final details = instruments.bondDetails(position.symbol);
      if (details?.couponRate == null || details?.maturityDate == null) continue;

      final maturity = BondMath.parseDateUtc(details!.maturityDate);
      if (maturity == null) continue;

      final frequency = details.couponFrequency ?? 2;
      final par = details.parValue ?? 100;
      final after = _lastCreditedCouponDate(position.symbol) ??
          _firstAcquisitionDate(position.symbol) ??
          maturity;
      if (!after.isBefore(asOf)) continue;

      final dates = BondMath.couponDatesInRange(
        maturity: maturity,
        paymentsPerYear: frequency,
        after: after,
        until: asOf,
      );

      for (final date in dates) {
        if (_isCouponCredited(position.symbol, date)) continue;
        final perUnit = par * details.couponRate! / frequency;
        final amount = perUnit * position.quantity;
        _creditCoupon(position.symbol, date, amount, timestamp);
        credited++;
      }
    }

    if (credited > 0) rebuildCache();
    return credited;
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  /// The instrument for an order, falling back to a minimal descriptor when the
  /// catalog has no entry (e.g. an order for an unseeded symbol).
  Instrument _resolveInstrument(Order order) {
    return instruments.get(order.symbol) ??
        Instrument(
          symbol: order.symbol,
          name: order.symbol,
          assetClass: order.assetClass,
        );
  }

  bool _shouldExecute(Order order, Quote quote) {
    switch (order.type) {
      case OrderType.market:
        return true;
      case OrderType.limit:
        final limit = order.limitPrice;
        if (limit == null) return false;
        return order.side == OrderSide.buy
            ? quote.price <= limit
            : quote.price >= limit;
      case OrderType.stop:
        final stop = order.stopPrice;
        if (stop == null) return false;
        return order.side == OrderSide.buy
            ? quote.price >= stop
            : quote.price <= stop;
    }
  }

  /// Applies slippage/fees/bond accrual, validates buying power, and writes the
  /// fill to the ledger.
  TradeResult _fill({
    required Order order,
    required Instrument instrument,
    required double price,
    required DateTime timestamp,
  }) {
    final assetClass = instrument.assetClass;
    final cleanPrice = FeeModel.withSlippage(price, assetClass, order.side);

    var accrued = 0.0;
    if (assetClass == AssetClass.bond) {
      final details = instruments.bondDetails(order.symbol);
      final maturity = BondMath.parseDateUtc(details?.maturityDate);
      if (details != null && maturity != null && details.couponRate != null) {
        accrued = BondMath.accruedAt(
          asOf: timestamp,
          maturity: maturity,
          parValue: details.parValue ?? 100,
          annualCouponRate: details.couponRate!,
          paymentsPerYear: details.couponFrequency ?? 2,
        );
      }
    }

    final dirtyPrice = cleanPrice + accrued;
    final notional = order.quantity * dirtyPrice;
    final fee = FeeModel.commission(notional, assetClass);
    final cashDelta =
        order.side == OrderSide.buy ? -(notional + fee) : (notional - fee);

    // --- Risk checks ---
    if (order.side == OrderSide.buy) {
      final available = ledger.cashBalance();
      if (notional + fee > available + 1e-6) {
        return _rejectOrder(
          order: order,
          timestamp: timestamp,
          reason: 'Insufficient buying power '
              '(${notional + fee} required, $available available)',
        );
      }
    } else {
      final held =
          positions.get(order.accountId, order.symbol)?.quantity ?? 0.0;
      if (order.quantity > held + 1e-9) {
        return _rejectOrder(
          order: order,
          timestamp: timestamp,
          reason: 'Insufficient position to sell '
              '(${order.quantity} requested, $held held)',
        );
      }
    }

    final event = LedgerEvent(
      eventId: Ids.uuidV7(now: timestamp),
      hlcTimestamp: timestamp.toIso8601String(),
      deviceId: currentDeviceId(),
      eventType:
          order.side == OrderSide.buy ? EventType.buy : EventType.sell,
      symbol: order.symbol,
      assetClass: assetClass.wire,
      quantity: order.quantity,
      // For bonds the ledger stores the clean price; accrual is separate.
      executionPrice: cleanPrice,
      accruedInterest: accrued,
      fee: fee,
      currency: instrument.currency,
    );
    ledger.append(event);

    final filled = order.copyWith(
      status: OrderStatus.filled,
      updatedAt: timestamp,
      filledEventId: event.eventId,
    );
    orders.upsert(filled);
    rebuildCache(accountId: order.accountId);

    return TradeResult(
      order: filled,
      event: event,
      executionPrice: cleanPrice,
      fee: fee,
      accruedInterest: accrued,
      cashDelta: cashDelta,
    );
  }

  TradeResult _reject({
    required String orderId,
    required String accountId,
    required Instrument instrument,
    required OrderSide side,
    required OrderType type,
    required double quantity,
    required double? limitPrice,
    required double? stopPrice,
    required DateTime timestamp,
    required String reason,
  }) {
    final order = Order(
      orderId: orderId,
      accountId: accountId,
      symbol: instrument.symbol,
      assetClass: instrument.assetClass,
      side: side,
      type: type,
      quantity: quantity,
      limitPrice: limitPrice,
      stopPrice: stopPrice,
      status: OrderStatus.rejected,
      createdAt: timestamp,
      updatedAt: timestamp,
      note: reason,
    );
    orders.upsert(order);
    return TradeResult(order: order, rejectionReason: reason);
  }

  TradeResult _rejectOrder({
    required Order order,
    required DateTime timestamp,
    required String reason,
  }) {
    final rejected =
        order.copyWith(status: OrderStatus.rejected, updatedAt: timestamp, note: reason);
    orders.upsert(rejected);
    return TradeResult(order: rejected, rejectionReason: reason);
  }

  // --- Bond coupon bookkeeping ---

  void _creditCoupon(
    String symbol,
    DateTime couponDate,
    double amount,
    DateTime timestamp,
  ) {
    final event = LedgerEvent(
      eventId: Ids.uuidV7(now: timestamp),
      hlcTimestamp: timestamp.toIso8601String(),
      deviceId: currentDeviceId(),
      eventType: EventType.bondCoupon,
      symbol: symbol,
      assetClass: AssetClass.bond.wire,
      quantity: amount,
    );
    ledger.append(event);
    database.raw.execute(
      'INSERT INTO bond_coupon_credits(symbol, coupon_date, event_id, credited_at) '
      'VALUES(?, ?, ?, ?);',
      [
        symbol,
        _isoDate(couponDate),
        event.eventId,
        timestamp.toIso8601String(),
      ],
    );
  }

  bool _isCouponCredited(String symbol, DateTime couponDate) {
    final rows = database.raw.select(
      'SELECT 1 FROM bond_coupon_credits WHERE symbol = ? AND coupon_date = ?;',
      [symbol, _isoDate(couponDate)],
    );
    return rows.isNotEmpty;
  }

  DateTime? _lastCreditedCouponDate(String symbol) {
    final rows = database.raw.select(
      'SELECT max(coupon_date) AS d FROM bond_coupon_credits WHERE symbol = ?;',
      [symbol],
    );
    final value = rows.first['d'];
    if (value == null) return null;
    return BondMath.parseDateUtc(value as String);
  }

  DateTime? _firstAcquisitionDate(String symbol) {
    final rows = database.raw.select(
      'SELECT min(hlc_timestamp) AS t FROM ledger_events '
      "WHERE symbol = ? AND event_type = 'BUY';",
      [symbol],
    );
    final value = rows.first['t'];
    if (value == null) return null;
    return BondMath.parseDateUtc(value as String);
  }

  static String _isoDate(DateTime date) {
    final utc = date.toUtc();
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    return '${utc.year}-$month-$day';
  }
}
