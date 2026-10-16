import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

typedef _ProtectNative = Int32 Function(
  Pointer<_DataBlob>,
  Pointer<Utf16>,
  Pointer<_DataBlob>,
  Pointer<Void>,
  Pointer<Void>,
  Uint32,
  Pointer<_DataBlob>,
);
typedef _ProtectDart = int Function(
  Pointer<_DataBlob>,
  Pointer<Utf16>,
  Pointer<_DataBlob>,
  Pointer<Void>,
  Pointer<Void>,
  int,
  Pointer<_DataBlob>,
);

typedef _UnprotectNative = Int32 Function(
  Pointer<_DataBlob>,
  Pointer<Pointer<Utf16>>,
  Pointer<_DataBlob>,
  Pointer<Void>,
  Pointer<Void>,
  Uint32,
  Pointer<_DataBlob>,
);
typedef _UnprotectDart = int Function(
  Pointer<_DataBlob>,
  Pointer<Pointer<Utf16>>,
  Pointer<_DataBlob>,
  Pointer<Void>,
  Pointer<Void>,
  int,
  Pointer<_DataBlob>,
);

typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void>);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void>);

/// Windows DPAPI (user-scoped) wrapper. Encrypts a secret so the on-disk value
/// is only readable by the same Windows user account — the functional
/// equivalent of an OS credential store, without a Flutter plugin.
class _Dpapi {
  _Dpapi() {
    final crypt32 = DynamicLibrary.open('crypt32.dll');
    _protectFn = crypt32.lookupFunction<_ProtectNative, _ProtectDart>(
      'CryptProtectData',
    );
    _unprotectFn = crypt32.lookupFunction<_UnprotectNative, _UnprotectDart>(
      'CryptUnprotectData',
    );
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    _localFreeFn = kernel32.lookupFunction<_LocalFreeNative, _LocalFreeDart>(
      'LocalFree',
    );
  }

  /// CRYPTPROTECT_UI_FORBIDDEN — never prompt.
  static const int _uiForbidden = 0x1;

  late final _ProtectDart _protectFn;
  late final _UnprotectDart _unprotectFn;
  late final _LocalFreeDart _localFreeFn;

  Uint8List? protect(List<int> data) {
    final inBlob = calloc<_DataBlob>();
    final outBlob = calloc<_DataBlob>();
    final buffer = calloc<Uint8>(data.isEmpty ? 1 : data.length);
    try {
      buffer.asTypedList(data.length).setAll(0, data);
      inBlob.ref.cbData = data.length;
      inBlob.ref.pbData = buffer;

      final ok = _protectFn(
        inBlob, nullptr, nullptr, nullptr, nullptr, _uiForbidden, outBlob,
      );
      if (ok == 0) return null;

      final result = Uint8List.fromList(
        outBlob.ref.pbData.asTypedList(outBlob.ref.cbData),
      );
      _localFreeFn(outBlob.ref.pbData.cast<Void>());
      return result;
    } catch (_) {
      return null;
    } finally {
      calloc.free(buffer);
      calloc.free(inBlob);
      calloc.free(outBlob);
    }
  }

  Uint8List? unprotect(Uint8List data) {
    final inBlob = calloc<_DataBlob>();
    final outBlob = calloc<_DataBlob>();
    final buffer = calloc<Uint8>(data.isEmpty ? 1 : data.length);
    final description = calloc<Pointer<Utf16>>();
    try {
      buffer.asTypedList(data.length).setAll(0, data);
      inBlob.ref.cbData = data.length;
      inBlob.ref.pbData = buffer;

      final ok = _unprotectFn(
        inBlob, description, nullptr, nullptr, nullptr, _uiForbidden, outBlob,
      );
      if (ok == 0) return null;

      final result = Uint8List.fromList(
        outBlob.ref.pbData.asTypedList(outBlob.ref.cbData),
      );
      _localFreeFn(outBlob.ref.pbData.cast<Void>());
      if (description.value.address != 0) {
        _localFreeFn(description.value.cast<Void>());
      }
      return result;
    } catch (_) {
      return null;
    } finally {
      calloc.free(buffer);
      calloc.free(inBlob);
      calloc.free(outBlob);
      calloc.free(description);
    }
  }
}

/// At-rest encoding for the GitHub token.
///
/// `dpapi:<base64>` on Windows; `plain:<base64>` as a clearly-marked fallback
/// elsewhere (where the token should be moved to platform secure storage).
class SecretCodec {
  const SecretCodec._();

  static const String encryptedPrefix = 'dpapi:';
  static const String plainPrefix = 'plain:';

  static _Dpapi? _instance;

  static bool get _available => Platform.isWindows;

  static String encode(String plaintext) {
    if (_available) {
      try {
        final protected = (_instance ??= _Dpapi()).protect(utf8.encode(plaintext));
        if (protected != null) {
          return '$encryptedPrefix${base64Encode(protected)}';
        }
      } catch (_) {
        // Fall through to the plaintext-with-marker form.
      }
    }
    return '$plainPrefix${base64Encode(utf8.encode(plaintext))}';
  }

  static String? decode(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    try {
      if (stored.startsWith(encryptedPrefix)) {
        final data = base64Decode(stored.substring(encryptedPrefix.length));
        final clear = (_instance ??= _Dpapi()).unprotect(data);
        return clear == null ? null : utf8.decode(clear);
      }
      if (stored.startsWith(plainPrefix)) {
        return utf8.decode(base64Decode(stored.substring(plainPrefix.length)));
      }
      return stored; // Legacy/plain value.
    } catch (_) {
      return null;
    }
  }

  static bool isEncrypted(String? stored) =>
      stored?.startsWith(encryptedPrefix) ?? false;
}
