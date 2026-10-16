import 'dart:io';
import 'dart:math';

/// Deterministic, time-sortable identifiers.
class Ids {
  const Ids._();

  static final Random _rng = Random.secure();

  /// RFC 9562 UUIDv7: 48-bit big-endian Unix-ms timestamp, version 7, 74 random bits.
  ///
  /// Time-ordered so the append-only ledger sorts naturally by primary key.
  static String uuidV7({DateTime? now}) {
    final millis =
        (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch & 0xFFFFFFFFFFFF;
    final bytes = List<int>.filled(16, 0);
    for (var i = 0; i < 6; i++) {
      bytes[5 - i] = (millis >> (8 * i)) & 0xFF;
    }
    for (var i = 6; i < 16; i++) {
      bytes[i] = _rng.nextInt(256);
    }
    bytes[6] = (bytes[6] & 0x0F) | 0x70; // version 7
    bytes[8] = (bytes[8] & 0x3F) | 0x80; // RFC 4122 variant

    final hex = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

/// Stable identifier for the device that produced a ledger event.
String currentDeviceId() {
  if (Platform.isWindows) return 'windows_desktop';
  if (Platform.isAndroid) return 'android_mobile';
  if (Platform.isMacOS) return 'macos_desktop';
  if (Platform.isLinux) return 'linux_desktop';
  return 'unknown_device';
}
