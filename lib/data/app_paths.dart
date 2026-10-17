import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves where the local SQLite database lives.
///
/// Deliberately plugin-free so the Windows and Android builds work without
/// Developer Mode (plugin symlinks). Android's app-private directory is derived
/// from the process name instead of a platform channel.
class AppPaths {
  const AppPaths._();

  static const String _folderName = 'PaperTradingApp';
  static const String _fileName = 'paper_trading.db';

  /// Used if the process name cannot be read (matches android/app/build.gradle.kts).
  static const String _androidPackageFallback =
      'com.papertrading.paper_trading_app';

  /// Per-user data directory for the current platform.
  static Directory dataDirectory() {
    if (Platform.isAndroid) {
      final dir = _androidDataDirectory();
      if (dir != null) {
        if (!dir.existsSync()) dir.createSync(recursive: true);
        return dir;
      }
      throw FileSystemException(
        'Could not locate an Android app data directory for '
        '$_androidPackageFallback.',
      );
    }

    final base = _baseDirectory();
    if (base == null) {
      throw UnsupportedError(
        'No data directory is configured for "${Platform.operatingSystem}".',
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

  /// Android app-private storage (`/data/user/0/<package>/files`).
  ///
  /// The package name comes from `/proc/self/cmdline`, with a compile-time
  /// fallback, because reading it any other way would need a Flutter plugin.
  static Directory? _androidDataDirectory() {
    final package = _androidPackageName() ?? _androidPackageFallback;
    final candidates = <String>[
      '/data/user/0/$package/files',
      '/data/data/$package/files',
      Platform.environment['HOME'] ?? '',
    ];
    for (final path in candidates) {
      if (path.isEmpty) continue;
      final dir = Directory(path);
      try {
        if (dir.existsSync()) return dir;
      } catch (_) {
        // Try the next candidate.
      }
    }

    // Last resort: the cache dir the engine points TMPDIR at.
    try {
      final temp = Directory.systemTemp;
      if (temp.existsSync()) return temp;
    } catch (_) {
      // Nothing writable.
    }
    return null;
  }

  static String? _androidPackageName() {
    try {
      final bytes = File('/proc/self/cmdline').readAsBytesSync();
      final name = String.fromCharCodes(bytes.where((b) => b != 0)).trim();
      if (name.isEmpty) return null;
      // Guard against an app_process style entry.
      return name.contains('.') ? name.split(':').first : null;
    } catch (_) {
      return null;
    }
  }

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
