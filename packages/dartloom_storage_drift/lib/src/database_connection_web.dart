import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:sqlite3/wasm.dart';

Future<DatabaseConnection> openDartloomConnection(String name) async {
  final sqlite = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
  final fileSystem = await IndexedDbFileSystem.open(dbName: name);
  return DatabaseConnection(WasmDatabase(
    sqlite3: sqlite,
    path: '$name.sqlite',
    fileSystem: fileSystem,
  ));
}
