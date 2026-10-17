import 'app_database.dart';

/// User preferences persisted in the local `sync_state` table.
class SettingsStore {
  SettingsStore(this._db);

  final AppDatabase _db;

  static const String _kTheme = 'ui.theme';
  static const String _kDeposit = 'ui.deposit_amount';

  /// Amount applied by the quick "add funds" action until changed.
  static const double defaultDeposit = 100000;

  static const List<double> depositPresets = <double>[
    10000,
    50000,
    100000,
    250000,
    1000000,
  ];

  /// `dark` or `light`.
  String get theme => _db.getSyncState(_kTheme) ?? 'dark';

  set theme(String value) =>
      _db.setSyncState(_kTheme, value == 'light' ? 'light' : 'dark');

  bool get isLightTheme => theme == 'light';

  double get depositAmount {
    final raw = _db.getSyncState(_kDeposit);
    final parsed = raw == null ? null : double.tryParse(raw);
    if (parsed == null || parsed <= 0) return defaultDeposit;
    return parsed;
  }

  set depositAmount(double value) {
    if (value <= 0) return;
    _db.setSyncState(_kDeposit, '$value');
  }
}
