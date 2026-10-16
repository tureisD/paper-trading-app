import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paper_trading_app/data/app_database.dart';
import 'package:paper_trading_app/data/ledger_repository.dart';
import 'package:paper_trading_app/market/asset_class.dart';
import 'package:paper_trading_app/market/instrument_repository.dart';
import 'package:paper_trading_app/market/models/instrument.dart';
import 'package:paper_trading_app/market/models/quote.dart';
import 'package:paper_trading_app/sync/gist_client.dart';
import 'package:paper_trading_app/sync/sync_config_store.dart';
import 'package:paper_trading_app/sync/sync_engine.dart';
import 'package:paper_trading_app/trading/order.dart';
import 'package:paper_trading_app/trading/pending_order_repository.dart';
import 'package:paper_trading_app/trading/position_repository.dart';
import 'package:paper_trading_app/trading/trading_engine.dart';

/// Live smoke test against the real GitHub Gist API.
///
/// Not auto-discovered by `flutter test`; run explicitly with a token:
///
///   TB_GIST_TOKEN=... flutter test test/sync_smoke.dart
///
/// Creates a temporary *secret* gist, exercises a two-device round-trip, then
/// deletes it.
void main() {
  final token = Platform.environment['TB_GIST_TOKEN'];
  final enabled = token != null && token.isNotEmpty;

  test(
    'two devices converge through a real gist vault',
    skip: !enabled,
    () async {
      final client = GistClient(token: token!);
      final a = _Device('smoke_a', 'windows_desktop');
      final b = _Device('smoke_b', 'android_mobile');
      addTearDown(() {
        a.dispose();
        b.dispose();
      });

      String? gistId;
      try {
        final aEngine = a.sync('smoke_a', client);
        final connect = await aEngine.connect(token: token);
        expect(connect.ok, isTrue, reason: connect.message);

        final id = a.config.gistId!;
        gistId = id;
        // ignore: avoid_print
        print('created temporary gist: $id');

        // Device A funds the account and pushes.
        a.ledger.append(
          a.ledger.deposit(amount: 100000, at: DateTime.utc(2026, 2, 1)),
        );
        expect((await aEngine.syncNow()).ok, isTrue);

        // Device B links and pulls the deposit.
        final bEngine = b.sync('smoke_b', client);
        final link = await bEngine.connect(token: token, gistId: id);
        expect(link.ok, isTrue, reason: link.message);
        expect(b.engine.snapshot().cash, closeTo(100000, 1e-6));

        // Device B trades on the synced cash.
        const apple = Instrument(
          symbol: 'AAPL',
          name: 'Apple Inc.',
          assetClass: AssetClass.stock,
        );
        b.instruments.upsert(apple);
        final buy = b.engine.submit(
          instrument: apple,
          side: OrderSide.buy,
          type: OrderType.market,
          quantity: 4,
          quote: Quote.derive(
            symbol: 'AAPL',
            price: 210,
            source: 'smoke',
            asOf: DateTime.utc(2026, 2, 1),
          ),
          now: DateTime.utc(2026, 2, 1, 10),
        );
        expect(buy.isFilled, isTrue);
        expect((await bEngine.syncNow()).ok, isTrue);

        // Device A pulls the fill and converges.
        expect((await aEngine.syncNow()).ok, isTrue);

        final aState = a.engine.snapshot();
        final bState = b.engine.snapshot();
        expect(aState.cash, closeTo(bState.cash, 1e-6));
        expect(
          aState.positions['AAPL']!.quantity,
          closeTo(bState.positions['AAPL']!.quantity, 1e-9),
        );
        expect(a.ledger.all().length, b.ledger.all().length);

        // The vault contains both devices' shards plus meta.
        final gist = await client.getGist(id);
        // ignore: avoid_print
        print('vault files: ${gist.files.keys.toList()..sort()}');
        expect(gist.files.keys.where((n) => n.endsWith('.ndjson')).length, 2);
        expect(gist.files.containsKey('meta.json'), isTrue);
      } finally {
        if (gistId != null) {
          await client.deleteGist(gistId);
          // ignore: avoid_print
          print('deleted temporary gist: $gistId');
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

class _Device {
  _Device(this.deviceId, this.platformDevice) {
    db = AppDatabase.inMemory();
    ledger = LedgerRepository(db, deviceId: platformDevice);
    instruments = InstrumentRepository(db);
    engine = TradingEngine(
      database: db,
      ledger: ledger,
      orders: PendingOrderRepository(db),
      positions: PositionRepository(db),
      instruments: instruments,
    );
    config = SyncConfigStore(db);
  }

  final String deviceId;
  final String platformDevice;
  late final AppDatabase db;
  late final LedgerRepository ledger;
  late final InstrumentRepository instruments;
  late final TradingEngine engine;
  late final SyncConfigStore config;

  SyncEngine sync(String id, GistClient client) => SyncEngine(
        database: db,
        ledger: ledger,
        config: config,
        deviceId: platformDevice,
        clientFactory: (_) => client,
        onMerged: engine.rebuildCache,
      );

  void dispose() => db.close();
}
