import 'dart:io';

import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final class TextFileStore implements TextStore {
  TextFileStore(this.root);

  final Directory root;

  static Future<TextFileStore> open({String path = 'dartloom/text'}) async {
    final base = await getApplicationSupportDirectory();
    final root = Directory(p.join(base.path, path));
    await root.create(recursive: true);
    return TextFileStore(root);
  }

  @override
  Future<void> delete(String key) async {
    final file = _file(key);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<List<String>> list({String prefix = ''}) async {
    if (!await root.exists()) return [];
    final keys = <String>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || entity.path.endsWith('.tmp')) continue;
      final key =
          p.relative(entity.path, from: root.path).replaceAll('\\', '/');
      if (key.startsWith(prefix)) keys.add(key);
    }
    return keys..sort();
  }

  @override
  Future<String?> read(String key) async {
    final file = _file(key);
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> write(String key, String value) async {
    final file = _file(key);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(value, flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  File _file(String key) {
    final normalized = p.normalize(key.replaceAll('/', p.separator));
    if (p.isAbsolute(normalized) ||
        normalized == '..' ||
        normalized.startsWith('..${p.separator}')) {
      throw ArgumentError.value(key, 'key', 'Key must stay inside the store.');
    }
    return File(p.join(root.path, normalized));
  }
}
