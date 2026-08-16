import 'dart:async';

import 'package:dartloom_sync/dartloom_sync.dart';
import 'package:test/test.dart';

void main() {
  test('foreground scheduler pauses and resumes with lifecycle', () async {
    var calls = 0;
    final scheduler = ForegroundTimerScheduler(onSync: () async => calls++);
    await scheduler.schedulePeriodicSync(const Duration(milliseconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 35));
    expect(calls, greaterThanOrEqualTo(1));
    scheduler.updateLifecycle(SyncLifecycleState.paused);
    final pausedCalls = calls;
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(calls, pausedCalls);
    scheduler.updateLifecycle(SyncLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, greaterThan(pausedCalls));
    await scheduler.cancel();
  });
}
