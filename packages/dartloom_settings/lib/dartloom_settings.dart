abstract interface class SettingsStore {
  Future<Object?> read(String key);
  Future<void> write(String key, Object value);
  Future<void> remove(String key);
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
