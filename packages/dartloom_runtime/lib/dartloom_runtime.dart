import 'dart:async';

typedef DartloomDisposer = FutureOr<void> Function();
typedef DartloomFactory = FutureOr<DartloomBinding<Object>> Function(
  DartloomFactoryContext context,
);
typedef DartloomRegistrationHook = FutureOr<void> Function(
  DartloomRegistration<Object> registration,
);

enum DartloomStartupScope { foreground, background, both }

final class DartloomBinding<T extends Object> {
  const DartloomBinding(this.value, {this.dispose});

  final T value;
  final DartloomDisposer? dispose;
}

final class DartloomFactoryContext {
  const DartloomFactoryContext._({
    required this.runtime,
    required this.capability,
    required this.name,
    required this.options,
  });

  final DartloomRuntime runtime;
  final String capability;
  final String name;
  final Map<String, Object?> options;

  T get<T extends Object>({String name = 'default'}) =>
      runtime.get<T>(name: name);

  /// Optional dependency lookup. Returns `null` when no instance is
  /// registered (e.g. the capability is optional on the current target),
  /// without throwing.
  T? maybeGet<T extends Object>({String name = 'default'}) =>
      runtime.maybeGet<T>(name: name);
}

final class DartloomRegistration<T extends Object> {
  const DartloomRegistration({
    required this.capability,
    required this.name,
    required this.factory,
    this.options = const {},
    this.dependsOn = const [],
    this.scope = DartloomStartupScope.both,
  });

  final String capability;
  final String name;
  final String factory;
  final Map<String, Object?> options;
  final List<DartloomReference> dependsOn;
  final DartloomStartupScope scope;

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

final class DartloomRuntime {
  final Map<_ServiceKey, _Entry> _entries = {};
  final List<_ServiceKey> _initializationOrder = [];
  bool _initializing = false;

  Future<void> initialize(
    Iterable<DartloomRegistration<Object>> registrations, {
    required Map<String, DartloomFactory> factories,
    DartloomStartupScope scope = DartloomStartupScope.foreground,
    DartloomRegistrationHook? onInitialized,
  }) async {
    if (_entries.isNotEmpty || _initializing) {
      throw const DartloomException('initialize may only be called once.');
    }
    _initializing = true;
    final byKey = <String, DartloomRegistration<Object>>{};
    try {
      for (final registration in registrations) {
        if (!_isActive(registration.scope, scope)) continue;
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
              runtime: this,
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
        await onInitialized?.call(item);
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

  T get<T extends Object>({String name = 'default'}) {
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
  T? maybeGet<T extends Object>({String name = 'default'}) {
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

  bool contains<T extends Object>({String name = 'default'}) =>
      _entries.containsKey(_ServiceKey(T, name));

  Future<void> dispose() async {
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

  bool _isActive(
      DartloomStartupScope registration, DartloomStartupScope requested) {
    if (registration == DartloomStartupScope.both ||
        requested == DartloomStartupScope.both) {
      return true;
    }
    return registration == requested;
  }
}

abstract final class Dartloom {
  static final DartloomRuntime _defaultRuntime = DartloomRuntime();

  static Future<void> initialize(
    Iterable<DartloomRegistration<Object>> registrations, {
    required Map<String, DartloomFactory> factories,
    DartloomStartupScope scope = DartloomStartupScope.foreground,
    DartloomRegistrationHook? onInitialized,
  }) =>
      _defaultRuntime.initialize(
        registrations,
        factories: factories,
        scope: scope,
        onInitialized: onInitialized,
      );

  static T get<T extends Object>({String name = 'default'}) =>
      _defaultRuntime.get<T>(name: name);

  static T? maybeGet<T extends Object>({String name = 'default'}) =>
      _defaultRuntime.maybeGet<T>(name: name);

  static bool contains<T extends Object>({String name = 'default'}) =>
      _defaultRuntime.contains<T>(name: name);

  static Future<void> dispose() => _defaultRuntime.dispose();
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
