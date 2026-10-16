import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper_trading_app/data/app_database.dart';
import 'package:paper_trading_app/data/ledger_repository.dart';
import 'package:paper_trading_app/design/app_theme.dart';
import 'package:paper_trading_app/features/home/home_shell.dart';
import 'package:paper_trading_app/market/asset_class.dart';
import 'package:paper_trading_app/market/instrument_repository.dart';
import 'package:paper_trading_app/market/market_data_service.dart';
import 'package:paper_trading_app/market/models/instrument.dart';
import 'package:paper_trading_app/market/models/quote.dart';
import 'package:paper_trading_app/market/quote_repository.dart';
import 'package:paper_trading_app/sync/sync_config_store.dart';
import 'package:paper_trading_app/sync/sync_engine.dart';
import 'package:paper_trading_app/trading/account_repository.dart';
import 'package:paper_trading_app/trading/order.dart';
import 'package:paper_trading_app/trading/pending_order_repository.dart';
import 'package:paper_trading_app/trading/position_repository.dart';
import 'package:paper_trading_app/trading/trading_engine.dart';

/// Dev utility: renders the app offscreen to a PNG for design review.
///
/// Disabled by default so it never slows down or writes files during normal
/// runs. Enable explicitly:
///
///   RENDER_SCREENSHOTS=1 flutter test test/render_screenshots_test.dart
void main() {
  final enabled = Platform.environment['RENDER_SCREENSHOTS'] == '1';

  testWidgets(
    'renders the portfolio tab with open positions',
    skip: !enabled,
    (tester) async {
      await _loadBrandFonts();

      tester.view.devicePixelRatio = 1.0;
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

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
      );
      AccountRepository(db).ensureDefault();

      const apple = Instrument(
        symbol: 'AAPL',
        name: 'Apple Inc.',
        assetClass: AssetClass.stock,
        isin: 'US0378331005',
        provider: 'yahoo',
      );
      const bitcoin = Instrument(
        symbol: 'BTC-USD',
        name: 'Bitcoin',
        assetClass: AssetClass.crypto,
        provider: 'binance',
        providerSymbol: 'BTCUSDT',
      );
      instruments.upsertAll([apple, bitcoin]);

      ledger.append(ledger.deposit(amount: 100000, at: DateTime.utc(2026, 1, 1, 9)));
      engine.submit(
        instrument: apple,
        side: OrderSide.buy,
        type: OrderType.market,
        quantity: 10,
        quote: _quote('AAPL', 345),
        now: DateTime.utc(2026, 1, 1, 10),
      );
      engine.submit(
        instrument: bitcoin,
        side: OrderSide.buy,
        type: OrderType.market,
        quantity: 0.5,
        quote: _quote('BTC-USD', 65000),
        now: DateTime.utc(2026, 1, 1, 11),
      );
      engine.submit(
        instrument: apple,
        side: OrderSide.sell,
        type: OrderType.market,
        quantity: 2,
        quote: _quote('AAPL', 350),
        now: DateTime.utc(2026, 1, 1, 12),
      );
      quotes.saveAll([
        _quote('AAPL', 350),
        _quote('BTC-USD', 65000),
      ]);

      final syncConfig = SyncConfigStore(db);
      syncConfig.gistId = 'a1b2c3d4e5f6071829304b5c6d7e8f90';

      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark(),
            home: HomeShell(
              database: db,
              databasePath: r'C:\Users\Dmitry Koryakin\AppData\Roaming\PaperTradingApp\paper_trading.db',
              ledger: ledger,
              instruments: instruments,
              quotes: quotes,
              // No providers: keeps the render offline (no http clients).
              marketData: MarketDataService(
                instruments: instruments,
                quotes: quotes,
                providers: const [],
              ),
              engine: engine,
              positions: positions,
              accountId: AccountRepository.defaultAccountId,
              syncEngine: SyncEngine(
                database: db,
                ledger: ledger,
                config: syncConfig,
                deviceId: 'windows_desktop',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      final out = Platform.environment['RENDER_OUT'] ??
          r'C:\Users\Dmitry Koryakin\AppData\Local\Temp\opencode\phase3_portfolio.png';
      File(out).writeAsBytesSync(bytes!.buffer.asUint8List());
      // ignore: avoid_print
      print('rendered -> $out');
    },
  );
}

Quote _quote(String symbol, double price) => Quote.derive(
      symbol: symbol,
      price: price,
      source: 'screenshot',
      asOf: DateTime.utc(2026, 1, 1, 12),
    );

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
