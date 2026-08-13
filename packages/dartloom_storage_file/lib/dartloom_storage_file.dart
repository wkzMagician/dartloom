import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:path/path.dart' as p;

final class FileDirectoryStore implements ReplicaStore {
  FileDirectoryStore._({
    required this.root,
    required this.metadataRoot,
    required this.hierarchical,
  });

  final Directory root;
  final Directory metadataRoot;
  final bool hierarchical;
  final StreamController<StoreChange> _changes =
      StreamController<StoreChange>.broadcast();
  final Map<String, StoreIntent> _intents = {};
  final Map<String, _ObservedObject> _baseline = {};
  StreamSubscription<FileSystemEvent>? _watcher;
  Future<void> _serial = Future.value();
  bool _closed = false;

  static Future<FileDirectoryStore> open({
    required Directory root,
    required Directory metadataRoot,
    bool hierarchical = true,
  }) async {
    if (!p.isAbsolute(root.path) || !p.isAbsolute(metadataRoot.path)) {
      throw ArgumentError('root and metadataRoot must be absolute paths.');
    }
    final rootPath = p.normalize(root.absolute.path);
    final metadataPath = p.normalize(metadataRoot.absolute.path);
    if (_contains(rootPath, metadataPath) ||
        _contains(metadataPath, rootPath)) {
      throw ArgumentError('metadataRoot must be outside root.');
    }
    final store = FileDirectoryStore._(
      root: Directory(rootPath),
      metadataRoot: Directory(metadataPath),
      hierarchical: hierarchical,
    );
    for (final directory in [store.root, store.metadataRoot]) {
      final type = await FileSystemEntity.type(
        directory.path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.link) {
        throw ArgumentError('Replica roots cannot be links or reparse points.');
      }
    }
    await store._initialize();
    return store;
  }

  @override
  String get identity => p.normalize(root.absolute.path);

  @override
  Stream<StoreChange> get changes => _changes.stream;

  File get _journalFile => File(p.join(metadataRoot.path, 'intents-v1.json'));
  File get _baselineFile => File(p.join(metadataRoot.path, 'observed-v1.json'));

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
  Future<List<ReplicaObjectMetadata>> scan() => _enqueue(() async {
        if (!await root.exists()) {
          await root.create(recursive: true);
          _emit(const StoreChange(
            '',
            StoreMutationOrigin.external,
            kind: StoreChangeKind.rootMissing,
            deleted: true,
          ));
        }
        final current = <String, _ObservedObject>{};
        await for (final entity
            in root.list(recursive: hierarchical, followLinks: false)) {
          final type =
              await FileSystemEntity.type(entity.path, followLinks: false);
          if (type == FileSystemEntityType.link) continue;
          if (entity is! File || _isTemporary(entity.path)) continue;
          final key = _keyFor(entity.path);
          if (!acceptsKey(key)) continue;
          await _rejectEscapingLinks(key);
          final bytes = await entity.readAsBytes();
          final stat = await entity.stat();
          current[key] = _ObservedObject(
            size: bytes.length,
            modifiedAt: stat.modified.toUtc(),
            hash: sha256.convert(bytes).toString(),
          );
        }

        final result = <ReplicaObjectMetadata>[];
        for (final entry in current.entries) {
          final previous = _baseline[entry.key];
          final pending =
              _intents.values.any((intent) => intent.key == entry.key);
          final observation = previous == null
              ? pending
                  ? ReplicaObservation.trusted
                  : ReplicaObservation.unregisteredLocalObject
              : previous.hash == entry.value.hash || pending
                  ? ReplicaObservation.trusted
                  : ReplicaObservation.untrustedLocalChange;
          result.add(entry.value.metadata(entry.key, observation));
        }
        for (final entry in _baseline.entries) {
          if (current.containsKey(entry.key)) continue;
          final hasDelete = _intents.values.any(
            (intent) =>
                intent.key == entry.key &&
                intent.kind == StoreIntentKind.delete,
          );
          if (!hasDelete) {
            result.add(ReplicaObjectMetadata(
              key: entry.key,
              size: entry.value.size,
              modifiedAt: entry.value.modifiedAt,
              contentHash: entry.value.hash,
              exists: false,
              observation: ReplicaObservation.unexpectedMissing,
            ));
          }
        }
        result.sort((a, b) => a.key.compareTo(b.key));
        return result;
      });

  @override
  Future<Uint8List?> readBytes(String key) => _enqueue(() async {
        final file = await _safeFile(key);
        return await file.exists() ? file.readAsBytes() : null;
      });

  @override
  Future<void> writeBytes(
    String key,
    Uint8List data, {
    StoreMutationOrigin origin = StoreMutationOrigin.application,
  }) =>
      _enqueue(() async {
        final normalized = _normalizeKey(key);
        final target = await _safeFile(normalized);
        final existed = await target.exists();
        await _atomicWrite(target, data);
        final observed = await _observe(target);
        _baseline[normalized] = observed;
        if (origin.isAuthorizedIntent) {
          final intent = _newIntent(
            normalized,
            existed ? StoreIntentKind.update : StoreIntentKind.create,
            origin,
            contentHash: observed.hash,
          );
          _intents[intent.operationId] = intent;
        }
        await _saveMetadata();
        _emit(StoreChange(normalized, origin));
      });

  @override
  Future<void> delete(
    String key, {
    StoreMutationOrigin origin = StoreMutationOrigin.application,
  }) =>
      _enqueue(() async {
        final normalized = _normalizeKey(key);
        final target = await _safeFile(normalized);
        if (await target.exists()) await target.delete();
        _baseline.remove(normalized);
        if (origin.isAuthorizedIntent) {
          final intent = _newIntent(normalized, StoreIntentKind.delete, origin);
          _intents[intent.operationId] = intent;
        }
        await _saveMetadata();
        _emit(StoreChange(normalized, origin, deleted: true));
      });

  @override
  Future<List<StoreIntent>> explicitIntents() async {
    await _serial;
    return List.unmodifiable(_intents.values);
  }

  @override
  Future<void> forgetExplicitIntent(String operationId) => _enqueue(() async {
        if (_intents.remove(operationId) != null) await _saveMetadata();
      });

  @override
  Future<Set<String>> explicitDeletedKeys() async {
    await _serial;
    return _intents.values
        .where((intent) => intent.kind == StoreIntentKind.delete)
        .map((intent) => intent.key)
        .toSet();
  }

  @override
  Future<void> forgetExplicitDelete(String key) => _enqueue(() async {
        _intents.removeWhere(
          (_, intent) =>
              intent.key == key && intent.kind == StoreIntentKind.delete,
        );
        await _saveMetadata();
      });

  @override
  Future<void> close() async {
    _closed = true;
    await _watcher?.cancel();
    await _serial;
    await _changes.close();
  }

  Future<void> _initialize() async {
    await root.create(recursive: true);
    await metadataRoot.create(recursive: true);
    await _cleanupTemporaryFiles();
    await _loadMetadata();
    _watcher = root.watch(recursive: hierarchical).listen(
      (event) async {
        if (_closed || _isTemporary(event.path)) return;
        final key = _keyFor(event.path);
        if (!acceptsKey(key)) return;
        final current = File(event.path);
        final deleted =
            event.type == FileSystemEvent.delete || !await current.exists();
        final previous = _baseline[key];
        if (deleted && previous != null) {
          _emit(StoreChange(
            key,
            StoreMutationOrigin.external,
            kind: StoreChangeKind.unexpectedMissing,
            deleted: true,
          ));
          return;
        }
        if (!deleted) {
          final observed = await _observe(current);
          if (previous?.hash == observed.hash) return;
          _emit(StoreChange(
            key,
            StoreMutationOrigin.external,
            kind: previous == null
                ? StoreChangeKind.unregisteredLocalObject
                : StoreChangeKind.untrustedLocalChange,
          ));
        }
      },
      onError: (Object _) {
        _emit(const StoreChange(
          '',
          StoreMutationOrigin.external,
          kind: StoreChangeKind.rootMissing,
          deleted: true,
        ));
      },
    );
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _serial = _serial.then((_) async {
      try {
        completer.complete(await action());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<File> _safeFile(String key) async {
    final normalized = _normalizeKey(key);
    await _rejectEscapingLinks(normalized);
    final target = File(
      p.join(root.path, normalized.replaceAll('/', p.separator)),
    );
    final type = await FileSystemEntity.type(target.path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw FileSystemException(
        'Replica paths cannot target links or reparse points.',
        target.path,
      );
    }
    return target;
  }

  String _normalizeKey(String key) {
    final normalized = key.replaceAll('\\', '/');
    final parts = normalized.split('/');
    if (normalized.isEmpty ||
        p.isAbsolute(normalized) ||
        normalized.startsWith('/') ||
        parts.any((part) => part.isEmpty || part == '.' || part == '..') ||
        (!hierarchical && parts.length != 1)) {
      throw ArgumentError.value(key, 'key', 'Invalid replica key.');
    }
    return normalized;
  }

  Future<void> _rejectEscapingLinks(String key) async {
    var cursor = root.path;
    for (final part in key.split('/').take(key.split('/').length - 1)) {
      cursor = p.join(cursor, part);
      final type = await FileSystemEntity.type(cursor, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw FileSystemException(
            'Replica paths cannot traverse links.', cursor);
      }
    }
  }

  Future<void> _atomicWrite(File target, List<int> bytes) async {
    await target.parent.create(recursive: true);
    final nonce = '${DateTime.now().microsecondsSinceEpoch}-$pid';
    final temporary = File('${target.path}.$nonce.dartloom-tmp');
    final previous = File('${target.path}.$nonce.dartloom-old');
    await temporary.writeAsBytes(bytes, flush: true);
    if (await target.exists()) await target.rename(previous.path);
    try {
      await temporary.rename(target.path);
      if (await previous.exists()) await previous.delete();
    } on Object {
      if (!await target.exists() && await previous.exists()) {
        await previous.rename(target.path);
      }
      rethrow;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _cleanupTemporaryFiles() async {
    for (final directory in [root, metadataRoot]) {
      if (!await directory.exists()) continue;
      await for (final entity
          in directory.list(recursive: true, followLinks: false)) {
        if (entity is File && _isTemporary(entity.path)) await entity.delete();
      }
    }
  }

  bool _isTemporary(String value) =>
      value.endsWith('.dartloom-tmp') || value.endsWith('.dartloom-old');

  String _keyFor(String path) =>
      p.relative(path, from: root.path).replaceAll(p.separator, '/');

  Future<_ObservedObject> _observe(File file) async {
    final bytes = await file.readAsBytes();
    final stat = await file.stat();
    return _ObservedObject(
      size: bytes.length,
      modifiedAt: stat.modified.toUtc(),
      hash: sha256.convert(bytes).toString(),
    );
  }

  StoreIntent _newIntent(
    String key,
    StoreIntentKind kind,
    StoreMutationOrigin origin, {
    String? contentHash,
  }) {
    final now = DateTime.now().toUtc();
    return StoreIntent(
      operationId: '${now.microsecondsSinceEpoch}::$key',
      key: key,
      kind: kind,
      origin: origin,
      createdAt: now,
      contentHash: contentHash,
    );
  }

  Future<void> _loadMetadata() async {
    if (await _journalFile.exists()) {
      final root = jsonDecode(await _journalFile.readAsString());
      if (root is! Map || root['version'] != 1 || root['intents'] is! List) {
        throw const FormatException('Invalid replica intent journal.');
      }
      for (final raw in root['intents'] as List) {
        final map = (raw as Map).cast<String, Object?>();
        final intent = StoreIntent(
          operationId: map['operationId']! as String,
          key: _normalizeKey(map['key']! as String),
          kind: StoreIntentKind.values.byName(map['kind']! as String),
          origin: StoreMutationOrigin.values.byName(map['origin']! as String),
          createdAt: DateTime.parse(map['createdAt']! as String).toUtc(),
          contentHash: map['contentHash'] as String?,
        );
        if (!intent.origin.isAuthorizedIntent) {
          throw const FormatException(
              'Intent journal contains unauthorized origin.');
        }
        _intents[intent.operationId] = intent;
      }
    }
    if (await _baselineFile.exists()) {
      final root = jsonDecode(await _baselineFile.readAsString());
      if (root is! Map || root['version'] != 1 || root['objects'] is! Map) {
        throw const FormatException('Invalid replica observed state.');
      }
      for (final entry in (root['objects'] as Map).entries) {
        final value = (entry.value as Map).cast<String, Object?>();
        _baseline[_normalizeKey(entry.key as String)] = _ObservedObject(
          size: value['size']! as int,
          modifiedAt: DateTime.parse(value['modifiedAt']! as String).toUtc(),
          hash: value['hash']! as String,
        );
      }
    }
  }

  Future<void> _saveMetadata() async {
    await _atomicWrite(
      _journalFile,
      utf8.encode(jsonEncode({
        'version': 1,
        'intents': [
          for (final intent in _intents.values)
            {
              'operationId': intent.operationId,
              'key': intent.key,
              'kind': intent.kind.name,
              'origin': intent.origin.name,
              'createdAt': intent.createdAt.toIso8601String(),
              if (intent.contentHash != null) 'contentHash': intent.contentHash,
            },
        ],
      })),
    );
    await _atomicWrite(
      _baselineFile,
      utf8.encode(jsonEncode({
        'version': 1,
        'objects': {
          for (final entry in _baseline.entries)
            entry.key: {
              'size': entry.value.size,
              'modifiedAt': entry.value.modifiedAt.toIso8601String(),
              'hash': entry.value.hash,
            },
        },
      })),
    );
  }

  void _emit(StoreChange change) {
    if (!_closed) _changes.add(change);
  }

  static bool _contains(String parent, String child) {
    final relative = p.relative(child, from: parent);
    return relative == '.' ||
        (!p.isAbsolute(relative) &&
            relative != '..' &&
            !relative.startsWith('..${p.separator}'));
  }
}

final class _ObservedObject {
  const _ObservedObject({
    required this.size,
    required this.modifiedAt,
    required this.hash,
  });

  final int size;
  final DateTime modifiedAt;
  final String hash;

  ReplicaObjectMetadata metadata(String key, ReplicaObservation observation) =>
      ReplicaObjectMetadata(
        key: key,
        size: size,
        modifiedAt: modifiedAt,
        contentHash: hash,
        observation: observation,
      );
}
