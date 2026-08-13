import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:dartloom_storage_file/dartloom_storage_file.dart';

final class JsonFileStore implements JsonStore {
  JsonFileStore(this.file);

  final File file;

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
      return await action(await _load());
    } finally {
      await handle.unlock();
      await handle.close();
    }
  }

  Object? _copyJson(Object? value) =>
      value == null ? null : jsonDecode(jsonEncode(value));
}

/// JSON CRUD layered over the generic binary-safe directory replica.
///
/// Both directories are resolved and owned by the application. Metadata is
/// always outside the business-data directory.
final class JsonDirectoryStore implements JsonStore, ReplicaStore {
  JsonDirectoryStore._({
    required FileDirectoryStore replica,
    required this.allowedKeys,
    required this.allowedPrefixes,
  }) : _replica = replica;

  final FileDirectoryStore _replica;
  final Set<String> allowedKeys;
  final List<String> allowedPrefixes;

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
      replica: await FileDirectoryStore.open(
        root: directory,
        metadataRoot: metadataDirectory,
        hierarchical: hierarchical,
      ),
      allowedKeys: Set.unmodifiable(allowedKeys),
      allowedPrefixes: List.unmodifiable(allowedPrefixes),
    );
    if (legacyJsonFile != null) {
      await store._migrateLegacy(legacyJsonFile, legacyKeyPrefix);
    }
    for (final entry in seed.entries) {
      if (await store.readBytes(entry.key) == null) {
        await store._writeJson(
          entry.key,
          entry.value,
          StoreMutationOrigin.migration,
        );
      }
    }
    return store;
  }

  @override
  String get identity => _replica.identity;

  @override
  Stream<StoreChange> get changes => _replica.changes;

  @override
  bool acceptsKey(String key) =>
      _replica.acceptsKey(key) &&
      (allowedKeys.isEmpty && allowedPrefixes.isEmpty ||
          allowedKeys.contains(key) ||
          allowedPrefixes.any(key.startsWith));

  void _requireAccepted(String key) {
    if (!acceptsKey(key)) {
      throw ArgumentError.value(
          key, 'key', 'Key is not accepted by this store.');
    }
  }

  @override
  Future<List<ReplicaObjectMetadata>> scan() async =>
      (await _replica.scan()).where((item) => acceptsKey(item.key)).toList();

  @override
  Future<List<String>> list({String prefix = ''}) async => (await scan())
      .where((item) => item.exists && item.key.startsWith(prefix))
      .map((item) => item.key)
      .toList()
    ..sort();

  @override
  Future<Uint8List?> readBytes(String key) {
    _requireAccepted(key);
    return _replica.readBytes(key);
  }

  @override
  Future<Object?> read(String key) async {
    if (!acceptsKey(key)) return null;
    final bytes = await readBytes(key);
    if (bytes == null) return null;
    final decoded = jsonDecode(utf8.decode(bytes));
    if (!isJsonValue(decoded)) {
      throw FormatException('Replica object $key is not valid JSON.');
    }
    return jsonDecode(jsonEncode(decoded));
  }

  @override
  Future<void> write(String key, Object? value) =>
      _writeJson(key, value, StoreMutationOrigin.application);

  Future<void> writeFromReplica(String key, Object? value) =>
      _writeJson(key, value, StoreMutationOrigin.remote);

  Future<void> _writeJson(
    String key,
    Object? value,
    StoreMutationOrigin origin,
  ) {
    if (!isJsonValue(value)) {
      throw ArgumentError.value(value, 'value', 'Value must be valid JSON.');
    }
    return writeBytes(
      key,
      Uint8List.fromList(utf8.encode(jsonEncode(value))),
      origin: origin,
    );
  }

  @override
  Future<void> writeBytes(
    String key,
    Uint8List data, {
    StoreMutationOrigin origin = StoreMutationOrigin.application,
  }) async {
    _requireAccepted(key);
    final decoded = jsonDecode(utf8.decode(data));
    if (!isJsonValue(decoded)) {
      throw FormatException('Replica object $key is not valid JSON.');
    }
    await _replica.writeBytes(key, data, origin: origin);
  }

  @override
  Future<void> delete(
    String key, {
    StoreMutationOrigin origin = StoreMutationOrigin.application,
  }) {
    _requireAccepted(key);
    return _replica.delete(key, origin: origin);
  }

  Future<void> deleteFromReplica(String key) =>
      delete(key, origin: StoreMutationOrigin.remote);

  @override
  Future<List<StoreIntent>> explicitIntents() => _replica.explicitIntents();

  @override
  Future<void> forgetExplicitIntent(String operationId) =>
      _replica.forgetExplicitIntent(operationId);

  @override
  Future<Set<String>> explicitDeletedKeys() => _replica.explicitDeletedKeys();

  @override
  Future<void> forgetExplicitDelete(String key) =>
      _replica.forgetExplicitDelete(key);

  @override
  Future<void> close() => _replica.close();

  Future<void> _migrateLegacy(File legacyFile, String prefix) async {
    final marker = File(
        '${_replica.metadataRoot.path}${Platform.pathSeparator}legacy-v3-migrated');
    if (await marker.exists() || !await legacyFile.exists()) return;
    final decoded = jsonDecode(await legacyFile.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Legacy JSON store root must be an object.');
    }
    for (final entry in decoded.entries) {
      final rawKey = entry.key;
      if (rawKey is! String || !rawKey.startsWith(prefix)) continue;
      final key = Uri.decodeComponent(rawKey.substring(prefix.length));
      if (key.isEmpty || key.startsWith('__dartloom_') || !acceptsKey(key)) {
        continue;
      }
      if (await readBytes(key) == null) {
        await _writeJson(key, entry.value, StoreMutationOrigin.migration);
      }
    }
    await marker.writeAsString(DateTime.now().toUtc().toIso8601String(),
        flush: true);
  }
}
