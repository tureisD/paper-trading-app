import 'dart:math' as math;

import '../core/dates.dart' as dates;

/// Fixed-income mathematics (roadmap section 4.3).
class BondMath {
  const BondMath._();

  /// Accrued interest earned since the last coupon date.
  ///
  /// AI = (C / m) * (daysElapsed / daysInPeriod)
  static double accruedInterest({
    required double parValue,
    required double annualCouponRate,
    required int paymentsPerYear,
    required int daysElapsed,
    required int daysInPeriod,
  }) {
    if (paymentsPerYear <= 0 || daysInPeriod <= 0) return 0;
    final periodicCoupon = parValue * annualCouponRate / paymentsPerYear;
    final fraction = (daysElapsed / daysInPeriod).clamp(0.0, 1.0);
    return periodicCoupon * fraction;
  }

  /// Dirty (invoice) price = clean price + accrued interest.
  static double dirtyPrice(double cleanPrice, double accruedInterest) =>
      cleanPrice + accruedInterest;

  /// Clean price from a dirty price.
  static double cleanPrice(double dirtyPrice, double accruedInterest) =>
      dirtyPrice - accruedInterest;

  /// Present value of a fixed-rate bond's remaining cash flows.
  static double priceFromYield({
    required double parValue,
    required double annualCouponRate,
    required int paymentsPerYear,
    required double annualYield,
    required int periodsToMaturity,
  }) {
    if (paymentsPerYear <= 0 || periodsToMaturity <= 0) return parValue;
    final coupon = parValue * annualCouponRate / paymentsPerYear;
    final rate = annualYield / paymentsPerYear;
    var presentValue = 0.0;
    for (var k = 1; k <= periodsToMaturity; k++) {
      presentValue += coupon / math.pow(1 + rate, k);
    }
    presentValue += parValue / math.pow(1 + rate, periodsToMaturity);
    return presentValue;
  }

  /// Yield to maturity implied by a price, via bisection.
  static double? yieldToMaturity({
    required double price,
    required double parValue,
    required double annualCouponRate,
    required int paymentsPerYear,
    required int periodsToMaturity,
    double low = -0.9,
    double high = 5.0,
  }) {
    if (paymentsPerYear <= 0 || periodsToMaturity <= 0) return null;

    double residual(double yield) =>
        priceFromYield(
          parValue: parValue,
          annualCouponRate: annualCouponRate,
          paymentsPerYear: paymentsPerYear,
          annualYield: yield,
          periodsToMaturity: periodsToMaturity,
        ) -
        price;

    var lo = low;
    var hi = high;
    var fLo = residual(lo);
    final fHi = residual(hi);
    if (fLo * fHi > 0) return null; // No sign change: not solvable here.

    for (var i = 0; i < 200; i++) {
      final mid = (lo + hi) / 2;
      final fMid = residual(mid);
      if (fMid.abs() < 1e-10) return mid;
      if (fLo * fMid <= 0) {
        hi = mid;
      } else {
        lo = mid;
        fLo = fMid;
      }
    }
    return (lo + hi) / 2;
  }

  /// Macaulay duration in years.
  static double macaulayDuration({
    required double parValue,
    required double annualCouponRate,
    required int paymentsPerYear,
    required double annualYield,
    required int periodsToMaturity,
  }) {
    if (paymentsPerYear <= 0 || periodsToMaturity <= 0) return 0;
    final price = priceFromYield(
      parValue: parValue,
      annualCouponRate: annualCouponRate,
      paymentsPerYear: paymentsPerYear,
      annualYield: annualYield,
      periodsToMaturity: periodsToMaturity,
    );
    if (price == 0) return 0;

    final coupon = parValue * annualCouponRate / paymentsPerYear;
    final rate = annualYield / paymentsPerYear;
    var weighted = 0.0;
    for (var k = 1; k <= periodsToMaturity; k++) {
      weighted +=
          (k / paymentsPerYear) * (coupon / math.pow(1 + rate, k));
    }
    weighted += (periodsToMaturity / paymentsPerYear) *
        (parValue / math.pow(1 + rate, periodsToMaturity));
    return weighted / price;
  }

  /// Modified duration in years: Macaulay / (1 + y/m).
  ///
  /// Approximates the percentage price change per unit yield shift.
  static double modifiedDuration({
    required double parValue,
    required double annualCouponRate,
    required int paymentsPerYear,
    required double annualYield,
    required int periodsToMaturity,
  }) {
    if (paymentsPerYear <= 0) return 0;
    final macaulay = macaulayDuration(
      parValue: parValue,
      annualCouponRate: annualCouponRate,
      paymentsPerYear: paymentsPerYear,
      annualYield: annualYield,
      periodsToMaturity: periodsToMaturity,
    );
    return macaulay / (1 + annualYield / paymentsPerYear);
  }

  static int daysBetween(DateTime from, DateTime to) =>
      to.toUtc().difference(from.toUtc()).inDays;

  /// Parses a date (or ISO timestamp) as UTC, ignoring any time component.
  ///
  /// Critical: `DateTime.parse('2030-01-15')` yields a *local* DateTime, which
  /// shifts the date by a day west of UTC. Coupon schedules must be UTC-stable.
  static DateTime? parseDateUtc(String? value) => dates.parseDateUtc(value);

  /// Coupon dates in the half-open range `(after, until]`, oldest first.
  static List<DateTime> couponDatesInRange({
    required DateTime maturity,
    required int paymentsPerYear,
    required DateTime after,
    required DateTime until,
  }) {
    if (paymentsPerYear <= 0) return const [];
    final months = 12 ~/ paymentsPerYear;
    if (months <= 0) return const [];

    final dates = <DateTime>[];
    var date = _dateOnly(maturity);
    final lower = _dateOnly(after);
    final upper = _dateOnly(until);

    // Walk backwards from maturity, collecting dates in (lower, upper].
    var guard = 0;
    while (date.isAfter(lower) && guard++ < 2000) {
      if (!date.isAfter(upper)) dates.add(date);
      date = addMonths(date, -months);
    }
    dates.sort();
    return dates;
  }

  /// The coupon period containing [asOf]: the previous (or on) coupon date and
  /// the next one.
  static ({DateTime previous, DateTime next}) couponPeriod({
    required DateTime asOf,
    required DateTime maturity,
    required int paymentsPerYear,
  }) {
    final months = 12 ~/ paymentsPerYear;
    final target = _dateOnly(asOf);
    var next = _dateOnly(maturity);
    var previous = addMonths(next, -months);

    var guard = 0;
    while (previous.isAfter(target) && guard++ < 2000) {
      next = previous;
      previous = addMonths(previous, -months);
    }
    return (previous: previous, next: next);
  }

  /// Accrued interest for a point in time, given the bond's terms.
  static double accruedAt({
    required DateTime asOf,
    required DateTime maturity,
    required double parValue,
    required double annualCouponRate,
    required int paymentsPerYear,
  }) {
    final period = couponPeriod(
      asOf: asOf,
      maturity: maturity,
      paymentsPerYear: paymentsPerYear,
    );
    final daysElapsed = daysBetween(period.previous, asOf);
    final daysInPeriod = daysBetween(period.previous, period.next);
    return accruedInterest(
      parValue: parValue,
      annualCouponRate: annualCouponRate,
      paymentsPerYear: paymentsPerYear,
      daysElapsed: daysElapsed,
      daysInPeriod: daysInPeriod,
    );
  }

  /// Adds [delta] months, clamping the day to the target month's length.
  static DateTime addMonths(DateTime date, int delta) {
    final totalMonths = date.year * 12 + (date.month - 1) + delta;
    final year = totalMonths ~/ 12;
    final month = totalMonths % 12 + 1;
    final lastDay = DateTime.utc(year, month + 1, 0).day;
    final day = date.day <= lastDay ? date.day : lastDay;
    return DateTime.utc(year, month, day);
  }

  static DateTime _dateOnly(DateTime d) =>
      DateTime.utc(d.toUtc().year, d.toUtc().month, d.toUtc().day);
}
