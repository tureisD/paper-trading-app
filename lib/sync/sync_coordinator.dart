import 'dart:async';

import 'package:flutter/foundation.dart';

import 'sync_config_store.dart';
import 'sync_engine.dart';

/// Orchestrates background sync.
///
/// Sync only being available as a manual button is why a trade made on one
/// device could sit unsynced for hours. This runs it on a cadence and pushes
/// shortly after any local ledger write:
///
/// - a **pull** every [pullInterval] while the app is open (and once at start),
/// - a **push** [pushDebounce] after the last local change,
/// - never two syncs at once, and it notifies listeners around each run so the
///   status pill can show `SYNCING…`.
class SyncCoordinator extends ChangeNotifier {
  SyncCoordinator({
    required this.engine,
    this.pullInterval = const Duration(seconds: 45),
    this.pushDebounce = const Duration(seconds: 2),
  });

  final SyncEngine engine;
  final Duration pullInterval;
  final Duration pushDebounce;

  Timer? _pullTimer;
  Timer? _pushTimer;
  bool _running = false;
  bool _started = false;
  bool _pendingLocalChanges = false;

  bool get isConfigured => engine.isConfigured;
  bool get isBusy => _running;
  SyncOutcome? get outcome => engine.lastOutcome;
  SyncConfigStore get config => engine.config;

  /// True when local writes are waiting to be pushed.
  bool get hasUnpushedChanges => _pendingLocalChanges;

  /// Begins background sync. Safe to call more than once.
  void start() {
    if (_started) return;
    _started = true;
    _pullTimer = Timer.periodic(pullInterval, (_) => unawaited(syncNow()));
    if (isConfigured) unawaited(syncNow());
  }

  void stop() {
    _pullTimer?.cancel();
    _pullTimer = null;
    _pushTimer?.cancel();
    _pushTimer = null;
  }

  /// Called after every local ledger append. Debounced so a burst of trades
  /// results in one push.
  void notifyLocalChange() {
    _pendingLocalChanges = true;
    notifyListeners();
    if (!isConfigured) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(pushDebounce, () {
      _pushTimer = null;
      unawaited(syncNow());
    });
  }

  /// Full pull + push right now (the SYNC button, and the periodic tick).
  Future<SyncOutcome?> syncNow() async {
    if (!isConfigured) {
      notifyListeners();
      return null;
    }
    if (_running) return outcome;

    _running = true;
    notifyListeners();
    try {
      final result = await engine.syncNow();
      if (result.ok) _pendingLocalChanges = false;
      return result;
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
