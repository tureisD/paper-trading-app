/// Supported asset classes.
enum AssetClass {
  stock('STOCK', 'Stocks'),
  etf('ETF', 'ETFs'),
  fund('FUND', 'Funds'),
  crypto('CRYPTO', 'Crypto'),
  bond('BOND', 'Bonds');

  const AssetClass(this.wire, this.label);

  /// Value persisted in SQLite and sent over the wire.
  final String wire;

  /// Human-readable plural label for filter pills.
  final String label;

  static AssetClass fromWire(String value) {
    return values.firstWhere(
      (c) => c.wire == value.toUpperCase(),
      orElse: () => AssetClass.stock,
    );
  }

  static AssetClass? tryParse(String? value) {
    if (value == null) return null;
    final upper = value.toUpperCase();
    for (final c in values) {
      if (c.wire == upper) return c;
    }
    return null;
  }
}
