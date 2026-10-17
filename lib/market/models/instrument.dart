import 'package:sqlite3/sqlite3.dart';

import '../asset_class.dart';

/// A tradable instrument in the local catalog.
class Instrument {
  const Instrument({
    required this.symbol,
    required this.name,
    required this.assetClass,
    this.exchange,
    this.currency = 'USD',
    this.isin,
    this.cusip,
    this.provider,
    this.providerSymbol,
    this.expenseRatio,
  });

  /// Canonical local symbol, e.g. `AAPL`, `BTC-USD`, `DGS10`.
  final String symbol;
  final String name;
  final AssetClass assetClass;
  final String? exchange;
  final String currency;
  final String? isin;
  final String? cusip;

  /// Market-data provider id that serves live data for this instrument.
  final String? provider;

  /// Provider-specific symbol (e.g. Binance `BTCUSDT`, FRED `DGS10`).
  final String? providerSymbol;

  /// Annual expense ratio as a percentage (ETFs and funds only).
  final double? expenseRatio;

  factory Instrument.fromRow(Row row) {
    return Instrument(
      symbol: row['symbol'] as String,
      name: row['name'] as String,
      assetClass: AssetClass.fromWire(row['asset_class'] as String),
      exchange: row['exchange'] as String?,
      currency: (row['currency'] as String?) ?? 'USD',
      isin: row['isin'] as String?,
      cusip: row['cusip'] as String?,
      provider: row['provider'] as String?,
      providerSymbol: row['provider_symbol'] as String?,
      expenseRatio: (row['expense_ratio'] as num?)?.toDouble(),
    );
  }

  List<Object?> toSqlParams() => <Object?>[
        symbol,
        name,
        assetClass.wire,
        exchange,
        currency,
        isin,
        cusip,
        provider,
        providerSymbol,
        expenseRatio,
      ];

  Map<String, dynamic> toJson() => <String, dynamic>{
        'symbol': symbol,
        'name': name,
        'assetClass': assetClass.wire,
        if (exchange != null) 'exchange': exchange,
        'currency': currency,
        if (isin != null) 'isin': isin,
        if (cusip != null) 'cusip': cusip,
        if (provider != null) 'provider': provider,
        if (providerSymbol != null) 'providerSymbol': providerSymbol,
        if (expenseRatio != null) 'expenseRatio': expenseRatio,
      };

  static Instrument fromJson(Map<String, dynamic> json) => Instrument(
        symbol: json['symbol'] as String,
        name: json['name'] as String,
        assetClass: AssetClass.fromWire(json['assetClass'] as String),
        exchange: json['exchange'] as String?,
        currency: (json['currency'] as String?) ?? 'USD',
        isin: json['isin'] as String?,
        cusip: json['cusip'] as String?,
        provider: json['provider'] as String?,
        providerSymbol: json['providerSymbol'] as String?,
        expenseRatio: (json['expenseRatio'] as num?)?.toDouble(),
      );
}

/// Fixed-income reference data (roadmap section 2, phase 3).
class BondDetails {
  const BondDetails({
    required this.symbol,
    this.couponRate,
    this.maturityDate,
    this.parValue,
    this.couponFrequency,
    this.dayCount,
  });

  final String symbol;
  final double? couponRate;
  final String? maturityDate;
  final double? parValue;
  final int? couponFrequency;
  final String? dayCount;

  factory BondDetails.fromRow(Row row) => BondDetails(
        symbol: row['symbol'] as String,
        couponRate: (row['coupon_rate'] as num?)?.toDouble(),
        maturityDate: row['maturity_date'] as String?,
        parValue: (row['par_value'] as num?)?.toDouble(),
        couponFrequency: (row['coupon_frequency'] as int?),
        dayCount: row['day_count'] as String?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'symbol': symbol,
        if (couponRate != null) 'couponRate': couponRate,
        if (maturityDate != null) 'maturityDate': maturityDate,
        if (parValue != null) 'parValue': parValue,
        if (couponFrequency != null) 'couponFrequency': couponFrequency,
        if (dayCount != null) 'dayCount': dayCount,
      };

  static BondDetails fromJson(Map<String, dynamic> json, {String? symbol}) =>
      BondDetails(
        symbol: symbol ?? json['symbol'] as String,
        couponRate: (json['couponRate'] as num?)?.toDouble(),
        maturityDate: json['maturityDate'] as String?,
        parValue: (json['parValue'] as num?)?.toDouble(),
        couponFrequency: json['couponFrequency'] as int?,
        dayCount: json['dayCount'] as String?,
      );
}
