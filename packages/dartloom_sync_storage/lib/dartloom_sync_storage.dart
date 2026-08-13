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

/// Opens one local replica. Keys are passed through unchanged: a key is the
/// relative path on both the local filesystem and the remote backend.
final class JsonLocalReplicaFactory implements LocalReplicaFactory {
  const JsonLocalReplicaFactory(this.store);

  final ReplicaJsonStore store;

  @override
  Future<LocalReplica> open(String profileId) async => _JsonReplica(store);

  @override
  Future<void> deleteProfile(String profileId) async {
    // Profiles select remote credentials, not local namespaces. Removing a
    // profile must never erase the shared local replica.
  }
}

final class _JsonReplica implements LocalReplica {
  _JsonReplica(this.store) {
    _subscription = store.changes.listen((change) {
      _changes.add(LocalReplicaChange(
        change.key,
        change.origin == JsonStoreMutationOrigin.local
            ? SyncMutationOrigin.local
            : SyncMutationOrigin.remote,
      ));
    });
  }

  final ReplicaJsonStore store;
  final StreamController<LocalReplicaChange> _changes =
      StreamController.broadcast();
  late final StreamSubscription<JsonStoreChange> _subscription;

  @override
  String get identity => store.replicaIdentity;

  @override
  bool acceptsKey(String key) => store.acceptsReplicaKey(key);

  @override
  Stream<LocalReplicaChange> get changes => _changes.stream;

  @override
  Future<Set<String>> deletedKeys() => store.deletedKeys();

  @override
  Future<void> forgetDeletedKey(String key) => store.forgetDeletedKey(key);

  @override
  Future<List<LocalObjectMetadata>> scan() async {
    final result = <LocalObjectMetadata>[];
    for (final key in await store.list()) {
      if (!acceptsKey(key)) continue;
      final data = await store.readReplicaBytes(key);
      if (data == null) continue;
      result.add(LocalObjectMetadata(key: key, version: _hash(data)));
    }
    return result..sort((a, b) => a.key.compareTo(b.key));
  }

  @override
  Future<LocalObject?> read(String key) async {
    final data = await store.readReplicaBytes(key);
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
    final value = jsonDecode(utf8.decode(data));
    if (origin == SyncMutationOrigin.remote) {
      await store.writeReplicaBytes(key, data);
    } else {
      await store.write(key, value);
    }
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
        await store.deleteFromReplica(key);
      }
      return true;
    }
    if (expectedVersion != null && current.version != expectedVersion) {
      return false;
    }
    if (origin == SyncMutationOrigin.remote) {
      await store.deleteFromReplica(key);
    } else {
      await store.delete(key);
    }
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
    final keys = keysValue is List<String> ? keysValue : const <String>[];
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
      'sync.$instanceName.v4.state.${Uri.encodeComponent(profileId)}';

  @override
  Future<Map<String, Object?>> load(String profileId) async {
    final value = await settings.read(_key(profileId));
    if (value is! String || value.isEmpty) return <String, Object?>{};
    final decoded = jsonDecode(value);
    return decoded is Map
        ? decoded.cast<String, Object?>()
        : <String, Object?>{};
  }

  @override
  Future<void> save(String profileId, Map<String, Object?> state) =>
      settings.write(_key(profileId), jsonEncode(state));

  @override
  Future<List<SyncConflict>> conflicts(String profileId) async {
    final values = (await load(profileId))['conflicts'];
    if (values is! Map) return const [];
    return values.values.whereType<Map>().map((value) {
      final map = value.cast<String, Object?>();
      return SyncConflict(
        id: map['id'] as String,
        key: map['key'] as String,
        local: _decodeStateBytes(map['local']),
        remote: _decodeStateBytes(map['remote']),
        base: _decodeStateBytes(map['base']),
      );
    }).toList(growable: false);
  }

  @override
  Future<void> resolve(
    String profileId,
    String conflictId,
    SyncConflictResolution resolution,
  ) async {
    final state = await load(profileId);
    final resolutions = state['resolutions'] is Map
        ? (state['resolutions'] as Map).cast<String, Object?>()
        : <String, Object?>{};
    resolutions[conflictId] = {
      'choice': resolution.choice.name,
      if (resolution.merged != null) 'merged': base64Encode(resolution.merged!),
    };
    state['resolutions'] = resolutions;
    await save(profileId, state);
  }

  Uint8List? _decodeStateBytes(Object? value) =>
      value is String ? base64Decode(value) : null;
}
