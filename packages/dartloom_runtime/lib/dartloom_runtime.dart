import 'dart:async';

typedef DartloomDisposer = FutureOr<void> Function();
typedef DartloomFactory = FutureOr<DartloomBinding<Object>> Function(
  DartloomFactoryContext context,
);

final class DartloomBinding<T extends Object> {
  const DartloomBinding(this.value, {this.dispose});

  final T value;
  final DartloomDisposer? dispose;
}

final class DartloomFactoryContext {
  const DartloomFactoryContext._({
    required this.capability,
    required this.name,
    required this.options,
  });

  final String capability;
  final String name;
  final Map<String, Object?> options;

  T get<T extends Object>({String name = 'default'}) =>
      Dartloom.get<T>(name: name);
}

final class DartloomRegistration<T extends Object> {
  const DartloomRegistration({
    required this.capability,
    required this.name,
    required this.factory,
    this.options = const {},
    this.dependsOn = const [],
  });

  final String capability;
  final String name;
  final String factory;
  final Map<String, Object?> options;
  final List<DartloomReference> dependsOn;

  Type get serviceType => T;
  bool accepts(Object value) => value is T;
  String get key => '$capability.$name';
}

final class DartloomReference {
  const DartloomReference(this.capability, [this.name = 'default']);

  final String capability;
  final String name;
  String get key => '$capability.$name';
}

final class DartloomException implements Exception {
  const DartloomException(this.message);

  final String message;

  @override
  String toString() => 'Dartloom runtime error: $message';
}

abstract final class Dartloom {
  static final Map<_ServiceKey, _Entry> _entries = {};
  static final List<_ServiceKey> _initializationOrder = [];
  static bool _initializing = false;

  static Future<void> initialize(
    Iterable<DartloomRegistration<Object>> registrations, {
    required Map<String, DartloomFactory> factories,
  }) async {
    if (_entries.isNotEmpty || _initializing) {
      throw const DartloomException('initialize may only be called once.');
    }
    _initializing = true;
    final byKey = <String, DartloomRegistration<Object>>{};
    try {
      for (final registration in registrations) {
        if (byKey.containsKey(registration.key)) {
          throw DartloomException(
            'duplicate capability instance ${registration.key}.',
          );
        }
        byKey[registration.key] = registration;
      }
      final visiting = <String>{};
      final initialized = <String>{};

      Future<void> initializeOne(DartloomRegistration<Object> item) async {
        if (initialized.contains(item.key)) return;
        if (!visiting.add(item.key)) {
          throw DartloomException(
            'circular capability dependency involving ${item.key}.',
          );
        }
        for (final dependency in item.dependsOn) {
          final target = byKey[dependency.key];
          if (target == null) {
            throw DartloomException(
              '${item.key} depends on missing ${dependency.key}.',
            );
          }
          await initializeOne(target);
        }
        final factory = factories[item.factory];
        if (factory == null) {
          throw DartloomException(
            '${item.key} references missing factory ${item.factory}.',
          );
        }
        DartloomBinding<Object> binding;
        try {
          binding = await factory(
            DartloomFactoryContext._(
              capability: item.capability,
              name: item.name,
              options: Map.unmodifiable(item.options),
            ),
          );
        } on Object catch (error) {
          throw DartloomException(
            'failed to initialize ${item.key} with ${item.factory}: $error',
          );
        }
        if (!item.accepts(binding.value)) {
          throw DartloomException(
            '${item.key} factory ${item.factory} returned '
            '${binding.value.runtimeType}; expected ${item.serviceType}.',
          );
        }
        final serviceKey = _ServiceKey(item.serviceType, item.name);
        if (_entries.containsKey(serviceKey)) {
          throw DartloomException(
            'duplicate ${item.serviceType} instance named ${item.name}.',
          );
        }
        _entries[serviceKey] = _Entry(binding.value, binding.dispose);
        _initializationOrder.add(serviceKey);
        visiting.remove(item.key);
        initialized.add(item.key);
      }

      for (final registration in byKey.values) {
        await initializeOne(registration);
      }
    } on Object {
      await dispose();
      rethrow;
    } finally {
      _initializing = false;
    }
  }

  static T get<T extends Object>({String name = 'default'}) {
    final entry = _entries[_ServiceKey(T, name)];
    if (entry == null) {
      throw DartloomException('no $T instance named $name is registered.');
    }
    final value = entry.value;
    if (value is! T) {
      throw DartloomException(
        '$T instance named $name has unexpected type ${value.runtimeType}.',
      );
    }
    return value;
  }

  /// Returns a registered capability instance, or `null` when the current
  /// target did not register one.
  ///
  /// Platform-aware generated registries intentionally omit adapters that do
  /// not support the active target. Feature code can use this method for
  /// optional UI without duplicating platform checks.
  static T? maybeGet<T extends Object>({String name = 'default'}) {
    final entry = _entries[_ServiceKey(T, name)];
    if (entry == null) return null;
    final value = entry.value;
    if (value is! T) {
      throw DartloomException(
        '$T instance named $name has unexpected type ${value.runtimeType}.',
      );
    }
    return value;
  }

  static bool contains<T extends Object>({String name = 'default'}) =>
      _entries.containsKey(_ServiceKey(T, name));

  static Future<void> dispose() async {
    Object? firstError;
    StackTrace? firstStack;
    for (final key in _initializationOrder.reversed) {
      final disposer = _entries[key]?.dispose;
      if (disposer == null) continue;
      try {
        await disposer();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStack ??= stackTrace;
      }
    }
    _entries.clear();
    _initializationOrder.clear();
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }
}

final class _Entry {
  const _Entry(this.value, this.dispose);
  final Object value;
  final DartloomDisposer? dispose;
}

final class _ServiceKey {
  const _ServiceKey(this.type, this.name);
  final Type type;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is _ServiceKey && other.type == type && other.name == name;

  @override
  int get hashCode => Object.hash(type, name);
}
