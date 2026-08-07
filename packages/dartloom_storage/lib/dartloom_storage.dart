abstract interface class LocalStore {
  Future<void> initialize();
  Future<void> close();
}

class MemoryLocalStore implements LocalStore {
  bool _initialized = false;
  bool get isInitialized => _initialized;

  @override
  Future<void> close() async => _initialized = false;

  @override
  Future<void> initialize() async => _initialized = true;
}
