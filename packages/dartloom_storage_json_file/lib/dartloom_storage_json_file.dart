import 'dart:convert';
import 'dart:io';

@Deprecated('Use ObjectStore with JSON encoding at the business boundary.')
final class JsonFileStore {
  JsonFileStore(this.file);
  final File file;
  Future<Map<String, Object?>> _load() async {
    if (!await file.exists()) return {};
    final value = jsonDecode(await file.readAsString());
    if (value is! Map) {
      throw const FormatException('JSON store root must be an object.');
    }
    return value.cast<String, Object?>();
  }

  Future<T> _with<T>(Future<T> Function(Map<String, Object?>) action) async {
    await file.parent.create(recursive: true);
    final values = await _load();
    final result = await action(values);
    await file.writeAsString(jsonEncode(values), flush: true);
    return result;
  }

  Future<List<String>> list({String prefix = ''}) async =>
      (await _load()).keys.where((k) => k.startsWith(prefix)).toList()..sort();
  Future<Object?> read(String key) async => (await _load())[key];
  Future<void> write(String key, Object? value) => _with((v) async {
        v[key] = value;
      });
  Future<void> delete(String key) => _with((v) async {
        v.remove(key);
      });
}
