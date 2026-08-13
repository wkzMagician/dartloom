import 'dart:convert';
import 'dart:io';

import 'package:dartloom/src/config/config_loader.dart';
import 'package:dartloom/src/config/schema5_migration.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('dry run reports unresolved app paths and changes no files', () async {
    final project =
        await Directory.systemTemp.createTemp('dartloom_schema5_blocked_');
    addTearDown(() => project.delete(recursive: true));
    final configFile =
        File('${project.path}${Platform.pathSeparator}dartloom.yaml');
    final original = _schema4(
      businessPath: 'MiniTodo',
      metadataPath: 'mini_todo/sync-metadata/MiniTodo',
    );
    await configFile.writeAsString(original);
    final before = await configFile.readAsBytes();

    final result = await const Schema5ConfigMigrator().migrate(
      project,
      dryRun: true,
    );

    expect(result.report.status, Schema5MigrationStatus.blocked);
    expect(result.report.diagnostics, hasLength(2));
    expect(result.report.toStructuredJson(), contains('"status": "blocked"'));
    expect(result.yaml, contains('implementation: "app_file_replica"'));
    expect(result.yaml, contains('factory: "createJsonReplicaStore"'));
    expect(result.yaml, contains('TODO(resolve absolute business root'));
    expect(result.yaml, contains('allowed_prefixes'));
    expect(result.yaml, contains('legacy_collection'));
    expect(await configFile.readAsBytes(), before);
    expect(await File('${configFile.path}.v4.backup').exists(), isFalse);
  });

  test('migration is lossless, backed up, validated, and idempotent', () async {
    final project =
        await Directory.systemTemp.createTemp('dartloom_schema5_apply_');
    addTearDown(() => project.delete(recursive: true));
    final configFile =
        File('${project.path}${Platform.pathSeparator}dartloom.yaml');
    final businessPath = _portableAbsolute('${project.path}/business');
    final metadataPath = _portableAbsolute('${project.path}/metadata');
    final original = _schema4(
      storageName: 'documents',
      businessPath: businessPath,
      metadataPath: metadataPath,
    );
    await configFile.writeAsString(original);

    final result = await const Schema5ConfigMigrator().migrate(
      project,
      dryRun: false,
    );

    expect(result.report.status, Schema5MigrationStatus.applied);
    final backup = File('${configFile.path}.v4.backup');
    expect(await backup.readAsString(), original);
    final migratedText = await configFile.readAsString();
    final migrated = loadYaml(migratedText) as YamlMap;
    expect(migrated['schema_version'], 5);
    final storage = (((migrated['capabilities'] as YamlMap)['storage']
        as YamlMap)['instances'] as YamlMap)['documents'] as YamlMap;
    expect(storage['implementation'], 'app_file_replica');
    expect(storage['factory'], 'createJsonReplicaStore');
    expect(storage['options'], isNull);
    final payload = storage['migration'] as YamlMap;
    expect(payload['source_schema'], 4);
    expect(payload['source_implementation'], 'json_directory');
    expect(
      (payload['app_owned_paths'] as YamlMap)['business_root'],
      businessPath,
    );
    final preserved = payload['preserved_options'] as YamlMap;
    expect(preserved['path'], businessPath);
    expect(preserved['metadata_path'], metadataPath);
    expect(preserved['allowed_prefixes'], ['todo-']);
    expect((preserved['seed'] as YamlMap)['.mini-todo.json'], isA<YamlMap>());
    final linkedSync = payload['linked_sync'] as YamlMap;
    expect(
      (linkedSync['default'] as YamlMap)['replica'],
      'storage.documents',
    );
    expect(
      ((linkedSync['default'] as YamlMap)['legacy_remote']
          as YamlMap)['legacy_collection'],
      'json',
    );
    final loaded = await const ConfigLoader().load(project);
    expect(
      loaded.capabilities.values
          .expand((instances) => instances.keys)
          .contains('documents'),
      isTrue,
    );

    final beforeRerun = await configFile.readAsBytes();
    final rerun = await const Schema5ConfigMigrator().migrate(
      project,
      dryRun: false,
    );
    expect(rerun.report.status, Schema5MigrationStatus.notNeeded);
    expect(await configFile.readAsBytes(), beforeRerun);
    expect(await File('${configFile.path}.v4.backup.1').exists(), isFalse);
  });

  test('a pre-existing backup is never overwritten', () async {
    final project =
        await Directory.systemTemp.createTemp('dartloom_schema5_backup_');
    addTearDown(() => project.delete(recursive: true));
    final configFile =
        File('${project.path}${Platform.pathSeparator}dartloom.yaml');
    final original = _schema4(
      businessPath: _portableAbsolute('${project.path}/business'),
      metadataPath: _portableAbsolute('${project.path}/metadata'),
    );
    await configFile.writeAsString(original);
    final firstBackup = File('${configFile.path}.v4.backup');
    await firstBackup.writeAsString('immutable existing backup');

    final result = await const Schema5ConfigMigrator().migrate(
      project,
      dryRun: false,
    );

    expect(result.report.status, Schema5MigrationStatus.applied);
    expect(await firstBackup.readAsString(), 'immutable existing backup');
    expect(
      await File('${configFile.path}.v4.backup.1').readAsString(),
      original,
    );
  });
}

String _schema4({
  String storageName = 'json',
  required String businessPath,
  required String metadataPath,
}) =>
    '''schema_version: 4
app:
  name: mini_todo
  organization: com.example
platforms:
  windows: true
capabilities:
  settings:
    instances:
      default:
        implementation: shared_preferences
      sync_secrets:
        implementation: secure_storage
  storage:
    instances:
      $storageName:
        implementation: json_directory
        options:
          path: ${jsonEncode(businessPath)}
          metadata_path: ${jsonEncode(metadataPath)}
          hierarchical: false
          legacy_json_path: "mini_todo/data.json"
          legacy_key_prefix: "__dartloom_profiles/default/"
          allowed_keys:
            - ".mini-todo.json"
          allowed_prefixes:
            - "todo-"
          seed:
            .mini-todo.json:
              application: mini-todo
              layout: 1
        filters:
          include_hidden: false
  sync:
    instances:
      default:
        implementation: etag
        replica: storage.$storageName
        backend:
          implementation: webdav
          options:
            root_path: MiniTodo
            connect_timeout: 10s
            request_timeout: 30s
            max_parallel_requests: 4
            create_missing_collections: true
            hierarchical: false
            probe_depth_infinity: false
            legacy_collection: json
            legacy_key_prefix: todo-
            listing_limit_hint: 750
sources:
  capabilities: github
release:
  github: true
''';

String _portableAbsolute(String path) => path.replaceAll('\\', '/');
