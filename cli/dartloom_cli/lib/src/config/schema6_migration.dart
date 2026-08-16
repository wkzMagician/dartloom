import 'dart:io';
import 'package:yaml/yaml.dart';

/// Lossless schema 5 to 6 configuration migration.
///
/// Only capability names are changed; business data is never moved. Runtime
/// sync metadata is intentionally handled by JournaledObjectStore.open().
Future<String> migrateSchema5To6(File configuration) async {
  final source = await configuration.readAsString();
  final migrated = migrateSchema5To6Source(source);
  await configuration.writeAsString(migrated);
  return migrated;
}

String migrateSchema5To6Source(String source) {
  final document = loadYaml(source);
  if (document is! YamlMap || document['schema_version'] != 5) return source;
  var migrated = source.replaceFirst(
      RegExp(r'^schema_version:\s*5\s*$', multiLine: true),
      'schema_version: 6');
  migrated = migrated.replaceAll(
      'implementation: app_file_replica', 'implementation: app_object_store');
  migrated = migrated.replaceAll('implementation: "app_file_replica"',
      'implementation: "app_object_store"');
  migrated = migrated.replaceAll('implementation: \'app_file_replica\'',
      "implementation: 'app_object_store'");
  return migrated;
}
