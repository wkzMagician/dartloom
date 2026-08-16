import 'dart:convert';

import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:drift/drift.dart';
import 'src/database_connection.dart';

final class DriftDocumentStore extends GeneratedDatabase
    implements DatabaseStore {
  DriftDocumentStore(super.executor);

  static Future<DriftDocumentStore> open({String name = 'dartloom'}) async =>
      DriftDocumentStore(await openDartloomConnection(name));

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];

  Future<void> initialize() => customStatement('''
CREATE TABLE IF NOT EXISTS dartloom_documents (
  collection_name TEXT NOT NULL,
  document_id TEXT NOT NULL,
  document_json TEXT NOT NULL,
  PRIMARY KEY (collection_name, document_id)
)
''');

  @override
  Future<List<String>> collections() async {
    final rows = await customSelect(
      'SELECT DISTINCT collection_name FROM dartloom_documents ORDER BY collection_name',
    ).get();
    return rows.map((row) => row.read<String>('collection_name')).toList();
  }

  @override
  Future<void> deleteDocument(String collection, String id) => customStatement(
        'DELETE FROM dartloom_documents WHERE collection_name = ? AND document_id = ?',
        [collection, id],
      );

  @override
  Future<List<String>> list(String collection) async {
    final rows = await customSelect(
      'SELECT document_id FROM dartloom_documents WHERE collection_name = ? ORDER BY document_id',
      variables: [Variable.withString(collection)],
    ).get();
    return rows.map((row) => row.read<String>('document_id')).toList();
  }

  @override
  Future<Map<String, Object?>?> read(String collection, String id) async {
    final row = await customSelect(
      'SELECT document_json FROM dartloom_documents WHERE collection_name = ? AND document_id = ?',
      variables: [Variable.withString(collection), Variable.withString(id)],
    ).getSingleOrNull();
    if (row == null) return null;
    return (jsonDecode(row.read<String>('document_json')) as Map)
        .cast<String, Object?>();
  }

  @override
  Future<void> write(
    String collection,
    String id,
    Map<String, Object?> document,
  ) {
    if (!isJsonValue(document)) {
      throw ArgumentError.value(document, 'document', 'Document must be JSON.');
    }
    return customStatement('''
INSERT INTO dartloom_documents(collection_name, document_id, document_json)
VALUES (?, ?, ?)
ON CONFLICT(collection_name, document_id)
DO UPDATE SET document_json = excluded.document_json
''', [collection, id, jsonEncode(document)]);
  }
}
