import 'package:flutter/material.dart';

import '../data/settings_store.dart';
import 'tokens.dart';

/// App-wide light/dark switch, persisted through [SettingsStore].
///
/// Switching also swaps [AppColors.palette]; the app rebuilds with a new key so
/// every widget re-reads the tokens.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController(this._store)
      : super(_store.isLightTheme ? ThemeMode.light : ThemeMode.dark) {
    _applyPalette();
  }

  final SettingsStore _store;

  bool get isLight => value == ThemeMode.light;

  void toggle() => select(isLight ? ThemeMode.dark : ThemeMode.light);

  void select(ThemeMode mode) {
    value = mode;
    _store.theme = mode == ThemeMode.light ? 'light' : 'dark';
    _applyPalette();
  }

  void _applyPalette() =>
      AppColors.use(isLight ? AppPalette.light : AppPalette.dark);
}
