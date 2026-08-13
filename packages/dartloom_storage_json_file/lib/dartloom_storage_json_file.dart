import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

/// Stores every JSON value in its own file, using the logical key as the
/// relative file path. The replica directory therefore has exactly the same
/// shape and bytes as a remote file replica.
final class JsonDirectoryStore implements ReplicaJsonStore {
  JsonDirectoryStore._({
    required this.directory,
    required this.metadataDirectory,
    required this.hierarchical,
    required this.allowedKeys,
    required this.allowedPrefixes,
  });

  final Directory directory;
  final Directory metadataDirectory;
  final bool hierarchical;
  final Set<String> allowedKeys;
  final List<String> allowedPrefixes;
  final StreamController<JsonStoreChange> _changes =
      StreamController<JsonStoreChange>.broadcast();

  static Future<JsonDirectoryStore> open({
    String path = 'Dartloom',
    String? metadataPath,
    bool hierarchical = false,
    String? legacyJsonPath,
    String legacyKeyPrefix = '',
    Set<String> allowedKeys = const {},
    List<String> allowedPrefixes = const [],
    Map<String, Object?> seed = const {},
  }) async {
    final base = await getApplicationSupportDirectory();
    return openAt(
      directory: Directory(p.join(base.path, path)),
      metadataDirectory: Directory(
        p.join(base.path, metadataPath ?? 'dartloom/sync-metadata/$path'),
      ),
      hierarchical: hierarchical,
      legacyJsonFile: legacyJsonPath == null
          ? null
          : File(p.join(base.path, legacyJsonPath)),
      legacyKeyPrefix: legacyKeyPrefix,
      allowedKeys: allowedKeys,
      allowedPrefixes: allowedPrefixes,
      seed: seed,
    );
  }

  static Future<JsonDirectoryStore> openAt({
    required Directory directory,
    required Directory metadataDirectory,
    bool hierarchical = false,
    File? legacyJsonFile,
    String legacyKeyPrefix = '',
    Set<String> allowedKeys = const {},
    List<String> allowedPrefixes = const [],
    Map<String, Object?> seed = const {},
  }) async {
    final store = JsonDirectoryStore._(
      directory: directory,
      metadataDirectory: metadataDirectory,
      hierarchical: hierarchical,
      allowedKeys: Set.unmodifiable(allowedKeys),
      allowedPrefixes: List.unmodifiable(allowedPrefixes),
    );
    await directory.create(recursive: true);
    await metadataDirectory.create(recursive: true);
    if (legacyJsonFile != null) {
      await store._migrateLegacy(legacyJsonFile, legacyKeyPrefix);
    }
    for (final entry in seed.entries) {
      if (!await store._file(entry.key).exists()) {
        await store._write(
          entry.key,
          entry.value,
          JsonStoreMutationOrigin.local,
        );
      }
    }
    return store;
  }

  @override
  String get replicaIdentity => p.normalize(directory.absolute.path);

  @override
  bool acceptsReplicaKey(String key) {
    final normalized = _normalizeKey(key);
    return allowedKeys.isEmpty && allowedPrefixes.isEmpty ||
        allowedKeys.contains(normalized) ||
        allowedPrefixes.any(normalized.startsWith);
  }

  @override
  Stream<JsonStoreChange> get changes => _changes.stream;

  File get _deletionsFile =>
      File(p.join(metadataDirectory.path, 'deletions.json'));
  File get _lockFile => File(p.join(metadataDirectory.path, 'replica.lock'));

  String _normalizeKey(String key) {
    final normalized = key.replaceAll('\\', '/');
    final parts = normalized.split('/');
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        parts.any((part) => part.isEmpty || part == '.' || part == '..') ||
        (!hierarchical && parts.length != 1)) {
      throw FormatException('Invalid replica key: $key');
    }
    return normalized;
  }

  File _file(String key) =>
      File(p.joinAll([directory.path, ..._normalizeKey(key).split('/')]));

  @override
  Future<List<String>> list({String prefix = ''}) async {
    if (!await directory.exists()) return const [];
    final values = <String>[];
    await for (final entity in directory.list(recursive: hierarchical)) {
      if (entity is! File) continue;
      final relative = p
          .relative(entity.path, from: directory.path)
          .replaceAll(p.separator, '/');
      final key = _normalizeKey(relative);
      if (key.startsWith(prefix)) values.add(key);
    }
    return values..sort();
  }

  @override
  Future<Object?> read(String key) async {
    final file = _file(key);
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    if (!isJsonValue(decoded)) {
      throw FormatException('Replica object $key is not valid JSON.');
    }
    return _copyJson(decoded);
  }

  @override
  Future<Uint8List?> readReplicaBytes(String key) async {
    final file = _file(key);
    return await file.exists() ? file.readAsBytes() : null;
  }

  @override
  Future<void> writeReplicaBytes(String key, Uint8List data) async {
    final decoded = jsonDecode(utf8.decode(data));
    if (!isJsonValue(decoded)) {
      throw FormatException('Replica object $key is not valid JSON.');
    }
    final normalized = _normalizeKey(key);
    await _withLock(() async {
      final file = _file(normalized);
      await file.parent.create(recursive: true);
      final temporary = File(
        '${file.path}.${DateTime.now().microsecondsSinceEpoch}.$pid.tmp',
      );
      await temporary.writeAsBytes(data, flush: true);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
      final deletions = await _loadDeletions();
      if (deletions.remove(normalized)) await _saveDeletions(deletions);
    });
    _changes.add(JsonStoreChange(normalized, JsonStoreMutationOrigin.replica));
  }

  @override
  Future<void> write(String key, Object? value) =>
      _write(key, value, JsonStoreMutationOrigin.local);

  @override
  Future<void> writeFromReplica(String key, Object? value) =>
      _write(key, value, JsonStoreMutationOrigin.replica);

  Future<void> _write(
    String key,
    Object? value,
    JsonStoreMutationOrigin origin,
  ) async {
    if (!isJsonValue(value)) {
      throw ArgumentError.value(value, 'value', 'Value must be valid JSON.');
    }
    final normalized = _normalizeKey(key);
    await _withLock(() async {
      final file = _file(normalized);
      await file.parent.create(recursive: true);
      final temporary = File(
        '${file.path}.${DateTime.now().microsecondsSinceEpoch}.$pid.tmp',
      );
      await temporary.writeAsString(jsonEncode(value), flush: true);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
      final deletions = await _loadDeletions();
      if (deletions.remove(normalized)) await _saveDeletions(deletions);
    });
    _changes.add(JsonStoreChange(normalized, origin));
  }

  @override
  Future<void> delete(String key) =>
      _delete(key, JsonStoreMutationOrigin.local);

  @override
  Future<void> deleteFromReplica(String key) =>
      _delete(key, JsonStoreMutationOrigin.replica);

  Future<void> _delete(String key, JsonStoreMutationOrigin origin) async {
    final normalized = _normalizeKey(key);
    await _withLock(() async {
      final file = _file(normalized);
      if (await file.exists()) await file.delete();
      final deletions = await _loadDeletions();
      final changed = origin == JsonStoreMutationOrigin.local
          ? deletions.add(normalized)
          : deletions.remove(normalized);
      if (changed) await _saveDeletions(deletions);
    });
    _changes.add(JsonStoreChange(normalized, origin));
  }

  @override
  Future<Set<String>> deletedKeys() => _withLock(_loadDeletions);

  @override
  Future<void> forgetDeletedKey(String key) => _withLock(() async {
        final deletions = await _loadDeletions();
        if (deletions.remove(_normalizeKey(key))) {
          await _saveDeletions(deletions);
        }
      });

  Future<Set<String>> _loadDeletions() async {
    if (!await _deletionsFile.exists()) return <String>{};
    final decoded = jsonDecode(await _deletionsFile.readAsString());
    if (decoded is! List) {
      throw const FormatException('Replica deletion journal must be a list.');
    }
    return decoded.whereType<String>().map(_normalizeKey).toSet();
  }

  Future<void> _saveDeletions(Set<String> values) async {
    final sorted = values.toList()..sort();
    await _deletionsFile.parent.create(recursive: true);
    final temporary = File('${_deletionsFile.path}.$pid.tmp');
    await temporary.writeAsString(jsonEncode(sorted), flush: true);
    if (await _deletionsFile.exists()) await _deletionsFile.delete();
    await temporary.rename(_deletionsFile.path);
  }

  Future<T> _withLock<T>(Future<T> Function() action) async {
    await _lockFile.parent.create(recursive: true);
    final handle = await _lockFile.open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.exclusive);
      return await action();
    } finally {
      await handle.unlock();
      await handle.close();
    }
  }

  Future<void> _migrateLegacy(File legacyFile, String prefix) async {
    final marker = File(p.join(metadataDirectory.path, 'legacy-v3-migrated'));
    if (await marker.exists() || !await legacyFile.exists()) return;
    final decoded = jsonDecode(await legacyFile.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Legacy JSON store root must be an object.');
    }
    for (final entry in decoded.entries) {
      final rawKey = entry.key;
      if (rawKey is! String || !rawKey.startsWith(prefix)) continue;
      final key = Uri.decodeComponent(rawKey.substring(prefix.length));
      if (key.isEmpty ||
          key.startsWith('__dartloom_') ||
          !acceptsReplicaKey(key)) {
        continue;
      }
      final destination = _file(key);
      if (!await destination.exists()) {
        await _write(key, entry.value, JsonStoreMutationOrigin.replica);
      }
    }
    await marker.writeAsString(DateTime.now().toUtc().toIso8601String(),
        flush: true);
  }

  Object? _copyJson(Object? value) =>
      value == null ? null : jsonDecode(jsonEncode(value));

  @override
  Future<void> close() => _changes.close();
}
