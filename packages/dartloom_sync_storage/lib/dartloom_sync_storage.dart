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

/// Opens one local replica. Keys are the same relative paths in local and
/// remote replicas; profiles never namespace or delete the shared local root.
final class ReplicaStoreLocalReplicaFactory implements LocalReplicaFactory {
  const ReplicaStoreLocalReplicaFactory(this.store);

  final ReplicaStore store;

  @override
  Future<LocalReplica> open(String profileId) async => _StoreReplica(store);

  @override
  Future<void> deleteProfile(String profileId) async {
    // Profiles select remote credentials, not local namespaces. Removing a
    // profile must never erase the shared local replica.
  }
}

@Deprecated('Use ReplicaStoreLocalReplicaFactory.')
typedef JsonLocalReplicaFactory = ReplicaStoreLocalReplicaFactory;

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
}

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
      if (existingKeys is List<String>) ...existingKeys,
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
    if (keys is List<String>) {
      for (final key in keys) {
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
