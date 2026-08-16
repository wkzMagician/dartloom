import 'dart:async';

import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:drift/drift.dart';
import 'src/database_connection.dart';

final class DriftObjectStore implements ObjectStore {
  DriftObjectStore(QueryExecutor executor)
      : _database = _DartloomDatabase(executor);
  final _DartloomDatabase _database;
  static Future<DriftObjectStore> open({String name = 'dartloom'}) async =>
      DriftObjectStore(await openDartloomConnection(name));
  final StreamController<StorageChange> _changes = StreamController.broadcast();
  @override
  String get identity => 'drift';
  @override
  bool acceptsKey(String key) =>
      key.isNotEmpty && !key.contains('..') && !key.startsWith('/');
  Future<void> initialize() => _database.customStatement(
      'CREATE TABLE IF NOT EXISTS dartloom_objects (key TEXT PRIMARY KEY NOT NULL, data BLOB NOT NULL, content_hash TEXT NOT NULL, modified_at INTEGER NOT NULL)');
  @override
  Future<List<StoredObject>> scan() async {
    await initialize();
    final rows = await _database
        .customSelect(
            'SELECT key, length(data) AS size, content_hash, modified_at FROM dartloom_objects ORDER BY key')
        .get();
    return [
      for (final row in rows)
        StoredObject(
            key: row.read<String>('key'),
            size: row.read<int>('size'),
            contentHash: row.read<String>('content_hash'),
            modifiedAt: DateTime.fromMillisecondsSinceEpoch(
                row.read<int>('modified_at'),
                isUtc: true))
    ];
  }

  @override
  Future<Uint8List?> read(String key) async {
    await initialize();
    final row = await _database.customSelect(
        'SELECT data FROM dartloom_objects WHERE key = ?',
        variables: [Variable.withString(key)]).getSingleOrNull();
    return row == null ? null : Uint8List.fromList(row.read<List<int>>('data'));
  }

  @override
  Future<void> write(String key, Uint8List data) async {
    if (!acceptsKey(key)) throw ArgumentError.value(key, 'key');
    await initialize();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database.customStatement(
        'INSERT INTO dartloom_objects(key,data,content_hash,modified_at) VALUES (?,?,?,?) ON CONFLICT(key) DO UPDATE SET data=excluded.data, content_hash=excluded.content_hash, modified_at=excluded.modified_at',
        [key, data, data.length.toString(), now]);
    _changes.add(StorageChange(key, StorageChangeKind.updated));
  }

  @override
  Future<void> delete(String key) async {
    await initialize();
    await _database
        .customStatement('DELETE FROM dartloom_objects WHERE key = ?', [key]);
    _changes.add(StorageChange(key, StorageChangeKind.deleted, deleted: true));
  }

  @override
  Stream<StorageChange> get changes => _changes.stream;
  @override
  Future<void> close() async {
    await _changes.close();
    await _database.close();
  }
}

final class _DartloomDatabase extends GeneratedDatabase {
  _DartloomDatabase(super.executor);
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
}

@Deprecated('Use DriftObjectStore.')
typedef DriftDocumentStore = DriftObjectStore;
