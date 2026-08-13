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
    final schemaVersion = root['schema_version'];
    if (schemaVersion != 4 && schemaVersion != 5) {
      throw ConfigException(
        'schema_version: 4 or 5 is required. Run dartloom upgrade to migrate '
        'a schema 4 configuration.',
      );
    }
    return _parse(root, schemaVersion: schemaVersion as int);
  }

  Future<DartloomConfig> loadForMigration(Directory project) async {
    final root = await _root(project);
    final schemaVersion = root['schema_version'];
    if (schemaVersion != 4 && schemaVersion != 5) {
      throw ConfigException('schema_version: 4 or 5 is required.');
    }
    return _parse(root, schemaVersion: schemaVersion as int);
  }

  DartloomConfig parse(
    String source, {
    Set<int> acceptedSchemaVersions = const {5},
    bool validateRegistry = true,
  }) {
    final Object? document;
    try {
      document = loadYaml(source);
    } on YamlException catch (error) {
      throw ConfigException('dartloom.yaml is invalid YAML: $error');
    }
    if (document is! YamlMap) {
      throw ConfigException('dartloom.yaml must be a map.');
    }
    final schemaVersion = document['schema_version'];
    if (schemaVersion is! int ||
        !acceptedSchemaVersions.contains(schemaVersion)) {
      throw ConfigException(
        'schema_version must be one of '
        '${acceptedSchemaVersions.toList()..sort()}.',
      );
    }
    return _parse(
      document,
      schemaVersion: schemaVersion,
      validateRegistry: validateRegistry,
    );
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

  DartloomConfig _parse(
    YamlMap root, {
    required int schemaVersion,
    bool validateRegistry = true,
  }) {
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
          platforms: _platformSet(
            value['platforms'],
            context: '${capability.name}.$name.platforms',
          ),
          options: _stringMap(value['options']),
          dependsOn: _stringList(value['depends_on'], name: 'depends_on'),
          replica: value['replica'] as String?,
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
          policy: _stringMap(value['policy']),
          migration: _stringMap(value['migration']),
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
    _validate(config, schemaVersion: schemaVersion);
    if (validateRegistry) {
      final registryErrors = CapabilityRegistry.validationErrors(config);
      if (registryErrors.isNotEmpty) {
        throw ConfigException(registryErrors.join(' '));
      }
    }
    return config;
  }

  (AppConfig, Set<TargetPlatform>) _base(YamlMap root) {
    final app = root['app'];
    final platforms = root['platforms'];
    if (app is! YamlMap ||
        app['name'] is! String ||
        (app['package_name'] != null && app['package_name'] is! String) ||
        app['organization'] is! String ||
        platforms is! YamlMap) {
      throw ConfigException('app and platforms sections are invalid.');
    }
    return (
      AppConfig(
        name: app['name'] as String,
        packageName: app['package_name'] as String?,
        organization: app['organization'] as String,
        description: app['description'] as String? ?? '',
      ),
      TargetPlatform.values
          .where((platform) => platforms[platform.name] == true)
          .toSet(),
    );
  }

  void _validate(DartloomConfig config, {required int schemaVersion}) {
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(config.app.name)) {
      throw ConfigException(
        'app.name must be a valid Dart package name using lowercase letters, '
        'digits, and underscores.',
      );
    }
    if (!RegExp(r'^[a-z0-9][a-z0-9+.-]+$').hasMatch(config.app.packageName)) {
      throw ConfigException(
        'app.package_name must be at least two characters and contain only '
        'lowercase letters, digits, plus, minus, and periods.',
      );
    }
    final storage = config.capabilities[Capability.storage] ?? const {};
    if (schemaVersion == 5) {
      for (final entry in storage.entries) {
        final paths = entry.value.migration['app_owned_paths'];
        if (paths is Map &&
            paths.values.any(
              (value) => value is String && value.startsWith('TODO('),
            )) {
          throw ConfigException(
            'storage.${entry.key} migration contains unresolved app-owned '
            'path TODOs.',
          );
        }
      }
    }
    for (final sync in config.capabilities[Capability.sync]?.entries ??
        const <MapEntry<String, CapabilityInstanceConfig>>[]) {
      if (sync.value.backend == null) {
        throw ConfigException('sync.${sync.key}.backend is required.');
      }
      final reference = sync.value.replica;
      final parts = reference?.split('.') ?? const <String>[];
      final referencedStorage = parts.length == 2 && parts.first == 'storage'
          ? storage[parts.last]
          : null;
      if (referencedStorage == null ||
          (schemaVersion == 5 &&
              referencedStorage.implementation != 'app_file_replica')) {
        throw ConfigException(
          'sync.${sync.key} requires an existing ReplicaStore reference such '
          'as storage.documents.',
        );
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
      for (final entry in value.entries)
        entry.key as String: _plainValue(entry.value)
    };
  }

  Object? _plainValue(Object? value) {
    if (value is YamlMap) {
      return {
        for (final entry in value.entries)
          entry.key as String: _plainValue(entry.value),
      };
    }
    if (value is YamlList) {
      return value.map(_plainValue).toList(growable: false);
    }
    return value;
  }

  List<String> _stringList(Object? value, {String name = 'stores'}) {
    if (value == null) return const [];
    if (value is! YamlList || value.any((item) => item is! String)) {
      throw ConfigException('$name must be a string list.');
    }
    return value.cast<String>().toList();
  }

  Set<TargetPlatform>? _platformSet(
    Object? value, {
    required String context,
  }) {
    if (value == null) return null;
    if (value is! YamlList ||
        value.isEmpty ||
        value.any((item) => item is! String)) {
      throw ConfigException('$context must be a non-empty platform list.');
    }
    final result = <TargetPlatform>{};
    for (final item in value.cast<String>()) {
      try {
        result.add(TargetPlatform.values.byName(item));
      } on ArgumentError {
        throw ConfigException('$context contains unknown platform $item.');
      }
    }
    return result;
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
