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
    required this.organization,
    required this.description,
  });
  final String name;
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
    this.options = const {},
    this.dependsOn = const [],
    this.stores = const [],
    this.backend,
    this.mergeFactory,
  });

  final String implementation;
  final String? factory;
  final Map<String, Object?> options;
  final List<String> dependsOn;
  final List<String> stores;
  final AdapterConfig? backend;
  final String? mergeFactory;

  @override
  bool operator ==(Object other) =>
      other is CapabilityInstanceConfig &&
      other.implementation == implementation &&
      other.factory == factory &&
      _mapEquals(other.options, options) &&
      _listEquals(other.dependsOn, dependsOn) &&
      _listEquals(other.stores, stores) &&
      other.backend == backend &&
      other.mergeFactory == mergeFactory;
  @override
  int get hashCode => Object.hash(
        implementation,
        factory,
        _mapHash(options),
        Object.hashAll(dependsOn),
        Object.hashAll(stores),
        backend,
        mergeFactory,
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
      ..writeln('schema_version: 2')
      ..writeln()
      ..writeln('app:')
      ..writeln('  name: ${_scalar(app.name)}')
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
        ..write('schema_version: 2\n\n')
        ..write('app:\n')
        ..write('  name: ${_scalar(app.name)}\n')
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
        _writeMap(buffer, '        ', 'options', instance.options);
        if (instance.dependsOn.isNotEmpty) {
          buffer.writeln('        depends_on:');
          for (final dependency in instance.dependsOn) {
            buffer.writeln('          - ${_scalar(dependency)}');
          }
        }
        if (instance.stores.isNotEmpty) {
          buffer.writeln('        stores:');
          for (final store in instance.stores) {
            buffer.writeln('          - ${_scalar(store)}');
          }
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
    for (final entry in values.entries) {
      buffer.writeln('$indent  ${entry.key}: ${_scalar(entry.value)}');
    }
  }

  static String _scalar(Object? value) {
    if (value == null) return 'null';
    if (value is bool || value is num) return '$value';
    return '"${value.toString().replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
  }
}

bool _mapEquals(Map<Object?, Object?> a, Map<Object?, Object?> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (entry.value is Map && other is Map) {
      if (!_mapEquals(
        (entry.value as Map).cast<Object?, Object?>(),
        other.cast<Object?, Object?>(),
      )) {
        return false;
      }
    } else if (entry.value is List && other is List) {
      if (!_listEquals(entry.value as List, other)) {
        return false;
      }
    } else if (other != entry.value) {
      return false;
    }
  }
  return true;
}

bool _listEquals(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

int _mapHash(Map<Object?, Object?> value) => Object.hashAllUnordered(
      value.entries.map((entry) => Object.hash(entry.key, entry.value)),
    );

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
              implementation: 'json_file',
              options: {'path': 'dartloom/data.json'},
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
              implementation: 'etag_object',
              stores: ['storage.json'],
              backend: AdapterConfig(
                implementation: 'webdav',
                options: {
                  'base_url': r'${WEBDAV_URL}',
                  'root_path': 'Dartloom',
                  'username': r'${WEBDAV_USERNAME}',
                  'password': r'${WEBDAV_PASSWORD}',
                },
              ),
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
