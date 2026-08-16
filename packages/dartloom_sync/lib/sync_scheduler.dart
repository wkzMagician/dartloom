import 'dart:async';

abstract interface class SyncScheduler {
  Future<void> schedulePeriodicSync(Duration interval);
  Future<void> cancel();
  Future<void> triggerNow();
}

enum SyncLifecycleState { resumed, inactive, paused, detached }

class ForegroundTimerScheduler implements SyncScheduler {
  ForegroundTimerScheduler({required this.onSync});
  final Future<void> Function() onSync;
  Timer? _timer;
  Duration? _interval;
  SyncLifecycleState _lifecycle = SyncLifecycleState.resumed;

  void updateLifecycle(SyncLifecycleState state) {
    _lifecycle = state;
    if (state == SyncLifecycleState.resumed && _interval != null) {
      _restart();
    } else if (state != SyncLifecycleState.resumed) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  Future<void> schedulePeriodicSync(Duration interval) async {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval', 'must be positive');
    }
    _interval = interval;
    _restart();
  }

  void _restart() {
    _timer?.cancel();
    if (_lifecycle != SyncLifecycleState.resumed || _interval == null) return;
    _timer = Timer.periodic(_interval!, (_) => unawaited(triggerNow()));
  }

  @override
  Future<void> triggerNow() => onSync();

  @override
  Future<void> cancel() async {
    _timer?.cancel();
    _timer = null;
    _interval = null;
  }
}
