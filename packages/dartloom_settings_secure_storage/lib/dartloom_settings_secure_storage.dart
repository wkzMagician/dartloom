import 'dart:convert';

import 'package:dartloom_settings/dartloom_settings.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final class SecureSettingsStore implements SettingsStore {
  const SecureSettingsStore([this.storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage storage;

  @override
  Future<Object?> read(String key) async {
    final encoded = await storage.read(key: key);
    return encoded == null ? null : jsonDecode(encoded);
  }

  @override
  Future<void> remove(String key) => storage.delete(key: key);

  @override
  Future<void> write(String key, Object value) {
    if (!isSettingsValue(value)) {
      throw ArgumentError.value(value, 'value', 'Unsupported settings value.');
    }
    return storage.write(key: key, value: jsonEncode(value));
  }
}
