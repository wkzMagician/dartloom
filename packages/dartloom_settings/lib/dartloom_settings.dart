abstract interface class SettingsStore {
  Future<T?> read<T>(String key);
  Future<void> write<T>(String key, T value);
  Future<void> remove(String key);
}

/// A deterministic default suitable for tests and early app bootstrap.
/// Applications can supply a persistent [SettingsStore] without changing feature APIs.
class MemorySettingsStore implements SettingsStore {
  final Map<String, Object?> _values = {};

  @override
  Future<T?> read<T>(String key) async => _values[key] as T?;

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> write<T>(String key, T value) async => _values[key] = value;
}
