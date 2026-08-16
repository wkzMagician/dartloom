import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:path/path.dart' as p;

final class FileObjectStore implements ObjectStore {
  FileObjectStore._({required this.root, required this.hierarchical});
  final Directory root;
  final bool hierarchical;
  final StreamController<StorageChange> _changes = StreamController.broadcast();
  StreamSubscription<FileSystemEvent>? _watcher;
  Future<void> _serial = Future.value();
  bool _closed = false;

  static Future<FileObjectStore> open(
      {required Directory root, bool hierarchical = true}) async {
    if (!p.isAbsolute(root.path)) {
      throw ArgumentError('root must be an absolute path.');
    }
    final store = FileObjectStore._(
        root: Directory(p.normalize(root.absolute.path)),
        hierarchical: hierarchical);
    final type =
        await FileSystemEntity.type(store.root.path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw ArgumentError('root cannot be a link or reparse point.');
    }
    await store.root.create(recursive: true);
    await store._cleanupTemporaryFiles();
    store._watcher =
        store.root.watch(recursive: hierarchical).listen(store._onEvent);
    return store;
  }

  @override
  String get identity => p.normalize(root.absolute.path);
  @override
  Stream<StorageChange> get changes => _changes.stream;
  @override
  bool acceptsKey(String key) {
    try {
      _normalizeKey(key);
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<List<StoredObject>> scan() => _enqueue(() async {
        final result = <StoredObject>[];
        await for (final entity
            in root.list(recursive: hierarchical, followLinks: false)) {
          if (entity is! File || _isTemporary(entity.path)) continue;
          final key = _keyFor(entity.path);
          if (!acceptsKey(key)) continue;
          await _rejectEscapingLinks(key);
          final bytes = await entity.readAsBytes();
          final stat = await entity.stat();
          result.add(StoredObject(
              key: key,
              size: bytes.length,
              modifiedAt: stat.modified.toUtc(),
              contentHash: sha256.convert(bytes).toString()));
        }
        result.sort((a, b) => a.key.compareTo(b.key));
        return result;
      });

  @override
  Future<Uint8List?> read(String key) => _enqueue(() async {
        final file = await _safeFile(key);
        return await file.exists() ? file.readAsBytes() : null;
      });
  @override
  Future<void> write(String key, Uint8List data) => _enqueue(() async {
        final target = await _safeFile(key);
        final existed = await target.exists();
        await _atomicWrite(target, data);
        _emit(StorageChange(_normalizeKey(key),
            existed ? StorageChangeKind.updated : StorageChangeKind.created));
      });
  @override
  Future<void> delete(String key) => _enqueue(() async {
        final target = await _safeFile(key);
        if (await target.exists()) {
          await target.delete();
          _emit(StorageChange(_normalizeKey(key), StorageChangeKind.deleted,
              deleted: true));
        }
      });
  @override
  Future<void> close() async {
    _closed = true;
    await _watcher?.cancel();
    await _serial;
    await _changes.close();
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final c = Completer<T>();
    _serial = _serial.then((_) async {
      try {
        c.complete(await action());
      } catch (e, s) {
        c.completeError(e, s);
      }
    });
    return c.future;
  }

  String _normalizeKey(String key) {
    final value = key.replaceAll('\\', '/');
    final parts = value.split('/');
    if (value.isEmpty ||
        p.isAbsolute(value) ||
        value.startsWith('/') ||
        parts.any((part) => part.isEmpty || part == '.' || part == '..') ||
        (!hierarchical && parts.length != 1)) {
      throw ArgumentError.value(key, 'key', 'Invalid object key.');
    }
    return value;
  }

  Future<File> _safeFile(String key) async {
    final normalized = _normalizeKey(key);
    await _rejectEscapingLinks(normalized);
    final file =
        File(p.join(root.path, normalized.replaceAll('/', p.separator)));
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FileSystemException('Object paths cannot target links.', file.path);
    }
    return file;
  }

  Future<void> _rejectEscapingLinks(String key) async {
    var cursor = root.path;
    for (final part in key.split('/').take(key.split('/').length - 1)) {
      cursor = p.join(cursor, part);
      if (await FileSystemEntity.type(cursor, followLinks: false) ==
          FileSystemEntityType.link) {
        throw FileSystemException(
            'Object paths cannot traverse links.', cursor);
      }
    }
  }

  Future<void> _atomicWrite(File target, List<int> bytes) async {
    await target.parent.create(recursive: true);
    final temp = File(
        '${target.path}.${DateTime.now().microsecondsSinceEpoch}-$pid.dartloom-tmp');
    await temp.writeAsBytes(bytes, flush: true);
    try {
      await temp.rename(target.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<void> _cleanupTemporaryFiles() async {
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is File && _isTemporary(e.path)) await e.delete();
    }
  }

  bool _isTemporary(String value) =>
      value.endsWith('.dartloom-tmp') || value.endsWith('.dartloom-old');
  String _keyFor(String path) =>
      p.relative(path, from: root.path).replaceAll(p.separator, '/');
  void _onEvent(FileSystemEvent event) {
    if (_closed || _isTemporary(event.path)) return;
    final key = _keyFor(event.path);
    if (acceptsKey(key)) {
      _emit(StorageChange(
          key,
          event.type == FileSystemEvent.delete
              ? StorageChangeKind.deleted
              : StorageChangeKind.external,
          deleted: event.type == FileSystemEvent.delete));
    }
  }

  void _emit(StorageChange change) {
    if (!_closed) _changes.add(change);
  }
}
