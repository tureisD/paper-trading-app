import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves where the local SQLite database lives.
///
/// Deliberately plugin-free so a plain `flutter build windows` works without
/// Developer Mode (plugin symlinks). Android will switch to `path_provider`
/// once the mobile toolchain is enabled in a later phase.
class AppPaths {
  const AppPaths._();

  static const String _folderName = 'PaperTradingApp';
  static const String _fileName = 'paper_trading.db';

  /// Per-user data directory for the current platform.
  static Directory dataDirectory() {
    final base = _baseDirectory();
    if (base == null) {
      throw UnsupportedError(
        'No data directory is configured for "${Platform.operatingSystem}". '
        'Android support will use path_provider in a later phase.',
      );
    }
    final dir = Directory(p.join(base, _folderName));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Absolute path to the SQLite database file.
  static String databasePath() => p.join(dataDirectory().path, _fileName);

  static String? _baseDirectory() {
    final env = Platform.environment;
    if (Platform.isWindows) {
      return env['APPDATA'] ?? env['LOCALAPPDATA'];
    }
    if (Platform.isMacOS) {
      final home = env['HOME'];
      return home == null ? null : p.join(home, 'Library', 'Application Support');
    }
    if (Platform.isLinux) {
      final xdg = env['XDG_DATA_HOME'];
      if (xdg != null && xdg.isNotEmpty) return xdg;
      final home = env['HOME'];
      return home == null ? null : p.join(home, '.local', 'share');
    }
    return null;
  }
}
