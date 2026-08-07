import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:dartloom_sync/dartloom_sync.dart';

final class CompositeLocalSyncStore implements LocalSyncStore {
  const CompositeLocalSyncStore(this.stores);
  final Map<String, LocalSyncStore> stores;

  @override
  Future<void> delete(String key) {
    final target = _target(key);
    return target.$1.delete(target.$2);
  }

  @override
  Future<List<String>> list() async {
    final keys = <String>[];
    for (final entry in stores.entries) {
      for (final key in await entry.value.list()) {
        keys.add('${entry.key}/${Uri.encodeComponent(key)}');
      }
    }
    return keys..sort();
  }

  @override
  Future<Uint8List?> read(String key) {
    final target = _target(key);
    return target.$1.read(target.$2);
  }

  @override
  Future<void> write(String key, Uint8List data) {
    final target = _target(key);
    return target.$1.write(target.$2, data);
  }

  (LocalSyncStore, String) _target(String key) {
    final index = key.indexOf('/');
    if (index <= 0) {
      throw FormatException('Composite sync key is invalid: $key');
    }
    final store = stores[key.substring(0, index)];
    if (store == null) {
      throw StateError('Sync store is no longer configured: $key');
    }
    return (store, Uri.decodeComponent(key.substring(index + 1)));
  }
}

final class TextLocalSyncStore implements LocalSyncStore {
  const TextLocalSyncStore(this.store);
  final TextStore store;
  @override
  Future<void> delete(String key) => store.delete(key);
  @override
  Future<List<String>> list() => store.list();
  @override
  Future<Uint8List?> read(String key) async {
    final value = await store.read(key);
    return value == null ? null : Uint8List.fromList(utf8.encode(value));
  }

  @override
  Future<void> write(String key, Uint8List data) =>
      store.write(key, utf8.decode(data));
}

final class JsonLocalSyncStore implements LocalSyncStore {
  const JsonLocalSyncStore(this.store);
  final JsonStore store;
  @override
  Future<void> delete(String key) => store.delete(key);
  @override
  Future<List<String>> list() => store.list();
  @override
  Future<Uint8List?> read(String key) async {
    final value = await store.read(key);
    return value == null
        ? null
        : Uint8List.fromList(utf8.encode(jsonEncode(value)));
  }

  @override
  Future<void> write(String key, Uint8List data) =>
      store.write(key, jsonDecode(utf8.decode(data)));
}

final class DatabaseLocalSyncStore implements LocalSyncStore {
  const DatabaseLocalSyncStore(this.store);
  final DatabaseStore store;
  @override
  Future<void> delete(String key) {
    final parts = _parts(key);
    return store.deleteDocument(parts.$1, parts.$2);
  }

  @override
  Future<List<String>> list() async {
    final keys = <String>[];
    for (final collection in await store.collections()) {
      for (final id in await store.list(collection)) {
        keys.add(
            '${Uri.encodeComponent(collection)}/${Uri.encodeComponent(id)}');
      }
    }
    return keys..sort();
  }

  @override
  Future<Uint8List?> read(String key) async {
    final parts = _parts(key);
    final value = await store.read(parts.$1, parts.$2);
    return value == null
        ? null
        : Uint8List.fromList(utf8.encode(jsonEncode(value)));
  }

  @override
  Future<void> write(String key, Uint8List data) {
    final parts = _parts(key);
    return store.write(
      parts.$1,
      parts.$2,
      (jsonDecode(utf8.decode(data)) as Map).cast<String, Object?>(),
    );
  }

  (String, String) _parts(String key) {
    final index = key.indexOf('/');
    if (index <= 0 || index == key.length - 1) {
      throw FormatException('Database sync key must be collection/id: $key');
    }
    return (
      Uri.decodeComponent(key.substring(0, index)),
      Uri.decodeComponent(key.substring(index + 1)),
    );
  }
}

final class JsonSyncStateStore implements SyncStateStore {
  const JsonSyncStateStore(this.store, {required this.key});
  final JsonStore store;
  final String key;
  @override
  Future<Map<String, Object?>> load() async {
    final value = await store.read(key);
    return value is Map<String, Object?> ? Map.of(value) : {};
  }

  @override
  Future<void> save(Map<String, Object?> state) => store.write(key, state);
}

final class EtagSyncEngine implements SyncEngine {
  EtagSyncEngine({
    required this.local,
    required this.remote,
    required this.stateStore,
    this.merge,
  });

  final LocalSyncStore local;
  final RemoteObjectStore remote;
  final SyncStateStore stateStore;
  final SyncMergePolicy? merge;
  SyncStatus _status = SyncStatus.idle;
  final Map<String, SyncConflict> _conflicts = {};

  @override
  Future<List<SyncConflict>> conflicts() async =>
      List.unmodifiable(_conflicts.values);

  @override
  Future<SyncStatus> status() async => _status;

  @override
  Future<SyncResult> sync() async {
    if (_status == SyncStatus.syncing) {
      return const SyncResult(
        status: SyncStatus.failed,
        message: 'A sync is already running.',
      );
    }
    _status = SyncStatus.syncing;
    var uploaded = 0;
    var downloaded = 0;
    var deleted = 0;
    _conflicts.clear();
    try {
      await remote.initialize();
      final state = await stateStore.load();
      final records = _map(state['records']);
      final localKeys = (await local.list()).toSet();
      final remoteMetadata = {
        for (final item in await remote.list()) item.key: item,
      };
      final keys = <String>{
        ...localKeys,
        ...remoteMetadata.keys,
        ...records.keys,
      }.toList()
        ..sort();

      for (final key in keys) {
        final localData = await local.read(key);
        final metadata = remoteMetadata[key];
        final record = _mapOrNull(records[key]);
        final localHash = _hash(localData);
        final baseHash = record?['baseHash'] as String?;
        final previousEtag = record?['etag'] as String?;
        final localChanged =
            record == null ? localData != null : localHash != baseHash;
        final remoteChanged =
            record == null ? metadata != null : metadata?.etag != previousEtag;

        if (!localChanged && !remoteChanged) continue;
        if (localChanged && !remoteChanged) {
          try {
            if (localData == null) {
              await remote.delete(key, ifMatch: previousEtag);
              records.remove(key);
              deleted++;
            } else {
              final etag = await remote.write(
                key,
                localData,
                ifMatch: previousEtag,
                createOnly: record == null,
              );
              records[key] = _record(etag, localData);
              uploaded++;
            }
          } on SyncPreconditionException {
            final remoteObject = await remote.read(key);
            _conflicts[key] = SyncConflict(
              key: key,
              local: localData,
              remote: remoteObject?.data,
              base: _decode(record?['base']),
            );
          }
          continue;
        }
        if (!localChanged && remoteChanged) {
          final remoteObject = await remote.read(key);
          if (remoteObject == null) {
            await local.delete(key);
            records.remove(key);
            deleted++;
          } else {
            await local.write(key, remoteObject.data);
            records[key] = _record(remoteObject.etag!, remoteObject.data);
            downloaded++;
          }
          continue;
        }

        final remoteObject = await remote.read(key);
        if (localData != null &&
            remoteObject != null &&
            _hash(remoteObject.data) == localHash) {
          records[key] = _record(remoteObject.etag!, localData);
          continue;
        }
        final conflict = SyncConflict(
          key: key,
          local: localData,
          remote: remoteObject?.data,
          base: _decode(record?['base']),
        );
        final merged = merge == null ? null : await merge!(conflict);
        if (merged == null) {
          _conflicts[key] = conflict;
          continue;
        }
        await local.write(key, merged);
        try {
          final etag = await remote.write(
            key,
            merged,
            ifMatch: remoteObject?.etag,
            createOnly: remoteObject == null,
          );
          records[key] = _record(etag, merged);
          uploaded++;
        } on SyncPreconditionException {
          final latest = await remote.read(key);
          _conflicts[key] = SyncConflict(
            key: key,
            local: merged,
            remote: latest?.data,
            base: _decode(record?['base']),
          );
        }
      }

      state['records'] = records;
      state['conflicts'] = {
        for (final entry in _conflicts.entries)
          entry.key: {
            'local': _encode(entry.value.local),
            'remote': _encode(entry.value.remote),
            'base': _encode(entry.value.base),
          },
      };
      await stateStore.save(state);
      _status =
          _conflicts.isEmpty ? SyncStatus.succeeded : SyncStatus.conflicted;
      return SyncResult(
        status: _status,
        uploaded: uploaded,
        downloaded: downloaded,
        deleted: deleted,
        conflicts: _conflicts.length,
      );
    } on Object catch (error) {
      _status = SyncStatus.failed;
      return SyncResult(status: _status, message: error.toString());
    }
  }

  Map<String, Object?> _record(String etag, Uint8List data) => {
        'etag': etag,
        'baseHash': _hash(data),
        'base': base64Encode(data),
      };

  String? _hash(Uint8List? data) =>
      data == null ? null : sha256.convert(data).toString();
  String? _encode(Uint8List? data) => data == null ? null : base64Encode(data);
  Uint8List? _decode(Object? data) =>
      data is String ? base64Decode(data) : null;
  Map<String, Object?> _map(Object? value) =>
      value is Map ? value.cast<String, Object?>() : <String, Object?>{};
  Map<String, Object?>? _mapOrNull(Object? value) =>
      value is Map ? value.cast<String, Object?>() : null;
}
