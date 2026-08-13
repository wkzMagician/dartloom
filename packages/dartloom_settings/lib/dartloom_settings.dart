import 'dart:convert';

abstract interface class SettingsStore {
  Future<Object?> read(String key);
  Future<void> write(String key, Object value);
  Future<void> remove(String key);
}

/// Values accepted by the structured settings codec. Unlike [SettingsStore]
/// primitive values, this contract permits nested JSON objects and arrays.
bool isSettingsJsonValue(Object? value) {
  if (value == null || value is bool || value is String || value is num) {
    return true;
  }
  if (value is List) return value.every(isSettingsJsonValue);
  if (value is Map) {
    return value.keys.every((key) => key is String) &&
        value.values.every(isSettingsJsonValue);
  }
  return false;
}

final class SettingsJsonCodec {
  const SettingsJsonCodec._();

  static String encode(Object? value) {
    if (!isSettingsJsonValue(value)) {
      throw ArgumentError.value(
          value, 'value', 'Unsupported JSON settings value.');
    }
    return jsonEncode(value);
  }

  static Object? decode(String encoded) {
    final value = jsonDecode(encoded);
    if (!isSettingsJsonValue(value)) {
      throw const FormatException('Decoded settings value is not valid JSON.');
    }
    return value;
  }
}

bool isSettingsValue(Object? value) =>
    value == null ||
    value is bool ||
    value is int ||
    value is double ||
    value is String ||
    value is List<String>;

/// A deterministic default suitable for tests and early app bootstrap.
/// Applications can supply a persistent [SettingsStore] without changing feature APIs.
class MemorySettingsStore implements SettingsStore {
  final Map<String, Object?> _values = {};

  @override
  Future<Object?> read(String key) async => _values[key];

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> write(String key, Object value) async {
    if (!isSettingsValue(value)) {
      throw ArgumentError.value(value, 'value', 'Unsupported settings value.');
    }
    _values[key] = value;
  }
}
