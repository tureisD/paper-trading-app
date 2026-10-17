import 'dart:async';
import 'dart:convert';

import '../data/app_database.dart';
import '../data/ledger_repository.dart';
import '../data/models/ledger_event.dart';
import 'gist_client.dart';
import 'hlc.dart';
import 'shard_codec.dart';
import 'sync_config_store.dart';
import 'token.dart';

/// Coarse sync state used by the header indicator.
enum SyncState { notConfigured, syncing, synced, offline, error }

/// Result of one sync attempt.
class SyncOutcome {
  const SyncOutcome({
    required this.state,
    required this.at,
    this.pushed = 0,
    this.pulled = 0,
    this.latency,
    this.message,
  });

  final SyncState state;
  final DateTime at;
  final int pushed;
  final int pulled;
  final Duration? latency;
  final String? message;

  bool get ok => state == SyncState.synced;

  String get label {
    switch (state) {
      case SyncState.notConfigured:
        return 'LOCAL ONLY';
      case SyncState.syncing:
        return 'SYNCING…';
      case SyncState.synced:
        final ms = latency == null ? '' : ' • ${latency!.inMilliseconds}ms';
        return 'SYNCED • GIST$ms';
      case SyncState.offline:
        return 'OFFLINE';
      case SyncState.error:
        return 'SYNC ERROR';
    }
  }
}

/// Cross-device sync over a single secret GitHub Gist.
///
/// Transport only: the ledger itself remains the source of truth, and merging
/// is an idempotent insert-if-absent keyed on `event_id`.
class SyncEngine {
  SyncEngine({
    required this.database,
    required this.ledger,
    required this.config,
    required this.deviceId,
    GistClient Function(String token)? clientFactory,
    this.onMerged,
    this.schemaVersion = 3,
  }) : _clientFactory = clientFactory ?? ((token) => GistClient(token: token));

  final AppDatabase database;
  final LedgerRepository ledger;
  final SyncConfigStore config;
  final String deviceId;
  final int schemaVersion;

  /// Invoked after remote events are merged, so callers can rebuild caches.
  final void Function()? onMerged;

  final GistClient Function(String token) _clientFactory;

  SyncOutcome? _last;
  SyncOutcome? get lastOutcome => _last;

  Timer? _retryTimer;
  DateTime? _retryAt;

  /// When the next automatic retry is due (after a rate limit), if scheduled.
  DateTime? get nextRetryAt => _retryAt;

  bool get isConfigured => config.isConfigured;

  /// Creates or links the vault, then performs a first sync.
  ///
  /// The token is sanitised and verified first, so a bad or under-scoped token
  /// produces a specific explanation instead of a bare 401.
  Future<SyncOutcome> connect({required String token, String? gistId}) async {
    final clean = sanitizeToken(token);
    if (clean.isEmpty) {
      return _record(
        SyncState.error,
        message: 'Paste a GitHub token first (it needs the gist scope).',
      );
    }

    final client = _clientFactory(clean);
    try {
      final info = await client.verifyToken();
      if (!info.hasGistScope) {
        return _record(
          SyncState.error,
          message: 'The token is valid for ${info.describe}, but it has no '
              '"gist" scope. Create a new token with that scope.',
        );
      }

      final trimmed = gistId?.trim();
      GistSnapshot snapshot;
      if (trimmed != null && trimmed.isNotEmpty) {
        snapshot = await client.getGist(trimmed);
        if (snapshot.notModified) {
          throw GistException('Unexpected 304 while linking the vault');
        }
      } else {
        snapshot = await client.createGist(
          description: 'TureisBanking sync vault',
          files: {
            ShardCodec.metaFileName: _encodeMeta(const []),
            ..._shardFiles(_monthKeysOf(ledger.all())),
          },
        );
      }
      config.token = clean;
      config.accountLogin = info.login;
      config.gistId = snapshot.id;
      // Leave the ETag unset so the first pull is unconditional.
      config.etag = null;
      config.knownDevices = _devicesFrom(snapshot);
      return await syncNow();
    } on GistException catch (e) {
      return _record(SyncState.error, message: e.toString());
    }
  }

  void disconnect() {
    config.clearCredentials();
    _last = null;
  }

  /// Pulls remote shards, then pushes local pending events.
  Future<SyncOutcome> syncNow() async {
    if (!isConfigured) {
      return _record(SyncState.notConfigured, message: 'Vault not configured');
    }
    _last = SyncOutcome(state: SyncState.syncing, at: DateTime.now().toUtc());

    final client = _clientFactory(config.token!);
    final gistId = config.gistId!;
    final stopwatch = Stopwatch()..start();

    try {
      final pulled = await _pull(client, gistId);
      final pushed = await _push(client, gistId);
      stopwatch.stop();
      return _record(
        SyncState.synced,
        pulled: pulled,
        pushed: pushed,
        latency: stopwatch.elapsed,
      );
    } on RateLimitedException catch (e) {
      _scheduleRetry(e.resetAt);
      return _record(SyncState.offline, message: e.toString());
    } on GistException catch (e) {
      return _record(SyncState.error, message: e.toString());
    } catch (e) {
      return _record(SyncState.offline, message: 'Offline: $e');
    }
  }

  Future<int> _pull(GistClient client, String gistId) async {
    final snapshot = await client.getGist(gistId, etag: config.etag);
    if (snapshot.notModified) return 0;

    config.etag = snapshot.etag;
    var merged = 0;
    for (final file in snapshot.files.values) {
      if (!ShardCodec.isShardFile(file.filename)) continue;
      // Checkpoint: skip shards whose content we already merged.
      final hash = _contentHash(file.content);
      if (config.shardHash(file.filename) == hash) continue;

      for (final event in ShardCodec.decodeEvents(file.content)) {
        if (ledger.insertIfAbsent(event)) merged++;
        ledger.observeHlc(event.hlcTimestamp);
      }
      config.setShardHash(file.filename, hash);
    }
    config.knownDevices = _devicesFrom(snapshot);
    if (merged > 0) onMerged?.call();
    return merged;
  }

  Future<int> _push(GistClient client, String gistId) async {
    final pending = ledger.pendingEvents();
    if (pending.isEmpty) return 0;

    final files = _shardFiles(_monthKeysOf(pending));
    files[ShardCodec.metaFileName] = _encodeMeta(config.knownDevices);

    final snapshot = await client.updateGist(gistId, files: files);
    config.etag = snapshot.etag;
    ledger.markSynced(pending.map((e) => e.eventId));
    return pending.length;
  }

  /// Files for the months that need (re)upload, built from the full local set
  /// for those months so a PATCH never drops earlier events.
  Map<String, String> _shardFiles(Iterable<String> monthKeys) {
    final files = <String, String>{};
    for (final key in monthKeys) {
      final events = ledger.deviceEventsInMonth(deviceId, key);
      if (events.isEmpty) continue;
      final month = _monthFromKey(key);
      files[ShardCodec.shardFileName(deviceId, month)] =
          ShardCodec.encodeEvents(events);
    }
    return files;
  }

  List<String> _monthKeysOf(Iterable<LedgerEvent> events) {
    final keys = <String>{};
    for (final event in events) {
      final month = Hlc.parse(event.hlcTimestamp).instant;
      keys.add(_monthKey(month));
    }
    return keys.toList()..sort();
  }

  String _encodeMeta(List<String> remoteDevices) {
    final devices = {...remoteDevices, deviceId}.toList()..sort();
    return jsonEncode({
      'schema_version': schemaVersion,
      'devices': devices,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  List<String> _devicesFrom(GistSnapshot snapshot) {
    final meta = snapshot.files[ShardCodec.metaFileName];
    final devices = <String>{...config.knownDevices, ..._devicesFromShards(snapshot)};
    if (meta != null && meta.content.isNotEmpty) {
      try {
        final decoded = jsonDecode(meta.content) as Map<String, dynamic>;
        for (final device in (decoded['devices'] as List? ?? const [])) {
          devices.add('$device');
        }
      } catch (_) {
        // Ignore malformed meta.
      }
    }
    return devices.toList()..sort();
  }

  Iterable<String> _devicesFromShards(GistSnapshot snapshot) sync* {
    for (final name in snapshot.files.keys) {
      if (!ShardCodec.isShardFile(name)) continue;
      final rest = name.substring(ShardCodec.shardPrefix.length);
      final dot = rest.indexOf('.');
      yield dot == -1 ? rest : rest.substring(0, dot);
    }
  }

  /// Schedules an automatic retry once the rate limit resets.
  void _scheduleRetry(DateTime? resetAt) {
    _retryTimer?.cancel();
    var delay = resetAt == null
        ? const Duration(minutes: 2)
        : resetAt.difference(DateTime.now());
    if (delay.isNegative) delay = const Duration(seconds: 30);
    if (delay > const Duration(minutes: 30)) {
      delay = const Duration(minutes: 30);
    }
    _retryAt = DateTime.now().add(delay);
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      _retryAt = null;
      syncNow();
    });
  }

  /// Cancels any pending automatic retry.
  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAt = null;
  }

  /// FNV-1a over the shard text: cheap, stable, good enough for change checks.
  static String _contentHash(String content) {
    var hash = 0x811c9dc5;
    for (final unit in content.codeUnits) {
      hash = (hash ^ unit) & 0xFFFFFFFF;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  static String _monthKey(DateTime month) =>
      '${month.year.toString().padLeft(4, '0')}-'
      '${month.month.toString().padLeft(2, '0')}';

  static DateTime _monthFromKey(String key) {
    final parts = key.split('-');
    return DateTime.utc(int.parse(parts[0]), int.parse(parts[1]));
  }

  SyncOutcome _record(
    SyncState state, {
    int pushed = 0,
    int pulled = 0,
    Duration? latency,
    String? message,
  }) {
    final outcome = SyncOutcome(
      state: state,
      at: DateTime.now().toUtc(),
      pushed: pushed,
      pulled: pulled,
      latency: latency,
      message: message,
    );
    _last = outcome;
    if (state == SyncState.synced) {
      config.lastSyncAt = outcome.at;
      config.lastMessage = null;
    } else if (message != null) {
      config.lastMessage = message;
    }
    return outcome;
  }
}
