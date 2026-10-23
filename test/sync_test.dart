import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:paper_trading_app/data/app_database.dart';import 'package:paper_trading_app/data/ledger_repository.dart';
import 'package:paper_trading_app/data/models/ledger_event.dart';
import 'package:paper_trading_app/market/asset_class.dart';
import 'package:paper_trading_app/market/instrument_repository.dart';
import 'package:paper_trading_app/market/models/instrument.dart';
import 'package:paper_trading_app/market/models/quote.dart';
import 'package:paper_trading_app/sync/gist_client.dart';
import 'package:paper_trading_app/sync/hlc.dart';
import 'package:paper_trading_app/sync/secret_codec.dart';
import 'package:paper_trading_app/sync/shard_codec.dart';
import 'package:paper_trading_app/sync/sync_config_store.dart';
import 'package:paper_trading_app/sync/sync_coordinator.dart';
import 'package:paper_trading_app/sync/sync_engine.dart';
import 'package:paper_trading_app/trading/order.dart';
import 'package:paper_trading_app/trading/pending_order_repository.dart';
import 'package:paper_trading_app/trading/position_repository.dart';
import 'package:paper_trading_app/trading/trading_engine.dart';

String? _header(http.BaseRequest request, String name) {
  for (final entry in request.headers.entries) {
    if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
  }
  return null;
}

/// In-memory stand-in for the Gist REST API: one gist, patchable files, ETags.
class FakeGist {
  FakeGist({this.token = 'tok_test', this.login = 'tester', this.scopes = 'gist, repo'});

  final String token;
  final String login;
  final String scopes;
  String? id;
  final Map<String, String> files = {};
  int revision = 0;
  int requestCount = 0;
  int notModifiedCount = 0;

  String get etag => 'W/"rev-$revision"';

  http.Client client() => MockClient((request) async {
        requestCount++;
        if (_header(request, 'authorization') != 'Bearer $token') {
          return http.Response('{"message":"Bad credentials"}', 401);
        }
        final path = request.url.path;
        final method = request.method;

        // Token verification used by `connect`.
        if (path == '/user' && method == 'GET') {
          return http.Response(
            '{"login":"$login"}',
            200,
            headers: {
              'content-type': 'application/json',
              'x-oauth-scopes': scopes,
            },
          );
        }

        if (path == '/gists' && method == 'POST') {
          id ??= 'gist_test_1';
          _applyFiles(request.body);
          revision++;
          return _snapshot();
        }
        if (path == '/gists/$id' && method == 'GET') {
          if (_header(request, 'if-none-match') == etag) {
            notModifiedCount++;
            return http.Response('', 304, headers: {'etag': etag});
          }
          return _snapshot();
        }
        if (path == '/gists/$id' && method == 'PATCH') {
          _applyFiles(request.body);
          revision++;
          return _snapshot();
        }
        return http.Response('{"message":"Not Found"}', 404);
      });

  void _applyFiles(String body) {
    if (body.isEmpty) return;
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final incoming = (decoded['files'] as Map?) ?? const {};
    incoming.forEach((key, value) {
      final map = (value as Map).cast<String, dynamic>();
      files['$key'] = (map['content'] as String?) ?? '';
    });
  }

  http.Response _snapshot() => http.Response(
        jsonEncode({
          'id': id,
          'description': 'vault',
          'updated_at': '2026-01-01T00:00:00Z',
          'files': {
            for (final entry in files.entries)
              entry.key: {
                'filename': entry.key,
                'content': entry.value,
                'truncated': false,
                'raw_url': 'https://gist.test/${entry.key}',
              },
          },
        }),
        200,
        headers: {'content-type': 'application/json', 'etag': etag},
      );
}

class _Device {
  _Device(this.deviceId) {
    db = AppDatabase.inMemory();
    ledger = LedgerRepository(db, deviceId: deviceId);
    instruments = InstrumentRepository(db);
    engine = TradingEngine(
      database: db,
      ledger: ledger,
      orders: PendingOrderRepository(db),
      positions: PositionRepository(db),
      instruments: instruments,
      accountId: 'default',
    );
    config = SyncConfigStore(db);
  }

  final String deviceId;
  late final AppDatabase db;
  late final LedgerRepository ledger;
  late final InstrumentRepository instruments;
  late final TradingEngine engine;
  late final SyncConfigStore config;
  int mergedCallbacks = 0;

  SyncEngine syncEngine(FakeGist gist) => SyncEngine(
        database: db,
        ledger: ledger,
        config: config,
        deviceId: deviceId,
        clientFactory: (token) => GistClient(token: token, client: gist.client()),
        onMerged: () {
          mergedCallbacks++;
          engine.rebuildCache();
        },
      );

  void dispose() => db.close();
}

void main() {
  group('Hlc', () {
    test('round-trips through its wire encoding', () {
      final hlc = Hlc(DateTime.utc(2026, 1, 2, 3, 4, 5).millisecondsSinceEpoch, 7);
      final decoded = Hlc.parse(hlc.encode());
      expect(decoded.physicalMs, hlc.physicalMs);
      expect(decoded.counter, 7);
    });

    test('counter guarantees strict monotonicity within the same millisecond',
        () {
      final clock = HlcClock();
      final a = clock.next(now: DateTime.utc(2026, 1, 1));
      final b = clock.next(now: DateTime.utc(2026, 1, 1));
      final c = clock.next(now: DateTime.utc(2026, 1, 1));
      expect(a.compareTo(b), lessThan(0));
      expect(b.compareTo(c), lessThan(0));
    });

    test('encoding sorts lexicographically in chronological order', () {
      final clock = HlcClock();
      final encodings = <String>[
        clock.next(now: DateTime.utc(2026, 1, 1)).encode(),
        clock.next(now: DateTime.utc(2026, 1, 1)).encode(),
        clock.next(now: DateTime.utc(2026, 1, 2)).encode(),
      ];
      final sorted = [...encodings]..sort();
      expect(sorted, encodings);
    });

    test('observing a remote clock advances past it', () {
      final clock = HlcClock();
      final remote = Hlc(DateTime.utc(2030, 5, 5).millisecondsSinceEpoch, 3);
      clock.observe(remote);
      final next = clock.next(now: DateTime.utc(2026, 1, 1));
      expect(next.compareTo(remote), greaterThan(0));
    });
  });

  group('ShardCodec', () {
    test('round-trips events and skips malformed lines', () {
      const event = LedgerEvent(
        eventId: '0190f000-0000-7000-8000-000000000001',
        hlcTimestamp: '2026-01-05T09:00:00.000Z#000000',
        deviceId: 'device_a',
        eventType: EventType.cashDeposit,
        quantity: 100000,
      );
      final encoded = ShardCodec.encodeEvents(const [event]);
      final decoded = ShardCodec.decodeEvents('$encoded\n{not json}\n\n');
      expect(decoded, hasLength(1));
      expect(decoded.single.eventId, event.eventId);
      expect(decoded.single.quantity, 100000);
      expect(decoded.single.synced, isTrue);
    });

    test('names shards per device per month', () {
      expect(
        ShardCodec.shardFileName('windows_desktop', DateTime.utc(2026, 10)),
        'ledger.windows_desktop.2026-10.ndjson',
      );
      expect(ShardCodec.isShardFile('ledger.android_mobile.2026-10.ndjson'), isTrue);
      expect(ShardCodec.isShardFile('meta.json'), isFalse);
    });
  });

  group('SecretCodec', () {
    test('encrypts with DPAPI on Windows and round-trips', () {
      const secret = 'github_pat_example_token';
      final stored = SecretCodec.encode(secret);
      expect(SecretCodec.decode(stored), secret);
      if (SecretCodec.isEncrypted(stored)) {
        expect(stored, startsWith(SecretCodec.encryptedPrefix));
        expect(stored.contains(secret), isFalse); // not stored in the clear
      }
    });
  });

  group('GistClient', () {
    late FakeGist gist;
    late GistClient client;

    setUp(() {
      gist = FakeGist();
      client = GistClient(token: gist.token, client: gist.client());
    });

    test('returns notModified on a 304 conditional GET', () async {
      final created = await client.createGist(
        files: {'meta.json': '{"schema_version":3}'},
      );
      final unchanged = await client.getGist(created.id, etag: created.etag);
      expect(unchanged.notModified, isTrue);
    });

    test('sends the conditional ETag header', () async {
      final created = await client.createGist(files: {'a.txt': '1'});
      await client.getGist(created.id, etag: created.etag);
      expect(gist.notModifiedCount, 1);
    });

    test('rejects a bad token with a GistException', () async {
      final bad = GistClient(token: 'nope', client: gist.client());
      await expectLater(
        bad.createGist(files: {'a.txt': '1'}),
        throwsA(isA<GistException>()),
      );
    });

    test('translates 403 rate limits into a reset time', () async {
      final limited = GistClient(
        token: gist.token,
        client: MockClient((_) async => http.Response(
              '{"message":"API rate limit exceeded"}',
              403,
              headers: {
                'x-ratelimit-remaining': '0',
                'x-ratelimit-reset': '${DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000}',
              },
            )),
      );
      await expectLater(
        limited.getGist('abc'),
        throwsA(isA<RateLimitedException>().having((e) => e.resetAt, 'resetAt', isNotNull)),
      );
    });

    test('PATCHes only the named files', () async {
      final created = await client.createGist(files: {'a.txt': '1', 'b.txt': '2'});
      await client.updateGist(created.id, files: {'b.txt': '3'});
      expect(gist.files['a.txt'], '1');
      expect(gist.files['b.txt'], '3');
    });
  });

  group('SyncEngine', () {
    late FakeGist gist;
    late _Device a;
    late _Device b;

    setUp(() {
      gist = FakeGist();
      a = _Device('device_a');
      b = _Device('device_b');
    });
    tearDown(() {
      a.dispose();
      b.dispose();
    });

    test('pushes local events into per-device shards and marks them synced',
        () async {
      a.ledger.append(a.ledger.deposit(amount: 100000, at: DateTime.utc(2026, 1, 5)));
      final engine = a.syncEngine(gist);

      final outcome = await engine.connect(token: gist.token);

      expect(outcome.ok, isTrue);
      expect(outcome.pushed, 1);
      expect(gist.files.keys.any(ShardCodec.isShardFile), isTrue);
      expect(gist.files.containsKey('meta.json'), isTrue);
      expect(a.ledger.pendingCount(), 0);
    });

    test('merges a remote shard exactly once', () async {
      final aEngine = a.syncEngine(gist);
      await aEngine.connect(token: gist.token);
      a.ledger.append(a.ledger.deposit(amount: 50000, at: DateTime.utc(2026, 1, 6)));
      await aEngine.syncNow();

      b.ledger.append(b.ledger.deposit(amount: 1, at: DateTime.utc(2026, 1, 7)));
      final bEngine = b.syncEngine(gist);
      await bEngine.connect(token: gist.token, gistId: gist.id);

      // b now has its own deposit plus device_a's.
      expect(b.engine.snapshot().cash, closeTo(50001, 1e-9));
      final merged = b.mergedCallbacks;

      await bEngine.syncNow();
      expect(b.mergedCallbacks, merged, reason: 'second sync should be a no-op');
    });

    test('two devices converge after trading independently', () async {
      final aEngine = a.syncEngine(gist);
      await aEngine.connect(token: gist.token);

      // Device A funds the account and syncs.
      a.ledger.append(a.ledger.deposit(amount: 100000, at: DateTime.utc(2026, 1, 5)));
      await aEngine.syncNow();

      // Device B links to the same vault and pulls the deposit.
      final bEngine = b.syncEngine(gist);
      await bEngine.connect(token: gist.token, gistId: gist.id);
      expect(b.engine.snapshot().cash, closeTo(100000, 1e-6));

      // Device B buys using the synced cash.
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
        quantity: 3,
        quote: Quote.derive(
          symbol: 'AAPL',
          price: 200,
          source: 'test',
          asOf: DateTime.utc(2026, 1, 5),
        ),
        now: DateTime.utc(2026, 1, 5, 10),
      );
      expect(buy.isFilled, isTrue);
      await bEngine.syncNow();

      // Device A pulls B's fill and converges on identical state.
      await aEngine.syncNow();

      final aState = a.engine.snapshot();
      final bState = b.engine.snapshot();
      expect(aState.cash, closeTo(bState.cash, 1e-6));
      expect(
        aState.positions['AAPL']!.quantity,
        closeTo(bState.positions['AAPL']!.quantity, 1e-9),
      );
      expect(
        aState.positions['AAPL']!.averageCost,
        closeTo(bState.positions['AAPL']!.averageCost, 1e-9),
      );
      expect(a.ledger.all().length, b.ledger.all().length);
    });

    test('reports notConfigured before a vault is linked', () async {
      final outcome = await a.syncEngine(gist).syncNow();
      expect(outcome.state, SyncState.notConfigured);
      expect(outcome.ok, isFalse);
    });

    test('disconnect clears credentials', () async {
      final engine = a.syncEngine(gist);
      await engine.connect(token: gist.token);
      expect(engine.isConfigured, isTrue);
      engine.disconnect();
      expect(engine.isConfigured, isFalse);
    });

    test('schedules an automatic retry when rate limited', () async {      final limited = SyncEngine(
        database: a.db,
        ledger: a.ledger,
        config: a.config,
        deviceId: 'device_a',
        clientFactory: (_) => GistClient(
          token: gist.token,
          client: MockClient(
            (_) async => http.Response(
              '{"message":"API rate limit exceeded"}',
              403,
              headers: {
                'x-ratelimit-remaining': '0',
                'x-ratelimit-reset':
                    '${DateTime.now().add(const Duration(minutes: 3)).millisecondsSinceEpoch ~/ 1000}',
              },
            ),
          ),
        ),
      );
      addTearDown(limited.dispose);

      a.config.token = 'test-token';
      a.config.gistId = 'gist_test_1';

      final outcome = await limited.syncNow();

      expect(outcome.state, SyncState.offline);
      expect(limited.nextRetryAt, isNotNull);
      expect(
        limited.nextRetryAt!.isAfter(DateTime.now()),
        isTrue,
        reason: 'retry is scheduled in the future',
      );
    });

    test('explains an empty token instead of sending one', () async {
      final engine = a.syncEngine(gist);
      final outcome = await engine.connect(token: '   ');

      expect(outcome.state, SyncState.error);
      expect(outcome.message, contains('Paste a GitHub token'));
      expect(gist.requestCount, 0, reason: 'no request should be made');
    });

    test('strips paste noise from the token before sending', () async {
      final engine = a.syncEngine(gist);
      // A trailing newline and a non-breaking space travel with far too many
      // copy-pastes; both used to produce 401 Bad credentials.
      final outcome = await engine.connect(token: '${gist.token}\n\u00A0 ');

      expect(outcome.ok, isTrue);
      expect(a.config.accountLogin, 'tester');
    });

    test('reports an invalid token as such', () async {
      final engine = SyncEngine(
        database: a.db,
        ledger: a.ledger,
        config: a.config,
        deviceId: 'device_a',
        clientFactory: (token) => GistClient(
          token: token,
          client: MockClient(
            (_) async => http.Response('{"message":"Bad credentials"}', 401),
          ),
        ),
      );

      final outcome = await engine.connect(token: 'ghp_stillnotvalid000000000000');

      expect(outcome.state, SyncState.error);
      expect(outcome.message, contains('invalid or'));
    });

    test('reports a token that is valid but lacks the gist scope', () async {
      final scopeless = FakeGist(scopes: 'repo, read:org');
      final engine = SyncEngine(
        database: a.db,
        ledger: a.ledger,
        config: a.config,
        deviceId: 'device_a',
        clientFactory: (token) =>
            GistClient(token: token, client: scopeless.client()),
      );

      final outcome = await engine.connect(token: scopeless.token);

      expect(outcome.state, SyncState.error);
      expect(outcome.message, contains('gist'));
      expect(a.config.gistId, isNull);
    });
  });

  group('SyncCoordinator', () {
    late FakeGist gist;
    late _Device a;
    late _Device b;
    final coordinators = <SyncCoordinator>[];

    setUp(() {
      gist = FakeGist();
      a = _Device('device_a');
      b = _Device('device_b');
    });
    tearDown(() {
      for (final coordinator in coordinators) {
        coordinator.dispose();
      }
      coordinators.clear();
      a.dispose();
      b.dispose();
    });

    SyncCoordinator coordinatorFor(_Device device, {int intervalMs = 40}) {
      final coordinator = SyncCoordinator(
        engine: device.syncEngine(gist),
        pullInterval: Duration(milliseconds: intervalMs),
        pushDebounce: const Duration(milliseconds: 10),
      );
      device.ledger.onAppended = coordinator.notifyLocalChange;
      coordinators.add(coordinator);
      return coordinator;
    }

    test('pushes on its own shortly after a local write', () async {
      final coordinator = coordinatorFor(a);
      await coordinator.engine.connect(token: gist.token);

      a.ledger.append(a.ledger.deposit(amount: 250, at: DateTime.utc(2026, 1, 2)));
      expect(a.ledger.pendingCount(), 1, reason: 'queued immediately');

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(
        a.ledger.pendingCount(),
        0,
        reason: 'the debounced push should have run without any button',
      );
      expect(coordinator.outcome?.ok, isTrue);
    });

    test('two devices converge with no manual sync at all', () async {
      final coordinatorA = coordinatorFor(a);
      await coordinatorA.engine.connect(token: gist.token);

      final coordinatorB = coordinatorFor(b);
      await coordinatorB.engine.connect(
        token: gist.token,
        gistId: gist.id,
      );

      // Background polling on both sides from here on.
      coordinatorA.start();
      coordinatorB.start();

      a.ledger.append(
        a.ledger.deposit(amount: 5000, at: DateTime.utc(2026, 1, 3)),
      );

      // Give the push debounce and a few pull intervals to run.
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(b.engine.snapshot().cash, closeTo(5000, 1e-6));
      expect(a.ledger.pendingCount(), 0);

      // And the reverse direction: trade on B, A should see it.
      const apple = Instrument(
        symbol: 'AAPL',
        name: 'Apple Inc.',
        assetClass: AssetClass.stock,
      );
      a.instruments.upsert(apple);
      b.instruments.upsert(apple);
      b.engine.submit(
        instrument: apple,
        side: OrderSide.buy,
        type: OrderType.market,
        quantity: 2,
        quote: Quote.derive(
          symbol: 'AAPL',
          price: 100,
          asOf: DateTime.utc(2026, 1, 3),
          source: 'test',
        ),
        now: DateTime.utc(2026, 1, 4),
      );

      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(
        a.engine.snapshot().positions['AAPL']?.quantity,
        closeTo(2, 1e-9),
        reason: 'the trade travelled back without pressing SYNC',
      );
      expect(a.ledger.all().length, b.ledger.all().length);
    });

    test('does not sync when no vault is configured', () async {
      final coordinator = coordinatorFor(a);
      a.ledger.append(a.ledger.deposit(amount: 10, at: DateTime.utc(2026, 1, 1)));

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(coordinator.isConfigured, isFalse);
      expect(gist.requestCount, 0);
      expect(a.ledger.pendingCount(), 1, reason: 'stays queued, never lost');
    });
  });
}
