import 'dart:convert';

import 'package:dartloom_settings/dartloom_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Settings backed by platform secure storage.
///
/// The primary iOS store uses `first_unlock` so background work can read
/// credentials after a reboot. Older releases used the default
/// `when_unlocked` accessibility. Keychain queries include accessibility, so
/// an existing item from those releases is not found by the new query and a
/// subsequent add would fail with `errSecDuplicateItem` (-25299). The legacy
/// store is retained only for that one-time migration path.
final class SecureSettingsStore implements SettingsStore {
  const SecureSettingsStore([
    this.storage = const FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock,
      ),
    ),
    this.legacyStorage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage storage;
  final FlutterSecureStorage legacyStorage;

  @override
  Future<Object?> read(String key) async {
    final encoded = await storage.read(key: key);
    if (encoded != null) return jsonDecode(encoded);

    final legacyEncoded = await legacyStorage.read(key: key);
    if (legacyEncoded == null) return null;

    await _writeEncoded(key, legacyEncoded);
    return jsonDecode(legacyEncoded);
  }

  @override
  Future<void> remove(String key) async {
    await storage.delete(key: key);
    await legacyStorage.delete(key: key);
  }

  @override
  Future<void> write(String key, Object value) {
    if (!isSettingsValue(value)) {
      throw ArgumentError.value(
        value,
        'value',
        'Unsupported settings value.',
      );
    }
    return _writeEncoded(key, jsonEncode(value));
  }

  Future<void> _writeEncoded(String key, String encoded) async {
    try {
      await storage.write(key: key, value: encoded);
    } on PlatformException catch (error) {
      if (!_isDuplicateItem(error)) rethrow;

      // The item was created with the old accessibility policy. Remove that
      // exact legacy query and retry the write using the current policy.
      await legacyStorage.delete(key: key);
      await storage.write(key: key, value: encoded);
    }
  }

  bool _isDuplicateItem(PlatformException error) =>
      error.code == '-25299' ||
      error.message?.contains('-25299') == true ||
      '${error.details}'.contains('-25299');
}
