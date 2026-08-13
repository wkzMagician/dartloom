import 'dart:convert';
import 'dart:io';

import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final class JsonFileStore implements JsonStore {
  JsonFileStore(this.file);

  final File file;

  static Future<JsonFileStore> open(
      {String path = 'dartloom/data.json'}) async {
    final base = await getApplicationSupportDirectory();
    final store = JsonFileStore(File(p.join(base.path, path)));
    await store._withLock((values) async {});
    return store;
  }

  @override
  Future<void> delete(String key) async {
    await _withLock((values) async {
      values.remove(key);
      await _flush(values);
    });
  }

  @override
  Future<List<String>> list({String prefix = ''}) => _withLock(
        (values) async =>
            (values.keys.where((key) => key.startsWith(prefix)).toList()
              ..sort()),
      );

  @override
  Future<Object?> read(String key) =>
      _withLock((values) async => _copyJson(values[key]));

  @override
  Future<void> write(String key, Object? value) async {
    if (!isJsonValue(value)) {
      throw ArgumentError.value(value, 'value', 'Value must be valid JSON.');
    }
    await _withLock((values) async {
      values[key] = _copyJson(value);
      await _flush(values);
    });
  }

  Future<Map<String, Object?>> _load() async {
    if (!await file.exists()) return {};
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?> || !isJsonValue(decoded)) {
      throw const FormatException('JSON store root must be an object.');
    }
    return decoded;
  }

  Future<void> _flush(Map<String, Object?> values) async {
    await file.parent.create(recursive: true);
    final temporary = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.$pid.tmp',
    );
    await temporary.writeAsString(jsonEncode(values), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<T> _withLock<T>(
    Future<T> Function(Map<String, Object?> values) action,
  ) async {
    await file.parent.create(recursive: true);
    final lock = File('${file.path}.lock');
    final handle = await lock.open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.exclusive);
      final values = await _load();
      return await action(values);
    } finally {
      await handle.unlock();
      await handle.close();
    }
  }

  Object? _copyJson(Object? value) =>
      value == null ? null : jsonDecode(jsonEncode(value));
}
