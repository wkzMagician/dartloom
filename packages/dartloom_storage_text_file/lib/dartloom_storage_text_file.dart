import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

@Deprecated('Use ObjectStore with UTF-8 encoding at the business boundary.')
final class TextFileStore {
  TextFileStore(this.root);
  final Directory root;
  static Future<TextFileStore> open({String path = 'dartloom/text'}) async {
    final root =
        Directory(p.join((await getApplicationSupportDirectory()).path, path));
    await root.create(recursive: true);
    return TextFileStore(root);
  }

  Future<void> delete(String key) async {
    final f = _file(key);
    if (await f.exists()) await f.delete();
  }

  Future<List<String>> list({String prefix = ''}) async {
    if (!await root.exists()) return [];
    final keys = <String>[];
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is File) {
        final k = p.relative(e.path, from: root.path).replaceAll('\\', '/');
        if (k.startsWith(prefix)) keys.add(k);
      }
    }
    return keys..sort();
  }

  Future<String?> read(String key) async {
    final f = _file(key);
    return await f.exists() ? f.readAsString() : null;
  }

  Future<void> write(String key, String value) async {
    final f = _file(key);
    await f.parent.create(recursive: true);
    await f.writeAsString(value, flush: true);
  }

  File _file(String key) {
    final n = p.normalize(key.replaceAll('/', p.separator));
    if (p.isAbsolute(n) || n == '..' || n.startsWith('..${p.separator}'))
      throw ArgumentError.value(key, 'key');
    return File(p.join(root.path, n));
  }
}
