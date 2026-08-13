import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

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

/// Generic raw-byte directory replica. The root is supplied by the
/// application; Dartloom does not choose a business path.
final class FileDirectoryStore implements ReplicaStore {
  FileDirectoryStore(this.root, {this.hierarchical = true}) {
    _watcher = root.watch(recursive: hierarchical).listen(_onEvent);
  }

  final Directory root;
  final bool hierarchical;
  final StreamController<StoreChange> _changes =
      StreamController<StoreChange>.broadcast();
  final Set<String> _localMutationKeys = {};
  late final StreamSubscription<FileSystemEvent> _watcher;

  static Future<FileDirectoryStore> openAt({
    required Directory root,
    bool hierarchical = true,
  }) async {
    await root.create(recursive: true);
    return FileDirectoryStore(root, hierarchical: hierarchical);
  }

  @override
  String get identity => root.absolute.path;
  @override
  Stream<StoreChange> get changes => _changes.stream;

  @override
  bool acceptsKey(String key) {
    try {
      _normalizedKey(key);
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<List<ReplicaObjectMetadata>> scan() async {
    if (!await root.exists()) return const [];
    final result = <ReplicaObjectMetadata>[];
    await for (final entity
        in root.list(recursive: hierarchical, followLinks: false)) {
      if (entity is! File || entity.path.endsWith('.tmp')) continue;
      final key = _keyFor(entity.path);
      final stat = await entity.stat();
      result.add(ReplicaObjectMetadata(
        key: key,
        size: stat.size,
        modifiedAt: stat.modified,
      ));
    }
    result.sort((a, b) => a.key.compareTo(b.key));
    return result;
  }

  @override
  Future<Uint8List?> readBytes(String key) async {
    final file = _file(key);
    return await file.exists() ? file.readAsBytes() : null;
  }

  @override
  Future<void> writeBytes(String key, Uint8List data,
      {StoreMutationOrigin origin = StoreMutationOrigin.local}) async {
    final file = _file(key);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.$pid.tmp');
    await temporary.writeAsBytes(data, flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
    final normalized = _normalizedKey(key);
    if (origin == StoreMutationOrigin.local) {
      _localMutationKeys.add(normalized);
    }
    _changes.add(StoreChange(normalized, origin));
  }

  @override
  Future<void> delete(String key,
      {StoreMutationOrigin origin = StoreMutationOrigin.local}) async {
    final normalized = _normalizedKey(key);
    final file = _file(normalized);
    if (await file.exists()) await file.delete();
    if (origin == StoreMutationOrigin.local) {
      _localMutationKeys.add(normalized);
    }
    _changes.add(StoreChange(normalized, origin, deleted: true));
  }

  @override
  Future<void> close() async {
    await _watcher.cancel();
    await _changes.close();
  }

  File _file(String key) => File(
        p.join(root.path, _normalizedKey(key).replaceAll('/', p.separator)),
      );

  String _normalizedKey(String key) {
    final normalized = key.replaceAll('\\', '/');
    final parts = normalized.split('/');
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        parts.any((part) => part.isEmpty || part == '.' || part == '..') ||
        (!hierarchical && parts.length != 1)) {
      throw ArgumentError.value(key, 'key', 'Key must stay inside the store.');
    }
    return normalized;
  }

  String _keyFor(String filePath) =>
      p.relative(filePath, from: root.path).replaceAll(p.separator, '/');

  void _onEvent(FileSystemEvent event) {
    final key = _keyFor(event.path);
    if (Directory(event.path).existsSync()) return;
    if (acceptsKey(key) && !key.endsWith('.tmp')) {
      if (_localMutationKeys.remove(key)) return;
      _changes.add(StoreChange(
        key,
        StoreMutationOrigin.replica,
        deleted: event.type == FileSystemEvent.delete,
      ));
    }
  }
}
