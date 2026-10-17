import 'package:flutter_test/flutter_test.dart';
import 'package:paper_trading_app/features/trade/order_ticket.dart';
import 'package:paper_trading_app/market/asset_class.dart';
import 'package:paper_trading_app/market/models/instrument.dart';

const _crypto = Instrument(
  symbol: 'BTC-USD',
  name: 'Bitcoin',
  assetClass: AssetClass.crypto,
);
const _stock = Instrument(
  symbol: 'AAPL',
  name: 'Apple Inc.',
  assetClass: AssetClass.stock,
);

void main() {
  group('order sizing', () {
    test('units mode passes the quantity through', () {
      expect(
        resolveUnits(entry: '2.5', mode: SizeMode.units, price: 100),
        closeTo(2.5, 1e-9),
      );
    });

    test('cash mode converts an amount into units', () {
      expect(
        resolveUnits(entry: '500', mode: SizeMode.cash, price: 100),
        closeTo(5, 1e-9),
      );
    });

    test('cash mode without a price cannot size', () {
      expect(
        resolveUnits(entry: '500', mode: SizeMode.cash, price: null),
        isNull,
      );
    });

    test('rejects non-positive and unparseable sizes', () {
      expect(resolveUnits(entry: '0', mode: SizeMode.units, price: 100), isNull);
      expect(resolveUnits(entry: '-3', mode: SizeMode.units, price: 100), isNull);
      expect(resolveUnits(entry: 'abc', mode: SizeMode.units, price: 100), isNull);
    });

    test('tolerates thousands separators', () {
      expect(
        resolveUnits(entry: '1,000', mode: SizeMode.units, price: 100),
        closeTo(1000, 1e-9),
      );
    });

    test('minimum step follows the asset class precision', () {
      expect(minimumStep(_crypto), 1e-8);
      expect(minimumStep(_stock), 1e-6);
    });
  });
}
