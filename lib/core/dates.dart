/// Date helpers shared across providers and the trading engine.
library;

/// Parses a date (`yyyy-MM-dd`) or ISO timestamp as **UTC**, ignoring any time
/// component.
///
/// `DateTime.parse('2030-01-15')` yields a *local* DateTime, which shifts the
/// date by a day west of UTC. Any date that feeds a schedule, a coupon period or
/// a comparison must go through here instead.
DateTime? parseDateUtc(String? value) {
  if (value == null || value.isEmpty) return null;
  final parts = value.split('T').first.split('-');
  if (parts.length != 3) return DateTime.tryParse(value)?.toUtc();
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  return DateTime.utc(year, month, day);
}

/// Parses a nullable ISO-8601 timestamp as UTC.
DateTime? parseInstantUtc(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
}

/// `yyyy-MM-dd` key for a UTC instant.
String dateKeyUtc(DateTime at) {
  final utc = at.toUtc();
  final month = utc.month.toString().padLeft(2, '0');
  final day = utc.day.toString().padLeft(2, '0');
  return '${utc.year}-$month-$day';
}
