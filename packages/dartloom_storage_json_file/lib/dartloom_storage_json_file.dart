import 'dart:convert';
import 'dart:io';

import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final class JsonFileStore implements JsonStore {
  JsonFileStore(this.file);

  final File file;
  Map<String, Object?>? _values;

  static Future<JsonFileStore> open(
      {String path = 'dartloom/data.json'}) async {
    final base = await getApplicationSupportDirectory();
    final store = JsonFileStore(File(p.join(base.path, path)));
    await store._load();
    return store;
  }

  @override
  Future<void> delete(String key) async {
    (await _load()).remove(key);
    await _flush();
  }

  @override
  Future<List<String>> list({String prefix = ''}) async =>
      ((await _load()).keys.where((key) => key.startsWith(prefix)).toList()
        ..sort());

  @override
  Future<Object?> read(String key) async => (await _load())[key];

  @override
  Future<void> write(String key, Object? value) async {
    if (!isJsonValue(value)) {
      throw ArgumentError.value(value, 'value', 'Value must be valid JSON.');
    }
    (await _load())[key] = value;
    await _flush();
  }

  Future<Map<String, Object?>> _load() async {
    if (_values case final values?) return values;
    if (!await file.exists()) return _values = {};
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?> || !isJsonValue(decoded)) {
      throw const FormatException('JSON store root must be an object.');
    }
    return _values = decoded;
  }

  Future<void> _flush() async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(_values), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}
