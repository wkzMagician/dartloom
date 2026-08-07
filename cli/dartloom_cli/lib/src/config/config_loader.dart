import 'dart:io';

import 'package:yaml/yaml.dart';

import '../capabilities/capability_registry.dart';
import 'dartloom_config.dart';

class ConfigException implements Exception {
  ConfigException(this.message);
  final String message;
  @override
  String toString() => 'Dartloom configuration error: $message';
}

class ConfigLoader {
  const ConfigLoader();

  Future<int> schemaVersion(Directory project) async {
    final root = await _root(project);
    return root['schema_version'] as int? ?? 0;
  }

  Future<DartloomConfig> load(Directory project) async {
    final root = await _root(project);
    if (root['schema_version'] == 1) {
      throw ConfigException(
        'schema_version: 1 is obsolete. Run dartloom project update.',
      );
    }
    if (root['schema_version'] != 2) {
      throw ConfigException('schema_version: 2 is required.');
    }
    return _parseV2(root);
  }

  Future<DartloomConfig> loadForMigration(Directory project) async {
    final root = await _root(project);
    return switch (root['schema_version']) {
      1 => _migrateV1(root),
      2 => _parseV2(root),
      _ => throw ConfigException('schema_version must be 1 or 2.'),
    };
  }

  Future<YamlMap> _root(Directory project) async {
    final file = File('${project.path}${Platform.pathSeparator}dartloom.yaml');
    if (!await file.exists()) {
      throw ConfigException('dartloom.yaml was not found in ${project.path}.');
    }
    final root = loadYaml(await file.readAsString());
    if (root is! YamlMap) throw ConfigException('dartloom.yaml must be a map.');
    return root;
  }

  DartloomConfig _parseV2(YamlMap root) {
    final base = _base(root);
    final rawCapabilities = root['capabilities'];
    if (rawCapabilities is! YamlMap) {
      throw ConfigException('capabilities must be a map.');
    }
    final capabilities = <Capability, Map<String, CapabilityInstanceConfig>>{};
    for (final capability in Capability.values) {
      final section = rawCapabilities[capability.name];
      if (section == null) continue;
      if (section is! YamlMap || section['instances'] is! YamlMap) {
        throw ConfigException('${capability.name}.instances must be a map.');
      }
      final instances = <String, CapabilityInstanceConfig>{};
      for (final entry in (section['instances'] as YamlMap).entries) {
        final name = entry.key;
        final value = entry.value;
        if (name is! String || value is! YamlMap) {
          throw ConfigException('${capability.name} instance is invalid.');
        }
        final implementation = value['implementation'];
        if (implementation is! String) {
          throw ConfigException(
            '${capability.name}.$name.implementation is required.',
          );
        }
        final backend = value['backend'];
        final conflict = value['conflict'];
        instances[name] = CapabilityInstanceConfig(
          implementation: implementation,
          factory: value['factory'] as String?,
          options: _stringMap(value['options']),
          dependsOn: _stringList(value['depends_on'], name: 'depends_on'),
          stores: _stringList(value['stores']),
          backend: backend is YamlMap
              ? AdapterConfig(
                  implementation: _requiredString(
                    backend,
                    'implementation',
                    '${capability.name}.$name.backend',
                  ),
                  options: _stringMap(backend['options']),
                )
              : null,
          mergeFactory:
              conflict is YamlMap ? conflict['merge_factory'] as String? : null,
        );
      }
      capabilities[capability] = instances;
    }
    final config = DartloomConfig(
      app: base.$1,
      platforms: base.$2,
      capabilities: capabilities,
      capabilitySource: _capabilitySource(root['sources']),
      githubRelease: (root['release'] as YamlMap?)?['github'] != false,
    );
    _validate(config);
    final registryErrors = CapabilityRegistry.validationErrors(config);
    if (registryErrors.isNotEmpty) {
      throw ConfigException(registryErrors.join(' '));
    }
    return config;
  }

  DartloomConfig _migrateV1(YamlMap root) {
    final base = _base(root);
    final raw = root['capabilities'];
    if (raw is! YamlMap) throw ConfigException('capabilities must be a map.');
    final capabilities = <Capability, Map<String, CapabilityInstanceConfig>>{};
    for (final capability in Capability.values) {
      if (raw[capability.name] == true) {
        capabilities[capability] = CapabilityDefaults.forCapability(capability);
      }
    }
    if (capabilities.containsKey(Capability.sync)) {
      capabilities.putIfAbsent(
        Capability.storage,
        () => CapabilityDefaults.forCapability(Capability.storage),
      );
      capabilities[Capability.storage]!.putIfAbsent(
        'json',
        () => CapabilityDefaults.forCapability(Capability.storage)['json']!,
      );
    }
    return DartloomConfig(
      app: base.$1,
      platforms: base.$2,
      capabilities: capabilities,
      capabilitySource: _capabilitySource(root['sources']),
      githubRelease: (root['release'] as YamlMap?)?['github'] != false,
    );
  }

  (AppConfig, Set<TargetPlatform>) _base(YamlMap root) {
    final app = root['app'];
    final platforms = root['platforms'];
    if (app is! YamlMap ||
        app['name'] is! String ||
        app['organization'] is! String ||
        platforms is! YamlMap) {
      throw ConfigException('app and platforms sections are invalid.');
    }
    return (
      AppConfig(
        name: app['name'] as String,
        organization: app['organization'] as String,
        description: app['description'] as String? ?? '',
      ),
      TargetPlatform.values
          .where((platform) => platforms[platform.name] == true)
          .toSet(),
    );
  }

  void _validate(DartloomConfig config) {
    final storage = config.capabilities[Capability.storage] ?? const {};
    for (final name in storage.keys) {
      if (!const {'text', 'json', 'database'}.contains(name)) {
        throw ConfigException(
          'storage instance $name is invalid; use text, json, or database.',
        );
      }
    }
    for (final sync in config.capabilities[Capability.sync]?.entries ??
        const <MapEntry<String, CapabilityInstanceConfig>>[]) {
      if (sync.value.backend == null) {
        throw ConfigException('sync.${sync.key}.backend is required.');
      }
      for (final reference in sync.value.stores) {
        final parts = reference.split('.');
        if (parts.length != 2 ||
            parts.first != 'storage' ||
            !storage.containsKey(parts.last)) {
          throw ConfigException(
            'sync.${sync.key} references missing store $reference.',
          );
        }
      }
    }
    for (final capability in config.capabilities.entries) {
      for (final instance in capability.value.entries) {
        for (final reference in instance.value.dependsOn) {
          final parts = reference.split('.');
          Capability? dependencyCapability;
          try {
            dependencyCapability = Capability.values.byName(parts.first);
          } on ArgumentError {
            dependencyCapability = null;
          }
          if (parts.length != 2 ||
              dependencyCapability == null ||
              !(config.capabilities[dependencyCapability]
                      ?.containsKey(parts.last) ??
                  false)) {
            throw ConfigException(
              '${capability.key.name}.${instance.key} depends on missing $reference.',
            );
          }
        }
      }
    }
  }

  String _requiredString(YamlMap map, String key, String context) {
    final value = map[key];
    if (value is! String) throw ConfigException('$context.$key is required.');
    return value;
  }

  Map<String, Object?> _stringMap(Object? value) {
    if (value == null) return const {};
    if (value is! YamlMap) throw ConfigException('options must be a map.');
    return {
      for (final entry in value.entries) entry.key as String: entry.value
    };
  }

  List<String> _stringList(Object? value, {String name = 'stores'}) {
    if (value == null) return const [];
    if (value is! YamlList || value.any((item) => item is! String)) {
      throw ConfigException('$name must be a string list.');
    }
    return value.cast<String>().toList();
  }

  CapabilitySource _capabilitySource(Object? sources) {
    final raw = (sources as YamlMap?)?['capabilities'];
    if (raw == null) return CapabilitySource.github;
    if (raw is! String) throw ConfigException('source must be github or pub.');
    try {
      return CapabilitySource.values.byName(raw);
    } on ArgumentError {
      throw ConfigException('source must be github or pub.');
    }
  }

  Future<void> save(Directory project, DartloomConfig config) =>
      File('${project.path}${Platform.pathSeparator}dartloom.yaml')
          .writeAsString(config.toYaml());
}
