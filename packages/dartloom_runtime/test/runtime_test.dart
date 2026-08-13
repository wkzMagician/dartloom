import 'package:dartloom_runtime/dartloom_runtime.dart';
import 'package:test/test.dart';

abstract interface class Service {
  String get value;
}

final class ServiceImpl implements Service {
  ServiceImpl(this.value);
  @override
  final String value;
}

void main() {
  tearDown(Dartloom.dispose);

  test('initializes dependencies and disposes in reverse order', () async {
    final events = <String>[];
    await Dartloom.initialize(
      <DartloomRegistration<Object>>[
        DartloomRegistration<Service>(
          capability: 'second',
          name: 'default',
          factory: 'second',
          dependsOn: const [DartloomReference('first', 'first')],
        ),
        const DartloomRegistration<Service>(
          capability: 'first',
          name: 'first',
          factory: 'first',
        ),
      ],
      factories: {
        'first': (context) {
          events.add('first');
          return DartloomBinding<Service>(
            ServiceImpl('one'),
            dispose: () => events.add('dispose first'),
          );
        },
        'second': (context) {
          events.add(Dartloom.get<Service>(name: 'first').value);
          return DartloomBinding<Service>(
            ServiceImpl('two'),
            dispose: () => events.add('dispose second'),
          );
        },
      },
    );

    expect(Dartloom.get<Service>().value, 'two');
    expect(Dartloom.maybeGet<Service>()?.value, 'two');
    expect(Dartloom.maybeGet<Service>(name: 'missing'), isNull);
    await Dartloom.dispose();
    expect(events, ['first', 'one', 'dispose second', 'dispose first']);
  });

  test('reports missing and circular dependencies', () async {
    await expectLater(
      Dartloom.initialize(
        <DartloomRegistration<Object>>[
          const DartloomRegistration<Service>(
            capability: 'a',
            name: 'default',
            factory: 'a',
            dependsOn: [DartloomReference('missing')],
          ),
        ],
        factories: {'a': (_) => DartloomBinding(ServiceImpl('a'))},
      ),
      throwsA(isA<DartloomException>()),
    );
    await expectLater(
      Dartloom.initialize(
        <DartloomRegistration<Object>>[
          const DartloomRegistration<Service>(
            capability: 'a',
            name: 'default',
            factory: 'a',
            dependsOn: [DartloomReference('b')],
          ),
          const DartloomRegistration<Service>(
            capability: 'b',
            name: 'default',
            factory: 'b',
            dependsOn: [DartloomReference('a')],
          ),
        ],
        factories: {
          'a': (_) => DartloomBinding(ServiceImpl('a')),
          'b': (_) => DartloomBinding(ServiceImpl('b')),
        },
      ),
      throwsA(
        isA<DartloomException>().having(
          (error) => error.message,
          'message',
          contains('circular'),
        ),
      ),
    );
  });

  test('runtime instances are isolated and factory context uses its runtime',
      () async {
    final first = DartloomRuntime();
    final second = DartloomRuntime();
    await first.initialize(
      <DartloomRegistration<Object>>[
        const DartloomRegistration<Service>(
          capability: 'service',
          name: 'default',
          factory: 'service',
        ),
      ],
      factories: {'service': (_) => DartloomBinding(ServiceImpl('first'))},
    );
    await second.initialize(
      <DartloomRegistration<Object>>[
        const DartloomRegistration<Service>(
          capability: 'service',
          name: 'default',
          factory: 'service',
        ),
      ],
      factories: {'service': (_) => DartloomBinding(ServiceImpl('second'))},
    );
    expect(first.get<Service>().value, 'first');
    expect(second.get<Service>().value, 'second');
    await first.dispose();
    expect(second.get<Service>().value, 'second');
    await second.dispose();
  });

  test('startup scope filters registrations', () async {
    final runtime = DartloomRuntime();
    await runtime.initialize(
      <DartloomRegistration<Object>>[
        const DartloomRegistration<Service>(
          capability: 'foreground',
          name: 'foreground',
          factory: 'service',
          scope: DartloomStartupScope.foreground,
        ),
        const DartloomRegistration<Service>(
          capability: 'background',
          name: 'default',
          factory: 'service',
          scope: DartloomStartupScope.background,
        ),
      ],
      factories: {
        'service': (context) => DartloomBinding(ServiceImpl(context.capability))
      },
      scope: DartloomStartupScope.background,
    );
    expect(runtime.maybeGet<Service>(name: 'foreground'), isNull);
    expect(runtime.get<Service>(name: 'default'), isA<Service>());
    await runtime.dispose();
  });
}
