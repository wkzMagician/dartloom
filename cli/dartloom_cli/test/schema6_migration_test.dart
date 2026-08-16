import 'dart:io';
import 'package:dartloom/src/config/schema6_migration.dart';
import 'package:test/test.dart';

void main() {
  test('renames schema 5 storage without touching business data', () async {
    final directory = await Directory.systemTemp.createTemp('dartloom-schema6-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}dartloom.yaml')
      ..writeAsStringSync('schema_version: 5\ncapabilities:\n  storage:\n    instances:\n      files:\n        implementation: app_file_replica\n');
    final migrated = await migrateSchema5To6(file);
    expect(migrated, contains('schema_version: 6'));
    expect(migrated, contains('implementation: app_object_store'));
  });
}
