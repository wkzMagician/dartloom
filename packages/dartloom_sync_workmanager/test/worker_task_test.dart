import 'dart:async';

import 'package:dartloom_sync_workmanager/dartloom_sync_workmanager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('background task opens, runs, and disposes a minimal session', () async {
    final events = <String>[];

    final result = await runDartloomSyncWorkerTask(
      {'instance': 'primary'},
      (instance) async {
        events.add('open:$instance');
        return DartloomSyncWorkerSession(
          run: () async {
            events.add('run');
            return true;
          },
          dispose: () async => events.add('dispose'),
        );
      },
    );

    expect(result, isTrue);
    expect(events, ['open:primary', 'run', 'dispose']);
  });

  test('timeout reports failure and still disposes the session', () async {
    final never = Completer<bool>();
    var disposed = false;

    final result = await runDartloomSyncWorkerTask(
      {'instance': 'primary', 'timeout_ms': 1},
      (_) async => DartloomSyncWorkerSession(
        run: () => never.future,
        dispose: () async => disposed = true,
      ),
    );

    expect(result, isFalse);
    expect(disposed, isTrue);
  });

  test('invalid task data does not initialize a runtime', () async {
    var opened = false;
    final result = await runDartloomSyncWorkerTask(null, (_) async {
      opened = true;
      throw StateError('must not open');
    });

    expect(result, isFalse);
    expect(opened, isFalse);
  });
}
