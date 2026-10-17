import 'dart:convert';

import '../data/app_database.dart';
import 'secret_codec.dart';
import 'token.dart';

/// Persisted sync settings: vault location, credentials and last-run state.
///
/// The token is DPAPI-encrypted at rest on Windows (see [SecretCodec]).
class SyncConfigStore {
  SyncConfigStore(this._db);

  final AppDatabase _db;

  static const String _kToken = 'gist.token';
  static const String _kGistId = 'gist.id';
  static const String _kEtag = 'gist.etag';
  static const String _kDevices = 'gist.devices';
  static const String _kAccount = 'gist.account';
  static const String _kLastSyncAt = 'sync.last_at';
  static const String _kLastMessage = 'sync.last_message';

  String? get _rawToken => _db.getSyncState(_kToken);

  /// The stored token, with any pasted whitespace/Unicode noise stripped.
  String? get token {
    final decoded = SecretCodec.decode(_rawToken);
    if (decoded == null) return null;
    final clean = sanitizeToken(decoded);
    return clean.isEmpty ? null : clean;
  }

  set token(String? value) => _db.setSyncState(
        _kToken,
        value == null ? null : SecretCodec.encode(sanitizeToken(value)),
      );

  /// GitHub login the vault was last verified against (for the UI).
  String? get accountLogin => _db.getSyncState(_kAccount);

  set accountLogin(String? value) => _db.setSyncState(_kAccount, value);

  /// True when the stored token is encrypted with DPAPI.
  bool get tokenEncrypted => SecretCodec.isEncrypted(_rawToken);

  String? get gistId => _db.getSyncState(_kGistId);

  set gistId(String? value) => _db.setSyncState(_kGistId, value);

  String? get etag => _db.getSyncState(_kEtag);

  set etag(String? value) => _db.setSyncState(_kEtag, value);

  DateTime? get lastSyncAt {
    final raw = _db.getSyncState(_kLastSyncAt);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  set lastSyncAt(DateTime? value) => _db.setSyncState(
        _kLastSyncAt,
        value?.toUtc().toIso8601String(),
      );

  String? get lastMessage => _db.getSyncState(_kLastMessage);

  set lastMessage(String? value) => _db.setSyncState(_kLastMessage, value);

  /// Devices known to be sharing this vault.
  List<String> get knownDevices {
    final raw = _db.getSyncState(_kDevices);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List).map((e) => '$e').toList();
    } catch (_) {
      return const [];
    }
  }

  set knownDevices(List<String> devices) => _db.setSyncState(
        _kDevices,
        jsonEncode(devices.toSet().toList()..sort()),
      );

  bool get isConfigured =>
      (token?.isNotEmpty ?? false) && (gistId?.isNotEmpty ?? false);

  /// Content hash of a shard we have already merged, so unchanged shards are
  /// not decoded again (a cheap checkpoint).
  String? shardHash(String fileName) =>
      _db.getSyncState('shard.hash.$fileName');

  void setShardHash(String fileName, String? hash) =>
      _db.setSyncState('shard.hash.$fileName', hash);

  void clearCredentials() {
    token = null;
    gistId = null;
    etag = null;
    lastMessage = null;
    accountLogin = null;
  }
}
