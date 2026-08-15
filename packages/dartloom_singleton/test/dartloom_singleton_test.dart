import 'dart:async';

import 'package:dartloom_singleton/dartloom_singleton.dart';
import 'package:test/test.dart';

void main() {
  group('MemorySingleInstanceService', () {
    test('acquirePrimary reports the configured primary state', () async {
      expect(await MemorySingleInstanceService().acquirePrimary(), isTrue);
      expect(
        await MemorySingleInstanceService(isPrimary: false).acquirePrimary(),
        isFalse,
      );
    });

    test(
      'ensureSingleInstance returns immediately for the primary instance',
      () async {
        final service = MemorySingleInstanceService(isPrimary: true);
        var teardownRan = false;
        await service.ensureSingleInstance(
          onDuplicateExit: () => teardownRan = true,
        );
        expect(teardownRan, isFalse);
        expect(service.disposed, isFalse);
      },
    );

    test(
      'ensureSingleInstance runs teardown then exit for a duplicate',
      () async {
        final exited = <int>[];
        final service = MemorySingleInstanceService(
          isPrimary: false,
          exitHandler: exited.add,
        );
        var teardownOrder = 0;
        var order = 0;
        await service.ensureSingleInstance(
          onDuplicateExit: () {
            expect(teardownOrder, 0);
            teardownOrder = ++order;
          },
        );
        // Teardown must run before the exit handler observes the exit.
        expect(exited, [0]);
        expect(teardownOrder, lessThan(1 + order));
      },
    );

    test(
      'ensureSingleInstance runs exit even when onDuplicateExit is omitted',
      () async {
        final exited = <int>[];
        final service = MemorySingleInstanceService(
          isPrimary: false,
          exitHandler: exited.add,
        );
        await service.ensureSingleInstance();
        expect(exited, [0]);
      },
    );

    test('onSecondInstance surfaces emitted arguments', () async {
      final service = MemorySingleInstanceService();
      final received = <List<String>>[];
      final sub = service.onSecondInstance.listen(received.add);
      service.emit(['a', 'b']);
      service.emit([]);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(received, [
        ['a', 'b'],
        <String>[],
      ]);
    });

    test('onArgs is invoked with delivered arguments', () async {
      final service = MemorySingleInstanceService();
      final handled = <List<String>>[];
      await service.configure(
        SingleInstanceConfiguration(onArgs: (args) async => handled.add(args)),
      );
      service.emit(['x']);
      await Future<void>.delayed(Duration.zero);
      expect(handled, [
        ['x']
      ]);
      expect(service.configuration.windowAction,
          SecondInstanceWindowAction.restore);
    });

    test('copyWith clears or replaces onArgs', () {
      const base = SingleInstanceConfiguration(onArgs: _noopArgs);
      expect(base.copyWith(clearOnArgs: true).onArgs, isNull);
      expect(
        base.copyWith(onArgs: _noopArgs, clearOnArgs: true).onArgs,
        isNull,
      );
      expect(base.copyWith(clearOnArgs: false).onArgs, isNotNull);
    });

    test('dispose closes the stream', () async {
      final service = MemorySingleInstanceService();
      await service.dispose();
      expect(service.disposed, isTrue);
    });
  });
}

Future<void> _noopArgs(List<String> args) async {}
