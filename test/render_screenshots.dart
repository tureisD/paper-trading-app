import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper_trading_app/analytics/equity_snapshot_repository.dart';
import 'package:paper_trading_app/data/app_database.dart';
import 'package:paper_trading_app/data/settings_store.dart';
import 'package:paper_trading_app/design/theme_controller.dart';
import 'package:paper_trading_app/data/ledger_repository.dart';
import 'package:paper_trading_app/design/app_theme.dart';
import 'package:paper_trading_app/features/home/home_shell.dart';
import 'package:paper_trading_app/market/asset_class.dart';
import 'package:paper_trading_app/market/instrument_repository.dart';
import 'package:paper_trading_app/market/market_data_service.dart';
import 'package:paper_trading_app/market/models/candle.dart';
import 'package:paper_trading_app/market/models/instrument.dart';
import 'package:paper_trading_app/market/models/quote.dart';
import 'package:paper_trading_app/market/providers/market_data_provider.dart';
import 'package:paper_trading_app/market/quote_repository.dart';
import 'package:paper_trading_app/sync/sync_config_store.dart';
import 'package:paper_trading_app/sync/sync_engine.dart';
import 'package:paper_trading_app/trading/account_repository.dart';
import 'package:paper_trading_app/trading/order.dart';
import 'package:paper_trading_app/trading/pending_order_repository.dart';
import 'package:paper_trading_app/trading/position_repository.dart';
import 'package:paper_trading_app/trading/trading_engine.dart';

/// Dev utility: renders the app offscreen to PNGs for design review.
///
/// Disabled by default so it never slows down or writes files during normal
/// runs. Enable explicitly:
///
///   RENDER_SCREENSHOTS=1 flutter test test/render_screenshots.dart
void main() {
  final enabled = Platform.environment['RENDER_SCREENSHOTS'] == '1';

  testWidgets(
    'renders the portfolio and discovery tabs',
    skip: !enabled,
    (tester) async {
      await _loadBrandFonts();

      final sizeEnv = Platform.environment['RENDER_SIZE'];
      final size = sizeEnv == null
          ? const Size(1280, 720)
          : Size(
              double.parse(sizeEnv.split('x').first),
              double.parse(sizeEnv.split('x').last),
            );
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);

      final db = AppDatabase.inMemory();
      addTearDown(db.close);

      final ledger = LedgerRepository(db);
      final instruments = InstrumentRepository(db);
      final quotes = QuoteRepository(db);
      final positions = PositionRepository(db);
      final engine = TradingEngine(
        database: db,
        ledger: ledger,
        orders: PendingOrderRepository(db),
        positions: positions,
        instruments: instruments,
        accountId: 'default',
      );
      AccountRepository(db).ensureDefault();

      const apple = Instrument(
        symbol: 'AAPL',
        name: 'Apple Inc.',
        assetClass: AssetClass.stock,
        isin: 'US0378331005',
        provider: 'yahoo',
      );
      const microsoft = Instrument(
        symbol: 'MSFT',
        name: 'Microsoft Corporation',
        assetClass: AssetClass.stock,
        exchange: 'NASDAQ',
        isin: 'US5949181045',
        provider: 'yahoo',
      );
      const bitcoin = Instrument(
        symbol: 'BTC-USD',
        name: 'Bitcoin',
        assetClass: AssetClass.crypto,
        provider: 'binance',
        providerSymbol: 'BTCUSDT',
      );
      const spy = Instrument(
        symbol: 'SPY',
        name: 'SPDR S&P 500 ETF Trust',
        assetClass: AssetClass.etf,
        isin: 'US78462F1030',
        provider: 'yahoo',
      );
      const dgs10 = Instrument(
        symbol: 'DGS10',
        name: 'US Treasury 10-Year Yield (CMT)',
        assetClass: AssetClass.bond,
        provider: 'fred',
        providerSymbol: 'DGS10',
      );
      instruments.upsertAll([apple, microsoft, bitcoin, spy, dgs10]);

      ledger.append(
        ledger.deposit(amount: 100000, at: DateTime.utc(2026, 10, 11, 9)),
      );

      void buy(Instrument instrument, double quantity, double price, int day) {
        engine.submit(
          instrument: instrument,
          side: OrderSide.buy,
          type: OrderType.market,
          quantity: quantity,
          quote: _quote(instrument.symbol, price),
          now: DateTime.utc(2026, 10, day, 10),
        );
      }

      buy(apple, 20, 180, 12);
      buy(bitcoin, 0.5, 65000, 13);
      buy(spy, 10, 500, 14);

      engine.submit(
        instrument: apple,
        side: OrderSide.sell,
        type: OrderType.market,
        quantity: 5,
        quote: _quote('AAPL', 200),
        now: DateTime.utc(2026, 10, 15, 10),
      );
      engine.submit(
        instrument: apple,
        side: OrderSide.sell,
        type: OrderType.market,
        quantity: 5,
        quote: _quote('AAPL', 170),
        now: DateTime.utc(2026, 10, 16, 10),
      );

      quotes.saveAll([
        _quote('AAPL', 210, previousClose: 205),
        _quote('BTC-USD', 66000, previousClose: 64000),
        _quote('SPY', 505, previousClose: 502),
        _quote('MSFT', 412, previousClose: 408),
      ]);

      final syncConfig = SyncConfigStore(db);
      syncConfig.gistId = 'a1b2c3d4e5f6071829304b5c6d7e8f90';

      final settings = SettingsStore(db);
      final theme = ThemeController(settings);
      if (Platform.environment['RENDER_THEME'] == 'light') {
        theme.select(ThemeMode.light);
      }

      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark(),
            home: HomeShell(
              database: db,
              databasePath:
                  r'C:\Users\Dmitry Koryakin\AppData\Roaming\PaperTradingApp\paper_trading.db',
              ledger: ledger,
              instruments: instruments,
              quotes: quotes,
              marketData: MarketDataService(
                instruments: instruments,
                quotes: quotes,
                providers: [_FakeProvider()],
              ),
              engine: engine,
              syncEngine: SyncEngine(
                database: db,
                ledger: ledger,
                config: syncConfig,
                deviceId: 'windows_desktop',
              ),
              snapshots: EquitySnapshotRepository(db),
              settings: settings,
              theme: theme,
              accounts: AccountRepository(db),
              accountId: 'default',
              accountName: 'Default portfolio',
              onAccountChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final view = Platform.environment['RENDER_VIEW'] ?? 'portfolio';
      if (view == 'discovery') {
        // Bounded pumps: the tree keeps async work alive, so settle can hang.
        await tester.tap(find.text('DISCOVERY'));
        await _settle(tester);
        await tester.enterText(find.byType(TextField).first, 'msft');
        await _settle(tester);
        await tester.tap(find.text('MSFT'));
        await _settle(tester);
      }

      final out = Platform.environment['RENDER_OUT'] ??
          r'C:\Users\Dmitry Koryakin\AppData\Local\Temp\opencode\screens.png';
      await _capture(tester, boundaryKey, out);
    },
  );
}

/// Advances a few frames without waiting for the tree to go fully quiescent.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String path,
) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1.0);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('rendered -> $path');
}

Quote _quote(String symbol, double price, {double? previousClose}) =>
    Quote.derive(
      symbol: symbol,
      price: price,
      previousClose: previousClose,
      source: 'screenshot',
      asOf: DateTime.utc(2026, 10, 17, 12),
    );

/// Deterministic offline market data so screenshots never touch the network.
class _FakeProvider implements MarketDataProvider {
  @override
  String get id => 'yahoo';

  @override
  Set<AssetClass> get supported => AssetClass.values.toSet();

  @override
  Future<Quote> fetchQuote({
    required String symbol,
    required String providerSymbol,
    String currency = 'USD',
  }) async {
    const marks = <String, double>{
      'AAPL': 210,
      'MSFT': 412,
      'SPY': 505,
      'BTC-USD': 66000,
    };
    final price = marks[symbol] ?? 100;
    return Quote.derive(
      symbol: symbol,
      price: price,
      previousClose: price * 0.99,
      source: 'screenshot',
      asOf: DateTime.utc(2026, 10, 17),
    );
  }

  @override
  Future<List<Candle>> fetchCandles({
    required String providerSymbol,
    String interval = '1d',
    int limit = 90,
  }) async {
    final now = DateTime.utc(2026, 10, 17);
    final candles = <Candle>[];
    var price = 392.0;
    for (var i = limit; i > 0; i--) {
      final drift = math.sin(i / 6.5) * 5.5 + math.cos(i / 2.7) * 2.5;
      final open = price;
      final close = price + drift;
      candles.add(
        Candle(
          time: now.subtract(Duration(days: i)),
          open: open,
          high: math.max(open, close) + 1.5 + (i % 4),
          low: math.min(open, close) - 1.2 - (i % 3),
          close: close,
          volume: 1.0e6 + (i % 9) * 1.2e5,
        ),
      );
      price = close;
    }
    return candles;
  }
}

Future<void> _loadBrandFonts() async {
  const fonts = {
    'Inter': 'assets/fonts/Inter-Variable.ttf',
    'JetBrainsMono': 'assets/fonts/JetBrainsMono-Variable.ttf',
  };
  for (final entry in fonts.entries) {
    final loader = FontLoader(entry.key);
    loader.addFont(rootBundle.load(entry.value));
    await loader.load();
  }
}
