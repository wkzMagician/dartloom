import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartloom_settings/dartloom_settings.dart';
import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:dartloom_sync/dartloom_sync.dart';

final class SyncProfileScope {
  SyncProfileScope._(this._settings, this.instanceName, this._activeProfileId);

  final SettingsStore _settings;
  final String instanceName;
  String _activeProfileId;
  final StreamController<String> _changes = StreamController.broadcast();

  static Future<SyncProfileScope> open(
      SettingsStore settings, String instanceName) async {
    final stored = await settings.read('sync.$instanceName.active_profile');
    final id = stored is String && stored.isNotEmpty ? stored : 'default';
    if (stored == null) {
      await settings.write('sync.$instanceName.active_profile', id);
    }
    return SyncProfileScope._(settings, instanceName, id);
  }

  String get activeProfileId => _activeProfileId;
  Stream<String> get changes => _changes.stream;

  Future<void> activate(String profileId) async {
    if (profileId == _activeProfileId) return;
    await _settings.write('sync.$instanceName.active_profile', profileId);
    _activeProfileId = profileId;
    _changes.add(profileId);
  }

  Future<void> dispose() => _changes.close();
}

final class JournaledObjectStore implements ObjectStore {
  JournaledObjectStore._(this.objects, this.metadata)
      : _changes = StreamController.broadcast();
  final ObjectStore objects;
  final ObjectStore metadata;
  final StreamController<StorageChange> _changes;
  final StreamController<LocalReplicaChange> _mutationChanges =
      StreamController.broadcast();
  final Map<String, SyncMutationOrigin> _pendingOrigins = {};
  Future<void> _serial = Future.value();
  bool _closed = false;

  static Future<JournaledObjectStore> open({
    required ObjectStore objects,
    required ObjectStore metadata,
  }) async {
    if (identical(objects, metadata)) {
      throw ArgumentError(
          'Object data and journal metadata must be separate stores.');
    }
    final store = JournaledObjectStore._(objects, metadata);
    store._subscription = objects.changes.listen(store._onObjectChange);
    await store._recoverPrepared();
    return store;
  }

  late final StreamSubscription<StorageChange> _subscription;
  @override
  String get identity => objects.identity;
  @override
  bool acceptsKey(String key) => objects.acceptsKey(key);
  @override
  Stream<StorageChange> get changes => _changes.stream;
  Stream<LocalReplicaChange> get mutationChanges => _mutationChanges.stream;
  @override
  Future<List<StoredObject>> scan() => objects.scan();
  @override
  Future<Uint8List?> read(String key) => objects.read(key);
  @override
  Future<void> write(String key, Uint8List data) =>
      _mutate(key, data, deleted: false, origin: SyncMutationOrigin.local);

  Future<void> writeRemote(String key, Uint8List data) => _mutate(key, data,
      deleted: false, origin: SyncMutationOrigin.remote, journal: false);
  @override
  Future<void> delete(String key) =>
      _mutate(key, null, deleted: true, origin: SyncMutationOrigin.local);

  Future<void> deleteRemote(String key) => _mutate(key, null,
      deleted: true, origin: SyncMutationOrigin.remote, journal: false);

  Future<List<PendingLocalMutation>> intents() => _enqueue(() async {
        final operations = await _operations();
        return [
          for (final operation in operations.values)
            if (operation['state'] != 'acknowledged' &&
                operation['origin'] == 'local')
              PendingLocalMutation(
                operationId: operation['id']! as String,
                key: operation['key']! as String,
                kind: (operation['kind'] == 'delete')
                    ? LocalMutationKind.delete
                    : (operation['kind'] == 'create')
                        ? LocalMutationKind.create
                        : LocalMutationKind.update,
                createdAt: DateTime.parse(operation['createdAt']! as String),
                contentHash: operation['resultHash'] as String?,
              ),
        ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      });

  Future<void> forgetIntent(String operationId) => _enqueue(() async {
        final operation = (await _operations())[operationId];
        if (operation == null) return;
        await _writeEvent(operation, 'acknowledged');
        await _compactLocked(DateTime.now().toUtc());
      });

  /// Removes acknowledged journal events while retaining delete tombstones
  /// for the configured conflict window.
  Future<void> compact({DateTime? now}) =>
      _enqueue(() => _compactLocked(now?.toUtc() ?? DateTime.now().toUtc()));

  Future<void> _mutate(
    String key,
    Uint8List? data, {
    required bool deleted,
    required SyncMutationOrigin origin,
    bool journal = true,
  }) async {
    if (!acceptsKey(key)) throw ArgumentError.value(key, 'key');
    await _enqueue(() async {
      final before = await objects.read(key);
      final beforeHash = _hash(before);
      final afterHash = deleted ? null : _hash(data);
      final operation = <String, Object?>{
        'id': _operationId(key),
        'key': key,
        'kind': deleted
            ? 'delete'
            : before == null
                ? 'create'
                : 'update',
        'origin': origin == SyncMutationOrigin.local ? 'local' : 'remote',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'expectedHash': beforeHash,
        'resultHash': afterHash,
        if (!deleted) 'payload': base64Encode(data!),
        'state': 'prepared',
      };
      if (journal && origin == SyncMutationOrigin.local) {
        await _writeEvent(operation, 'prepared');
      }
      _pendingOrigins[key] = origin;
      try {
        if (deleted) {
          await objects.delete(key);
        } else {
          await objects.write(key, data!);
        }
      } catch (_) {
        _pendingOrigins.remove(key);
        rethrow;
      }
      if (journal && origin == SyncMutationOrigin.local) {
        await _writeEvent(operation, 'applied');
      }
      await Future<void>.delayed(Duration.zero);
      _pendingOrigins.remove(key);
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final c = Completer<T>();
    _serial = _serial.then((_) async {
      try {
        c.complete(await _exclusive(action));
      } catch (e, s) {
        c.completeError(e, s);
      }
    });
    return c.future;
  }

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final store = metadata;
    if (store is ExclusiveObjectStore) {
      return (store as ExclusiveObjectStore).withExclusiveLock(action);
    }
    return action();
  }

  Future<void> _recoverPrepared() => _enqueue(() async {
        for (final operation in (await _operations()).values) {
          if (operation['state'] != 'prepared' ||
              operation['origin'] != 'local') {
            continue;
          }
          final key = operation['key']! as String;
          final current = await objects.read(key);
          final currentHash = _hash(current);
          final resultHash = operation['resultHash'] as String?;
          if (currentHash == resultHash) {
            await _writeEvent(operation, 'applied');
            continue;
          }
          if (currentHash != operation['expectedHash']) {
            throw StateError('Journal recovery conflict for $key.');
          }
          final kind = operation['kind'];
          _pendingOrigins[key] = SyncMutationOrigin.local;
          if (kind == 'delete') {
            await objects.delete(key);
          } else {
            await objects.write(
                key,
                Uint8List.fromList(
                    base64Decode(operation['payload']! as String)));
          }
          await _writeEvent(operation, 'applied');
        }
      });

  Future<Map<String, Map<String, Object?>>> _operations() async {
    final values = <String, Map<String, Object?>>{};
    for (final item in await metadata.scan()) {
      if (!item.key.startsWith(_eventPrefix) || !item.key.endsWith('.json')) {
        continue;
      }
      final bytes = await metadata.read(item.key);
      if (bytes == null) continue;
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        throw const FormatException('Invalid journal event.');
      }
      final event = decoded.cast<String, Object?>();
      final id = event['id'];
      if (id is! String ||
          event['sequence'] is! int ||
          event['checksum'] != _checksum(event)) {
        throw const FormatException('Corrupt journal event.');
      }
      final previous = values[id];
      final previousState = previous?['state'];
      final rank = {'prepared': 0, 'applied': 1, 'acknowledged': 2};
      if (previous == null ||
          (rank[event['state']] ?? -1) >= (rank[previousState] ?? -1)) {
        values[id] = event;
      }
    }
    return values;
  }

  Future<void> _writeEvent(Map<String, Object?> operation, String state) async {
    final event = <String, Object?>{...operation, 'state': state};
    event['sequence'] = await _nextSequence();
    event['checksum'] = _checksum(event);
    final id = event['id']! as String;
    final sequence = event['sequence']! as int;
    final eventKey =
        '$_eventPrefix${sequence.toString().padLeft(20, '0')}-$id-$state.json';
    await metadata.write(
        eventKey, Uint8List.fromList(utf8.encode(jsonEncode(event))));
  }

  void _onObjectChange(StorageChange change) {
    final origin = _pendingOrigins.remove(change.key);
    _changes
        .add(StorageChange(change.key, change.kind, deleted: change.deleted));
    _mutationChanges.add(
        LocalReplicaChange(change.key, origin ?? SyncMutationOrigin.local));
  }

  Future<int> _nextSequence() async {
    final bytes = await metadata.read(_sequenceKey);
    final current = bytes == null ? 0 : int.tryParse(utf8.decode(bytes));
    if (current == null) {
      throw const FormatException('Corrupt journal sequence.');
    }
    final next = current + 1;
    await metadata.write(
        _sequenceKey, Uint8List.fromList(utf8.encode('$next')));
    return next;
  }

  Future<void> _compactLocked(DateTime now) async {
    final cutoff = now.subtract(const Duration(days: 30));
    for (final operation in (await _operations()).values) {
      if (operation['state'] != 'acknowledged') continue;
      final created = DateTime.parse(operation['createdAt']! as String);
      if (operation['kind'] == 'delete' && created.isAfter(cutoff)) continue;
      for (final item in await metadata.scan()) {
        if (!item.key.startsWith(_eventPrefix) || !item.key.endsWith('.json')) {
          continue;
        }
        final bytes = await metadata.read(item.key);
        if (bytes == null) continue;
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is Map && decoded['id'] == operation['id']) {
          await metadata.delete(item.key);
        }
      }
    }
  }

  String _operationId(String key) =>
      '${DateTime.now().microsecondsSinceEpoch}-${key.hashCode.abs()}';
  String? _hash(Uint8List? value) =>
      value == null ? null : sha256.convert(value).toString();
  String _checksum(Map<String, Object?> value) {
    final copy = Map<String, Object?>.from(value)..remove('checksum');
    return sha256.convert(utf8.encode(jsonEncode(copy))).toString();
  }

  static const _eventPrefix = '__dartloom_journal/v1/events/';
  static const _sequenceKey = '__dartloom_journal/v1/sequence';
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    await _changes.close();
    await _mutationChanges.close();
    await objects.close();
    if (!identical(objects, metadata)) await metadata.close();
  }
}

final class _JournaledLocalReplica implements LocalReplica {
  _JournaledLocalReplica(this.store, {this.closeStore = true}) {
    _subscription = store.mutationChanges.listen(_changes.add);
  }
  final JournaledObjectStore store;
  final bool closeStore;
  final StreamController<LocalReplicaChange> _changes =
      StreamController.broadcast();
  late final StreamSubscription<LocalReplicaChange> _subscription;
  @override
  String get identity => store.identity;
  @override
  bool acceptsKey(String key) => store.acceptsKey(key);
  @override
  Stream<LocalReplicaChange> get changes => _changes.stream;
  @override
  Future<List<PendingLocalMutation>> intents() => store.intents();
  @override
  Future<void> forgetIntent(String operationId) =>
      store.forgetIntent(operationId);
  @override
  Future<List<LocalObjectMetadata>> scan() async => [
        for (final item in await store.scan())
          LocalObjectMetadata(key: item.key, version: item.contentHash ?? '')
      ];
  @override
  Future<LocalObject?> read(String key) async {
    final data = await store.read(key);
    return data == null
        ? null
        : LocalObject(key: key, data: data, version: _hash(data));
  }

  @override
  Future<bool> write(String key, Uint8List data,
      {String? expectedVersion,
      SyncMutationOrigin origin = SyncMutationOrigin.remote}) async {
    final current = await read(key);
    if ((expectedVersion != null && current?.version != expectedVersion) ||
        (expectedVersion == null && current != null)) {
      return false;
    }
    if (origin == SyncMutationOrigin.remote) {
      await store.writeRemote(key, data);
    } else {
      await store.write(key, data);
    }
    return true;
  }

  @override
  Future<bool> delete(String key,
      {String? expectedVersion,
      SyncMutationOrigin origin = SyncMutationOrigin.remote}) async {
    final current = await read(key);
    if (current == null) return true;
    if (expectedVersion != null && current.version != expectedVersion) {
      return false;
    }
    if (origin == SyncMutationOrigin.remote) {
      await store.deleteRemote(key);
    } else {
      await store.delete(key);
    }
    return true;
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await _changes.close();
    if (closeStore) {
      await store.close();
    }
  }

  String _hash(Uint8List data) => sha256.convert(data).toString();
}

final class JournaledObjectStoreLocalReplicaFactory
    implements LocalReplicaFactory {
  const JournaledObjectStoreLocalReplicaFactory(this.store);
  final JournaledObjectStore store;
  @override
  Future<LocalReplica> open(String profileId) async =>
      _JournaledLocalReplica(store, closeStore: false);
  @override
  Future<void> deleteProfile(String profileId) async {}
}

final class ObjectStoreLocalReplicaFactory implements LocalReplicaFactory {
  const ObjectStoreLocalReplicaFactory(
      {required this.objects, required this.metadata});
  final ObjectStore objects;
  final ObjectStore metadata;
  @override
  Future<LocalReplica> open(String profileId) async => _JournaledLocalReplica(
      await JournaledObjectStore.open(objects: objects, metadata: metadata));
  @override
  Future<void> deleteProfile(String profileId) async {}
}

typedef ReplicaStoreLocalReplicaFactory = ObjectStoreLocalReplicaFactory;
typedef JsonLocalReplicaFactory = ObjectStoreLocalReplicaFactory;

/* legacy adapter removed: ObjectStore is now the storage boundary.
final class _StoreReplica implements LocalReplica {
  _StoreReplica(this.store) {
    _subscription = store.changes.listen((change) {
      _changes.add(LocalReplicaChange(
        change.key,
        change.origin.isAuthorizedIntent
            ? SyncMutationOrigin.local
            : SyncMutationOrigin.remote,
      ));
    });
  }

  final ReplicaStore store;
  final StreamController<LocalReplicaChange> _changes =
      StreamController.broadcast();
  late final StreamSubscription<StoreChange> _subscription;

  @override
  String get identity => store.identity;

  @override
  bool acceptsKey(String key) => store.acceptsKey(key);

  @override
  Stream<LocalReplicaChange> get changes => _changes.stream;

  @override
  Future<List<StoreIntent>> intents() => store.explicitIntents();

  @override
  Future<void> forgetIntent(String operationId) =>
      store.forgetExplicitIntent(operationId);

  @override
  Future<List<LocalObjectMetadata>> scan() async {
    return [
      for (final item in await store.scan())
        LocalObjectMetadata(
          key: item.key,
          version: item.contentHash ?? '',
          exists: item.exists,
          observation: item.observation,
        ),
    ];
  }

  @override
  Future<LocalObject?> read(String key) async {
    final data = await store.readBytes(key);
    if (data == null) return null;
    return LocalObject(key: key, data: data, version: _hash(data));
  }

  @override
  Future<bool> write(
    String key,
    Uint8List data, {
    String? expectedVersion,
    SyncMutationOrigin origin = SyncMutationOrigin.remote,
  }) async {
    final current = await read(key);
    if (expectedVersion != null && current?.version != expectedVersion) {
      return false;
    }
    if (expectedVersion == null && current != null) return false;
    await store.writeBytes(
      key,
      data,
      origin: origin == SyncMutationOrigin.remote
          ? StoreMutationOrigin.recovery
          : StoreMutationOrigin.application,
    );
    return true;
  }

  @override
  Future<bool> delete(
    String key, {
    String? expectedVersion,
    SyncMutationOrigin origin = SyncMutationOrigin.remote,
  }) async {
    final current = await read(key);
    if (current == null) {
      if (origin == SyncMutationOrigin.remote) {
        await store.delete(key, origin: StoreMutationOrigin.recovery);
      }
      return true;
    }
    if (expectedVersion != null && current.version != expectedVersion) {
      return false;
    }
    await store.delete(
      key,
      origin: origin == SyncMutationOrigin.remote
          ? StoreMutationOrigin.recovery
          : StoreMutationOrigin.application,
    );
    return true;
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await _changes.close();
  }

  String _hash(Uint8List value) => sha256.convert(value).toString();
} */

final class SettingsSyncProfileRepository implements SyncProfileRepository {
  SettingsSyncProfileRepository({
    required this.instanceName,
    required this.metadata,
    required this.secretsStore,
    required this.scope,
  });

  final String instanceName;
  final SettingsStore metadata;
  final SettingsStore secretsStore;
  final SyncProfileScope scope;
  String get _profilesKey => 'sync.$instanceName.profiles';

  @override
  Future<List<SyncProfile>> list() async {
    final encoded = await metadata.read(_profilesKey);
    final profiles = <SyncProfile>[];
    if (encoded is String && encoded.isNotEmpty) {
      final decoded = jsonDecode(encoded);
      if (decoded is List) {
        for (final item in decoded.whereType<Map>()) {
          final map = item.cast<String, Object?>();
          profiles.add(SyncProfile(
            id: map['id'] as String,
            label: map['label'] as String,
            backend: map['backend'] as String? ?? '',
            options:
                (map['options'] as Map?)?.cast<String, Object?>() ?? const {},
            isActive: map['id'] == scope.activeProfileId,
          ));
        }
      }
    }
    if (profiles.isEmpty) {
      profiles.add(SyncProfile(
          id: 'default', label: 'Local', backend: '', isActive: true));
      await _saveList(profiles);
    }
    return profiles;
  }

  @override
  Future<SyncProfile?> active() async {
    final values = await list();
    return values
            .where((value) => value.id == scope.activeProfileId)
            .firstOrNull ??
        values.firstOrNull;
  }

  @override
  Future<Map<String, String>> secrets(String profileId) async {
    final keysValue = await metadata
        .read('sync.$instanceName.profile.$profileId.secret_keys');
    // SecureSettingsStore decodes JSON values, so a persisted string list is
    // returned as List<dynamic> rather than List<String>. Normalize the
    // decoded value instead of requiring the runtime generic type to match.
    final keys = keysValue is List
        ? keysValue.whereType<String>().toList(growable: false)
        : const <String>[];
    final result = <String, String>{};
    for (final key in keys) {
      final value = await secretsStore
          .read('sync.$instanceName.profile.$profileId.secret.$key');
      if (value is String) result[key] = value;
    }
    return result;
  }

  @override
  Future<SyncProfile> save(SyncProfileDraft draft) async {
    final values = await list();
    final id = draft.id ?? 'profile-${DateTime.now().microsecondsSinceEpoch}';
    final next = SyncProfile(
      id: id,
      label: draft.label,
      backend: draft.backend,
      options: Map.unmodifiable(draft.options),
      isActive: id == scope.activeProfileId,
    );
    final index = values.indexWhere((value) => value.id == id);
    if (index < 0) {
      values.add(next);
    } else {
      values[index] = next;
    }
    final existingKeys =
        await metadata.read('sync.$instanceName.profile.$id.secret_keys');
    final keys = <String>{
      if (existingKeys is List) ...existingKeys.whereType<String>(),
      ...draft.secrets.keys
    }.toList()
      ..sort();
    for (final entry in draft.secrets.entries) {
      await secretsStore.write(
          'sync.$instanceName.profile.$id.secret.${entry.key}', entry.value);
    }
    await metadata.write('sync.$instanceName.profile.$id.secret_keys', keys);
    await _saveList(values);
    return next;
  }

  @override
  Future<void> activate(String profileId) async {
    final values = await list();
    if (!values.any((value) => value.id == profileId)) {
      throw StateError('Unknown sync profile $profileId.');
    }
    await scope.activate(profileId);
  }

  @override
  Future<void> delete(String profileId, {required bool deleteLocalData}) async {
    final values = await list();
    values.removeWhere((value) => value.id == profileId);
    final keys = await metadata
        .read('sync.$instanceName.profile.$profileId.secret_keys');
    if (keys is List) {
      for (final key in keys.whereType<String>()) {
        await secretsStore
            .remove('sync.$instanceName.profile.$profileId.secret.$key');
      }
    }
    await metadata.remove('sync.$instanceName.profile.$profileId.secret_keys');
    await _saveList(values);
  }

  Future<void> _saveList(List<SyncProfile> values) => metadata.write(
        _profilesKey,
        jsonEncode([
          for (final value in values)
            {
              'id': value.id,
              'label': value.label,
              'backend': value.backend,
              'options': value.options
            },
        ]),
      );
}

/// Keeps reconciliation metadata outside the replicated dataset.
final class SettingsReconciliationStateRepository
    implements ReconciliationStateRepository {
  const SettingsReconciliationStateRepository(
    this.settings, {
    required this.instanceName,
  });

  final SettingsStore settings;
  final String instanceName;

  String _key(String profileId) =>
      'sync.$instanceName.v5.state.${Uri.encodeComponent(profileId)}';

  @override
  Future<SyncState> load(String profileId) async {
    final value = await settings.read(_key(profileId));
    if (value == null) return const SyncState();
    if (value is! String || value.isEmpty) {
      throw const FormatException('Sync state must be encoded JSON.');
    }
    final decoded = jsonDecode(value);
    if (decoded is! Map || decoded['version'] != 1) {
      throw const FormatException('Unsupported or corrupt sync state.');
    }
    final root = decoded.cast<String, Object?>();
    final records = <String, SyncRecord>{};
    for (final entry in _map(root['records']).entries) {
      final record = _map(entry.value);
      records[entry.key] = SyncRecord(
        remoteVersion: record['remoteVersion'] as String?,
        baseHash: record['baseHash'] as String?,
        base: _decodeStateBytes(record['base']),
        deletedAt: record['deletedAt'] is String
            ? DateTime.parse(record['deletedAt']! as String).toUtc()
            : null,
      );
    }
    final conflicts = <String, StoredConflict>{};
    for (final entry in _map(root['conflicts']).entries) {
      final map = _map(entry.value);
      final conflict = SyncConflict(
        id: map['id']! as String,
        key: map['key']! as String,
        local: _decodeStateBytes(map['local']),
        remote: _decodeStateBytes(map['remote']),
        base: _decodeStateBytes(map['base']),
      );
      conflicts[entry.key] = StoredConflict(conflict);
    }
    final resolutions = <String, StoredResolution>{};
    for (final entry in _map(root['resolutions']).entries) {
      final map = _map(entry.value);
      resolutions[entry.key] = StoredResolution(SyncConflictResolution(
        SyncConflictChoice.values.byName(map['choice']! as String),
        merged: _decodeStateBytes(map['merged']),
      ));
    }
    return SyncState(
      fingerprint: root['fingerprint'] as String?,
      cursor: root['cursor'] as String?,
      records: Map.unmodifiable(records),
      remoteVersions: Map.unmodifiable(
        _map(root['remoteVersions']).map(
          (key, value) => MapEntry(key, value! as String),
        ),
      ),
      conflicts: Map.unmodifiable(conflicts),
      resolutions: Map.unmodifiable(resolutions),
    );
  }

  @override
  Future<void> save(String profileId, SyncState state) => settings.write(
        _key(profileId),
        jsonEncode({
          'version': state.version,
          'fingerprint': state.fingerprint,
          'cursor': state.cursor,
          'records': {
            for (final entry in state.records.entries)
              entry.key: {
                'remoteVersion': entry.value.remoteVersion,
                'baseHash': entry.value.baseHash,
                if (entry.value.base != null)
                  'base': base64Encode(entry.value.base!),
                if (entry.value.deletedAt != null)
                  'deletedAt': entry.value.deletedAt!.toIso8601String(),
              },
          },
          'remoteVersions': state.remoteVersions,
          'conflicts': {
            for (final entry in state.conflicts.entries)
              entry.key: {
                'id': entry.value.value.id,
                'key': entry.value.value.key,
                'local': _encodeStateBytes(entry.value.value.local),
                'remote': _encodeStateBytes(entry.value.value.remote),
                'base': _encodeStateBytes(entry.value.value.base),
              },
          },
          'resolutions': {
            for (final entry in state.resolutions.entries)
              entry.key: {
                'choice': entry.value.value.choice.name,
                if (entry.value.value.merged != null)
                  'merged': base64Encode(entry.value.value.merged!),
              },
          },
        }),
      );

  @override
  Future<List<SyncConflict>> conflicts(String profileId) async {
    return (await load(profileId))
        .conflicts
        .values
        .map((value) => value.value)
        .toList(growable: false);
  }

  @override
  Future<void> resolve(
    String profileId,
    String conflictId,
    SyncConflictResolution resolution,
  ) async {
    final state = await load(profileId);
    final resolutions = Map<String, StoredResolution>.of(state.resolutions)
      ..[conflictId] = StoredResolution(resolution);
    await save(profileId, state.copyWith(resolutions: resolutions));
  }

  Map<String, Object?> _map(Object? value) =>
      value is Map ? value.cast<String, Object?>() : const {};
  String? _encodeStateBytes(Uint8List? value) =>
      value == null ? null : base64Encode(value);
  Uint8List? _decodeStateBytes(Object? value) =>
      value is String ? base64Decode(value) : null;
}
