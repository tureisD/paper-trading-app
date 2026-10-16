import 'package:sqlite3/sqlite3.dart';

/// A point-in-time market quote for an instrument.
class Quote {
  const Quote({
    required this.symbol,
    required this.price,
    required this.asOf,
    required this.source,
    this.previousClose,
    this.change,
    this.changePercent,
    this.currency = 'USD',
  });

  final String symbol;
  final double price;
  final double? previousClose;
  final double? change;
  final double? changePercent;
  final String currency;
  final DateTime asOf;
  final String source;

  /// Builds a quote, deriving change metrics from `previousClose` when absent.
  factory Quote.derive({
    required String symbol,
    required double price,
    required String source,
    required DateTime asOf,
    double? previousClose,
    double? change,
    double? changePercent,
    String currency = 'USD',
  }) {
    var resolvedChange = change;
    var resolvedPercent = changePercent;
    if (previousClose != null && previousClose != 0) {
      resolvedChange ??= price - previousClose;
      resolvedPercent ??= (resolvedChange / previousClose) * 100;
    }
    return Quote(
      symbol: symbol,
      price: price,
      previousClose: previousClose,
      change: resolvedChange,
      changePercent: resolvedPercent,
      currency: currency,
      asOf: asOf,
      source: source,
    );
  }

  factory Quote.fromRow(Row row) => Quote(
        symbol: row['symbol'] as String,
        price: (row['price'] as num).toDouble(),
        previousClose: (row['previous_close'] as num?)?.toDouble(),
        change: (row['change'] as num?)?.toDouble(),
        changePercent: (row['change_percent'] as num?)?.toDouble(),
        currency: (row['currency'] as String?) ?? 'USD',
        asOf: DateTime.parse(row['as_of'] as String),
        source: row['source'] as String,
      );

  List<Object?> toSqlParams() => <Object?>[
        symbol,
        price,
        previousClose,
        change,
        changePercent,
        currency,
        asOf.toUtc().toIso8601String(),
        source,
      ];
}
