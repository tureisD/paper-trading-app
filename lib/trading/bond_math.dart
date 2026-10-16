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

  static int daysBetween(DateTime from, DateTime to) =>
      to.toUtc().difference(from.toUtc()).inDays;

  /// Parses a date (or ISO timestamp) as UTC, ignoring any time component.
  ///
  /// Critical: `DateTime.parse('2030-01-15')` yields a *local* DateTime, which
  /// shifts the date by a day west of UTC. Coupon schedules must be UTC-stable.
  static DateTime? parseDateUtc(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.split('T').first.split('-');
    if (parts.length != 3) return DateTime.tryParse(value)?.toUtc();
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime.utc(year, month, day);
  }

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
