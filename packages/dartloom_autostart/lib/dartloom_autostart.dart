abstract interface class AutostartService {
  Future<bool> isEnabled();
  Future<void> enable();
  Future<void> disable();
}

/// Test implementation. Platform adapters belong behind [AutostartService],
/// keeping features free of operating-system conditionals.
class MemoryAutostartService implements AutostartService {
  bool _enabled = false;
  @override
  Future<void> disable() async => _enabled = false;
  @override
  Future<void> enable() async => _enabled = true;
  @override
  Future<bool> isEnabled() async => _enabled;
}
