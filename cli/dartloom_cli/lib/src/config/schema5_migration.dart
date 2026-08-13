import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'config_loader.dart';
import 'dartloom_config.dart';

enum Schema5MigrationStatus { notNeeded, ready, blocked, applied }

class Schema5MigrationReport {
  const Schema5MigrationReport({
    required this.status,
    required this.configurationPath,
    required this.sourceSchema,
    required this.targetSchema,
    required this.changes,
    required this.recognized,
    required this.diagnostics,
    this.backupPath,
    this.migrationPayload = const {},
  });

  final Schema5MigrationStatus status;
  final String configurationPath;
  final int sourceSchema;
  final int targetSchema;
  final List<String> changes;
  final Map<String, Object?> recognized;
  final List<String> diagnostics;
  final String? backupPath;
  final Map<String, Object?> migrationPayload;

  bool get isBlocked => status == Schema5MigrationStatus.blocked;

  Map<String, Object?> toJson() => {
        'operation': 'schema4_to_schema5',
        'status': status.name,
        'configuration': configurationPath,
        'source_schema': sourceSchema,
        'target_schema': targetSchema,
        'changes': changes,
        'recognized': recognized,
        'diagnostics': diagnostics,
        if (backupPath != null) 'backup': backupPath,
        if (migrationPayload.isNotEmpty) 'migration_payload': migrationPayload,
      };

  String toStructuredJson() => const JsonEncoder.withIndent('  ').convert({
        'configuration_migration': toJson(),
      });

  Schema5MigrationReport copyWith({
    Schema5MigrationStatus? status,
    String? backupPath,
  }) =>
      Schema5MigrationReport(
        status: status ?? this.status,
        configurationPath: configurationPath,
        sourceSchema: sourceSchema,
        targetSchema: targetSchema,
        changes: changes,
        recognized: recognized,
        diagnostics: diagnostics,
        backupPath: backupPath ?? this.backupPath,
        migrationPayload: migrationPayload,
      );
}

class Schema5MigrationResult {
  const Schema5MigrationResult({
    required this.config,
    required this.report,
    required this.yaml,
  });

  final DartloomConfig config;
  final Schema5MigrationReport report;
  final String yaml;
}

/// Plans and transactionally applies the schema-4-to-schema-5 configuration
/// migration. It never resolves application business paths on the app's
/// behalf.
class Schema5ConfigMigrator {
  const Schema5ConfigMigrator({ConfigLoader? loader})
      : _loader = loader ?? const ConfigLoader();

  final ConfigLoader _loader;

  Future<Schema5MigrationResult> migrate(
    Directory project, {
    required bool dryRun,
  }) async {
    final planned = await plan(project);
    if (dryRun ||
        planned.report.isBlocked ||
        planned.report.status == Schema5MigrationStatus.notNeeded) {
      return planned;
    }

    final active = _configurationFile(project);
    final originalBytes = await active.readAsBytes();
    final backup = await _writeUniqueBackup(active, originalBytes);
    File? temporary;
    try {
      temporary = await _createUniqueTemporary(active);
      await temporary.writeAsString(planned.yaml, flush: true);
      final reparsed = _loader.parse(
        await temporary.readAsString(),
        acceptedSchemaVersions: const {5},
      );
      await temporary.rename(active.path);
      temporary = null;
      return Schema5MigrationResult(
        config: reparsed,
        yaml: planned.yaml,
        report: planned.report.copyWith(
          status: Schema5MigrationStatus.applied,
          backupPath: backup.path,
        ),
      );
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  Future<Schema5MigrationResult> plan(Directory project) async {
    final active = _configurationFile(project);
    if (!await active.exists()) {
      throw ConfigException('dartloom.yaml was not found in ${project.path}.');
    }
    final source = await active.readAsString();
    final root = _yamlMap(source);
    final schemaVersion = root['schema_version'];
    if (schemaVersion == 5) {
      final config = _loader.parse(source);
      return Schema5MigrationResult(
        config: config,
        yaml: source,
        report: Schema5MigrationReport(
          status: Schema5MigrationStatus.notNeeded,
          configurationPath: active.path,
          sourceSchema: 5,
          targetSchema: 5,
          changes: const [],
          recognized: const {},
          diagnostics: const [],
        ),
      );
    }
    if (schemaVersion != 4) {
      throw ConfigException(
        'schema_version: 4 is required for migration to schema 5.',
      );
    }

    final config = _loader.parse(
      source,
      acceptedSchemaVersions: const {4},
      validateRegistry: false,
    );
    final replicaNames = _replicaStorageNames(root);
    final rawStorageInstances = _instances(root, 'storage');
    final storageInstances =
        config.capabilities[Capability.storage] ?? const {};
    final namesToMigrate = <String>{
      if (rawStorageInstances.containsKey('json')) 'json',
      ...replicaNames,
    };
    if (namesToMigrate.isEmpty) {
      final migrated = config.toYaml();
      final validated = _loader.parse(migrated);
      return Schema5MigrationResult(
        config: validated,
        yaml: migrated,
        report: Schema5MigrationReport(
          status: Schema5MigrationStatus.ready,
          configurationPath: active.path,
          sourceSchema: 4,
          targetSchema: 5,
          changes: const ['Set schema_version to 5.'],
          recognized: const {'replica_storage': <String>[]},
          diagnostics: const [],
        ),
      );
    }

    final diagnostics = <String>[];
    final capabilities = <Capability, Map<String, CapabilityInstanceConfig>>{
      for (final entry in config.capabilities.entries)
        entry.key: <String, CapabilityInstanceConfig>{...entry.value},
    };
    final syncInstances = root['capabilities'] is YamlMap
        ? (root['capabilities'] as YamlMap)['sync']
        : null;
    final rawSyncInstances =
        syncInstances is YamlMap ? syncInstances['instances'] : null;
    final syncReferences = <String, Object?>{};
    final legacyRemote = <String, Object?>{};
    if (rawSyncInstances is YamlMap) {
      for (final entry in rawSyncInstances.entries) {
        if (entry.key is! String || entry.value is! YamlMap) continue;
        final value = entry.value as YamlMap;
        syncReferences[entry.key as String] = value['replica'];
        final backend = value['backend'];
        final backendOptions = backend is YamlMap
            ? _plainMap(backend['options'])
            : const <String, Object?>{};
        final legacy = <String, Object?>{
          for (final option in backendOptions.entries)
            if (option.key.startsWith('legacy_')) option.key: option.value,
        };
        if (legacy.isNotEmpty) legacyRemote[entry.key as String] = legacy;
      }
    }
    final migrationPayloads = <String, Object?>{};
    final recognizedStorage = <String, Object?>{};
    final migratedStores = <String, CapabilityInstanceConfig>{
      ...?capabilities[Capability.storage],
    };
    for (final name in namesToMigrate) {
      final rawStorage = rawStorageInstances[name];
      final storage = storageInstances[name];
      if (rawStorage == null || storage == null) {
        diagnostics.add(
          'sync.replica references missing storage.$name.',
        );
        continue;
      }
      final preservedOptions = _plainMap(rawStorage['options']);
      final businessPath = preservedOptions['path'];
      final metadataPath = preservedOptions['metadata_path'];
      if (!_isAbsolutePath(businessPath)) {
        diagnostics.add(
          'storage.$name.options.path is not an absolute business path. '
          'Resolve it in the application and register createJsonReplicaStore.',
        );
      }
      if (!_isAbsolutePath(metadataPath)) {
        diagnostics.add(
          'storage.$name.options.metadata_path is not an absolute metadata '
          'path. Resolve it in the application outside the business replica root.',
        );
      }
      final preservedFields = <String, Object?>{
        for (final key in const ['filters', 'seed', 'legacy', 'legacy_remote'])
          if (rawStorage.containsKey(key)) key: _plainValue(rawStorage[key]),
      };
      final linkedSync = <String, Object?>{
        for (final entry in syncReferences.entries)
          if (entry.value == 'storage.$name')
            entry.key: {
              'replica': entry.value,
              if (legacyRemote.containsKey(entry.key))
                'legacy_remote': legacyRemote[entry.key],
            },
      };
      final payload = <String, Object?>{
        'source_schema': 4,
        'source_implementation': storage.implementation,
        'app_owned_paths': {
          'business_root': _isAbsolutePath(businessPath)
              ? businessPath
              : 'TODO(resolve absolute business root in the application)',
          'metadata_root': _isAbsolutePath(metadataPath)
              ? metadataPath
              : 'TODO(resolve absolute metadata root in the application)',
        },
        'preserved_options': preservedOptions,
        if (preservedFields.isNotEmpty) 'preserved_fields': preservedFields,
        if (linkedSync.isNotEmpty) 'linked_sync': linkedSync,
      };
      migrationPayloads[name] = payload;
      recognizedStorage[name] = {
        'filters': {
          if (preservedOptions.containsKey('allowed_keys'))
            'allowed_keys': preservedOptions['allowed_keys'],
          if (preservedOptions.containsKey('allowed_prefixes'))
            'allowed_prefixes': preservedOptions['allowed_prefixes'],
          if (preservedOptions.containsKey('filters'))
            'filters': preservedOptions['filters'],
          if (preservedFields.containsKey('filters'))
            'instance_filters': preservedFields['filters'],
        },
        if (preservedOptions.containsKey('seed'))
          'seed': preservedOptions['seed'],
        'legacy_local': {
          for (final option in preservedOptions.entries)
            if (option.key.startsWith('legacy_')) option.key: option.value,
        },
      };
      migratedStores[name] = CapabilityInstanceConfig(
        implementation: 'app_file_replica',
        factory: 'createJsonReplicaStore',
        platforms: storage.platforms,
        options: const {},
        dependsOn: storage.dependsOn,
        replica: storage.replica,
        backend: storage.backend,
        mergeFactory: storage.mergeFactory,
        policy: storage.policy,
        migration: payload,
      );
    }
    capabilities[Capability.storage] = migratedStores;
    final proposed = config.copyWith(capabilities: capabilities);
    final migrated = proposed.toYaml();
    DartloomConfig validated = proposed;
    if (diagnostics.isEmpty) validated = _loader.parse(migrated);
    return Schema5MigrationResult(
      config: validated,
      yaml: migrated,
      report: Schema5MigrationReport(
        status: diagnostics.isEmpty
            ? Schema5MigrationStatus.ready
            : Schema5MigrationStatus.blocked,
        configurationPath: active.path,
        sourceSchema: 4,
        targetSchema: 5,
        changes: const [
          'Set schema_version to 5.',
          'Replace replica storage with app_file_replica and an '
              'application-owned factory.',
          'Move schema-4 storage details into a non-runtime migration payload.',
        ],
        recognized: {
          'replica_storage': recognizedStorage,
          'sync.replica': syncReferences,
          'legacy_remote': legacyRemote,
        },
        diagnostics: diagnostics,
        migrationPayload: migrationPayloads,
      ),
    );
  }

  File _configurationFile(Directory project) =>
      File(p.join(project.path, 'dartloom.yaml'));

  Future<File> _writeUniqueBackup(File active, List<int> bytes) async {
    var suffix = '';
    var index = 0;
    while (true) {
      final candidate = File('${active.path}.v4.backup$suffix');
      try {
        await candidate.create(exclusive: true);
        try {
          await candidate.writeAsBytes(bytes, flush: true);
          final backupBytes = await candidate.readAsBytes();
          if (!_bytesEqual(bytes, backupBytes)) {
            throw ConfigException('Configuration backup verification failed.');
          }
          _loader.parse(
            utf8.decode(backupBytes),
            acceptedSchemaVersions: const {4},
            validateRegistry: false,
          );
          return candidate;
        } catch (_) {
          if (await candidate.exists()) await candidate.delete();
          rethrow;
        }
      } on PathExistsException {
        index++;
        suffix = '.$index';
      } on FileSystemException catch (error) {
        if (await candidate.exists()) {
          index++;
          suffix = '.$index';
          continue;
        }
        throw ConfigException('Could not create configuration backup: $error');
      }
    }
  }

  Future<File> _createUniqueTemporary(File active) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      final candidate = File(
        '${active.path}.schema5.$pid.${DateTime.now().microsecondsSinceEpoch}.$attempt.tmp',
      );
      try {
        await candidate.create(exclusive: true);
        return candidate;
      } on PathExistsException {
        continue;
      }
    }
    throw ConfigException('Could not allocate a schema 5 temporary file.');
  }

  YamlMap _yamlMap(String source) {
    final value = loadYaml(source);
    if (value is! YamlMap) {
      throw ConfigException('dartloom.yaml must be a map.');
    }
    return value;
  }

  Map<String, YamlMap> _instances(YamlMap root, String capability) {
    final capabilities = root['capabilities'];
    if (capabilities is! YamlMap) return const {};
    final section = capabilities[capability];
    if (section is! YamlMap) return const {};
    final instances = section['instances'];
    if (instances is! YamlMap) return const {};
    return {
      for (final entry in instances.entries)
        if (entry.key is String && entry.value is YamlMap)
          entry.key as String: entry.value as YamlMap,
    };
  }

  Set<String> _replicaStorageNames(YamlMap root) {
    final result = <String>{};
    for (final sync in _instances(root, 'sync').values) {
      final replica = sync['replica'];
      if (replica is! String) continue;
      final parts = replica.split('.');
      if (parts.length == 2 && parts.first == 'storage') {
        result.add(parts.last);
      }
    }
    return result;
  }

  bool _isAbsolutePath(Object? value) =>
      value is String && value.trim().isNotEmpty && p.isAbsolute(value);

  Map<String, Object?> _plainMap(Object? value) {
    if (value == null) return const {};
    if (value is! Map) throw ConfigException('migration source must be a map.');
    return {
      for (final entry in value.entries)
        entry.key.toString(): _plainValue(entry.value),
    };
  }

  Object? _plainValue(Object? value) {
    if (value is Map) return _plainMap(value);
    if (value is Iterable) {
      return value.map(_plainValue).toList(growable: false);
    }
    return value;
  }

  bool _bytesEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
