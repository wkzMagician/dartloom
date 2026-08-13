enum TargetPlatform { android, ios, windows, macos, linux, web }

enum CapabilitySource { github, pub }

enum Capability {
  settings,
  storage,
  logging,
  autostart,
  sync,
  localization,
  resident,
}

extension TargetPlatformName on TargetPlatform {
  String get configName => name;
  static TargetPlatform parse(String value) =>
      TargetPlatform.values.byName(value);
}

class AppConfig {
  const AppConfig({
    required this.name,
    String? packageName,
    required this.organization,
    required this.description,
  }) : _packageName = packageName;

  /// Dart package name and generated executable name.
  final String name;

  /// Distribution package and launcher name.
  ///
  /// Existing configurations default to the Debian-compatible spelling of
  /// [name], so `mini_todo` becomes `mini-todo` without a schema migration.
  String get packageName => _packageName ?? name.replaceAll('_', '-');
  final String? _packageName;

  final String organization;
  final String description;
}

class AdapterConfig {
  const AdapterConfig({required this.implementation, this.options = const {}});
  final String implementation;
  final Map<String, Object?> options;

  @override
  bool operator ==(Object other) =>
      other is AdapterConfig &&
      other.implementation == implementation &&
      _mapEquals(other.options, options);
  @override
  int get hashCode => Object.hash(implementation, _mapHash(options));
}

class CapabilityInstanceConfig {
  const CapabilityInstanceConfig({
    required this.implementation,
    this.factory,
    this.platforms,
    this.options = const {},
    this.dependsOn = const [],
    this.replica,
    this.backend,
    this.mergeFactory,
    this.policy = const {},
  });

  final String implementation;
  final String? factory;
  final Set<TargetPlatform>? platforms;
  final Map<String, Object?> options;
  final List<String> dependsOn;

  /// The single storage capability whose keys are replica-relative paths.
  final String? replica;
  final AdapterConfig? backend;
  final String? mergeFactory;
  final Map<String, Object?> policy;

  @override
  bool operator ==(Object other) =>
      other is CapabilityInstanceConfig &&
      other.implementation == implementation &&
      other.factory == factory &&
      _setEquals(other.platforms, platforms) &&
      _mapEquals(other.options, options) &&
      _listEquals(other.dependsOn, dependsOn) &&
      other.replica == replica &&
      other.backend == backend &&
      other.mergeFactory == mergeFactory &&
      _mapEquals(other.policy, policy);
  @override
  int get hashCode => Object.hash(
        implementation,
        factory,
        platforms == null ? null : Object.hashAllUnordered(platforms!),
        _mapHash(options),
        Object.hashAll(dependsOn),
        replica,
        backend,
        mergeFactory,
        _mapHash(policy),
      );
}

class DartloomConfig {
  const DartloomConfig({
    required this.app,
    required this.platforms,
    required this.capabilities,
    this.capabilitySource = CapabilitySource.github,
    this.githubRelease = true,
  });

  final AppConfig app;
  final Set<TargetPlatform> platforms;
  final Map<Capability, Map<String, CapabilityInstanceConfig>> capabilities;
  final CapabilitySource capabilitySource;
  final bool githubRelease;

  Set<Capability> get enabledCapabilities => capabilities.entries
      .where((entry) => entry.value.isNotEmpty)
      .map((entry) => entry.key)
      .toSet();

  DartloomConfig copyWith({
    Map<Capability, Map<String, CapabilityInstanceConfig>>? capabilities,
    CapabilitySource? capabilitySource,
  }) =>
      DartloomConfig(
        app: app,
        platforms: platforms,
        capabilities: capabilities ?? this.capabilities,
        capabilitySource: capabilitySource ?? this.capabilitySource,
        githubRelease: githubRelease,
      );

  String toYaml() {
    final buffer = StringBuffer()
      ..writeln('schema_version: 4')
      ..writeln()
      ..writeln('app:')
      ..writeln('  name: ${_scalar(app.name)}')
      ..writeln('  package_name: ${_scalar(app.packageName)}')
      ..writeln('  organization: ${_scalar(app.organization)}')
      ..writeln('  description: ${_scalar(app.description)}')
      ..writeln()
      ..writeln('platforms:');
    for (final platform in TargetPlatform.values) {
      buffer.writeln('  ${platform.name}: ${platforms.contains(platform)}');
    }
    buffer
      ..writeln()
      ..writeln('capabilities:');
    if (enabledCapabilities.isEmpty) {
      buffer
        ..clear()
        ..write('schema_version: 4\n\n')
        ..write('app:\n')
        ..write('  name: ${_scalar(app.name)}\n')
        ..write('  package_name: ${_scalar(app.packageName)}\n')
        ..write('  organization: ${_scalar(app.organization)}\n')
        ..write('  description: ${_scalar(app.description)}\n\n')
        ..write('platforms:\n');
      for (final platform in TargetPlatform.values) {
        buffer.writeln('  ${platform.name}: ${platforms.contains(platform)}');
      }
      buffer.writeln('\ncapabilities: {}');
    }
    for (final capability in Capability.values) {
      final instances = capabilities[capability];
      if (instances == null || instances.isEmpty) continue;
      buffer
        ..writeln('  ${capability.name}:')
        ..writeln('    instances:');
      for (final entry in instances.entries) {
        final instance = entry.value;
        buffer
          ..writeln('      ${entry.key}:')
          ..writeln(
              '        implementation: ${_scalar(instance.implementation)}');
        if (instance.factory != null) {
          buffer.writeln('        factory: ${_scalar(instance.factory!)}');
        }
        if (instance.platforms case final platforms?) {
          buffer.writeln('        platforms:');
          for (final platform in TargetPlatform.values) {
            if (platforms.contains(platform)) {
              buffer.writeln('          - ${_scalar(platform.name)}');
            }
          }
        }
        _writeMap(buffer, '        ', 'options', instance.options);
        if (instance.dependsOn.isNotEmpty) {
          buffer.writeln('        depends_on:');
          for (final dependency in instance.dependsOn) {
            buffer.writeln('          - ${_scalar(dependency)}');
          }
        }
        if (instance.replica != null) {
          buffer.writeln('        replica: ${_scalar(instance.replica!)}');
        }
        if (instance.backend case final backend?) {
          buffer
            ..writeln('        backend:')
            ..writeln(
              '          implementation: ${_scalar(backend.implementation)}',
            );
          _writeMap(buffer, '          ', 'options', backend.options);
        }
        if (instance.mergeFactory != null) {
          buffer
            ..writeln('        conflict:')
            ..writeln('          strategy: preserve')
            ..writeln(
              '          merge_factory: ${_scalar(instance.mergeFactory!)}',
            );
        }
        _writeMap(buffer, '        ', 'policy', instance.policy);
      }
    }
    buffer
      ..writeln()
      ..writeln('sources:')
      ..writeln('  capabilities: ${capabilitySource.name}')
      ..writeln()
      ..writeln('release:')
      ..writeln('  github: $githubRelease');
    return buffer.toString();
  }

  static void _writeMap(
    StringBuffer buffer,
    String indent,
    String name,
    Map<String, Object?> values,
  ) {
    if (values.isEmpty) return;
    buffer.writeln('$indent$name:');
    _writeMapEntries(buffer, '$indent  ', values);
  }

  static void _writeMapEntries(
    StringBuffer buffer,
    String indent,
    Map<String, Object?> values,
  ) {
    for (final entry in values.entries) {
      _writeKeyValue(buffer, indent, entry.key, entry.value);
    }
  }

  static void _writeKeyValue(
    StringBuffer buffer,
    String indent,
    String key,
    Object? value,
  ) {
    if (value is Map) {
      buffer.writeln('$indent$key:');
      _writeMapEntries(buffer, '$indent  ', _asStringMap(value));
    } else if (value is Iterable) {
      buffer.writeln('$indent$key:');
      _writeList(buffer, '$indent  ', value);
    } else {
      buffer.writeln('$indent$key: ${_scalar(value)}');
    }
  }

  static void _writeList(StringBuffer buffer, String indent, Iterable values) {
    for (final value in values) {
      if (value is Map) {
        buffer.writeln('$indent-');
        _writeMapEntries(buffer, '$indent  ', _asStringMap(value));
      } else if (value is Iterable) {
        buffer.writeln('$indent-');
        _writeList(buffer, '$indent  ', value);
      } else {
        buffer.writeln('$indent- ${_scalar(value)}');
      }
    }
  }

  static Map<String, Object?> _asStringMap(Map value) => {
        for (final entry in value.entries) entry.key.toString(): entry.value,
      };

  static String _scalar(Object? value) {
    if (value == null) return 'null';
    if (value is bool || value is num) return '$value';
    return '"${value.toString().replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
  }
}

bool _mapEquals(Map<Object?, Object?> a, Map<Object?, Object?> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || !_valueEquals(entry.value, b[entry.key])) {
      return false;
    }
  }
  return true;
}

bool _listEquals(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (!_valueEquals(a[index], b[index])) return false;
  }
  return true;
}

bool _setEquals(Set<Object?>? a, Set<Object?>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  return a.containsAll(b);
}

bool _valueEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return _mapEquals(a.cast<Object?, Object?>(), b.cast<Object?, Object?>());
  }
  if (a is List && b is List) return _listEquals(a, b);
  return a == b;
}

int _mapHash(Map<Object?, Object?> value) => Object.hashAllUnordered(
      value.entries
          .map((entry) => Object.hash(entry.key, _valueHash(entry.value))),
    );

int _valueHash(Object? value) {
  if (value is Map) return _mapHash(value.cast<Object?, Object?>());
  if (value is List) return Object.hashAll(value.map(_valueHash));
  return value.hashCode;
}

abstract final class CapabilityDefaults {
  static Map<String, CapabilityInstanceConfig> forCapability(
    Capability capability,
  ) =>
      switch (capability) {
        Capability.settings => const {
            'default': CapabilityInstanceConfig(
              implementation: 'shared_preferences',
            ),
          },
        Capability.storage => const {
            'json': CapabilityInstanceConfig(
              implementation: 'json_directory',
              options: {
                'path': 'Dartloom',
                'metadata_path': 'dartloom/sync-metadata/Dartloom',
                'hierarchical': false,
              },
            ),
          },
        Capability.logging => const {
            'default': CapabilityInstanceConfig(implementation: 'logger'),
          },
        Capability.autostart => const {
            'default': CapabilityInstanceConfig(
              implementation: 'launch_at_startup',
            ),
          },
        Capability.sync => const {
            'default': CapabilityInstanceConfig(
              implementation: 'etag',
              replica: 'storage.json',
              backend: AdapterConfig(
                implementation: 'webdav',
                options: {
                  'root_path': 'Dartloom',
                  'connect_timeout': '10s',
                  'request_timeout': '30s',
                  'max_parallel_requests': 4,
                  'create_missing_collections': true,
                  'hierarchical': false,
                  'probe_depth_infinity': false,
                },
              ),
              policy: {
                'mode': 'automatic',
                'triggers': {
                  'startup': true,
                  'resume': true,
                  'connectivity_restored': true,
                  'local_write': {
                    'enabled': true,
                    'debounce': '2s',
                    'max_delay': '10s',
                  },
                },
                'discovery': {
                  'remote_changes': 'auto',
                  'poll_interval': '60s',
                  'safety_reconcile_interval': '15m',
                },
                'execution': {
                  'timeout': '2m',
                  'busy_behavior': 'coalesce_then_rerun',
                  'max_parallel_transfers': 4,
                  'max_object_size': '20mb',
                },
                'retry': {
                  'strategy': 'exponential',
                  'initial_delay': '5s',
                  'fixed_delay': '30s',
                  'sequence': ['5s', '30s', '2m', '10m'],
                  'multiplier': 3,
                  'max_delay': '10m',
                  'jitter': '20%',
                  'max_attempts': 0,
                },
                'conflicts': {
                  'strategy': 'preserve',
                  'delete_vs_update': 'conflict',
                },
                'state': {
                  'base_payload': 'always',
                  'tombstone_retention': '30d',
                },
                'profiles': {
                  'sync_on_activate': true,
                  'existing_data': 'attach_to_default',
                },
                'platforms': {
                  'android': {
                    'background': {
                      'enabled': true,
                      'enqueue_on_pending': true,
                      'periodic_interval': '15m',
                      'flex_interval': '5m',
                      'network': 'connected',
                      'requires_battery_not_low': true,
                      'requires_charging': false,
                      'timeout': '2m',
                    },
                  },
                  'ios': {
                    'background': {
                      'enabled': true,
                      'task': 'app_refresh',
                      'earliest_begin': '15m',
                      'requires_network': true,
                      'timeout': '25s',
                    },
                  },
                },
              },
            ),
          },
        Capability.localization => const {
            'default': CapabilityInstanceConfig(implementation: 'gen_l10n'),
          },
        Capability.resident => const {
            'default': CapabilityInstanceConfig(
              implementation: 'tray',
              options: {
                'icon_path': r'${RESIDENT_ICON_PATH}',
                'tooltip': 'Dartloom application',
              },
            ),
          },
      };
}
