import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartloom_settings/dartloom_settings.dart';
import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:dartloom_sync/dartloom_sync.dart';

const _profilesPrefix = '__dartloom_profiles/';
const _syncStatePrefix = '__dartloom_sync_v3/';

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

abstract interface class ProfileScopedStore {
  SyncProfileScope get profileScope;
}

final class ProfileScopedJsonStore implements JsonStore, ProfileScopedStore {
  ProfileScopedJsonStore._(this.raw, this.profileScope);

  final JsonStore raw;
  @override
  final SyncProfileScope profileScope;
  final StreamController<LocalReplicaChange> _changes =
      StreamController.broadcast();

  static Future<ProfileScopedJsonStore> open(
    JsonStore raw,
    SyncProfileScope scope, {
    bool attachExistingData = true,
  }) async {
    final value = ProfileScopedJsonStore._(raw, scope);
    if (attachExistingData) await value._migrateLegacy();
    return value;
  }

  Stream<LocalReplicaChange> get changes => _changes.stream;

  String _prefix(String profileId) =>
      '$_profilesPrefix${Uri.encodeComponent(profileId)}/';
  String _key(String profileId, String key) =>
      '${_prefix(profileId)}${Uri.encodeComponent(key)}';

  @override
  Future<void> delete(String key) =>
      deleteFor(profileScope.activeProfileId, key,
          origin: SyncMutationOrigin.local);

  @override
  Future<List<String>> list({String prefix = ''}) =>
      listFor(profileScope.activeProfileId, prefix: prefix);

  @override
  Future<Object?> read(String key) =>
      readFor(profileScope.activeProfileId, key);

  @override
  Future<void> write(String key, Object? value) =>
      writeFor(profileScope.activeProfileId, key, value,
          origin: SyncMutationOrigin.local);

  Future<List<String>> listFor(String profileId, {String prefix = ''}) async {
    final storagePrefix = _prefix(profileId);
    final values = <String>[];
    for (final key in await raw.list(prefix: storagePrefix)) {
      final decoded = Uri.decodeComponent(key.substring(storagePrefix.length));
      if (decoded.startsWith(prefix)) values.add(decoded);
    }
    return values..sort();
  }

  Future<Object?> readFor(String profileId, String key) =>
      raw.read(_key(profileId, key));

  Future<void> writeFor(
    String profileId,
    String key,
    Object? value, {
    required SyncMutationOrigin origin,
  }) async {
    await raw.write(_key(profileId, key), value);
    _changes.add(LocalReplicaChange(key, origin));
  }

  Future<void> deleteFor(
    String profileId,
    String key, {
    required SyncMutationOrigin origin,
  }) async {
    await raw.delete(_key(profileId, key));
    _changes.add(LocalReplicaChange(key, origin));
  }

  Future<void> deleteProfile(String profileId) async {
    for (final key in await raw.list(prefix: _prefix(profileId))) {
      await raw.delete(key);
    }
  }

  Future<void> _migrateLegacy() async {
    final marker =
        '$_syncStatePrefix${profileScope.instanceName}/legacy_migrated';
    if (await raw.read(marker) == true) return;
    final legacyKeys = (await raw.list())
        .where((key) => !key.startsWith('__dartloom_'))
        .toList(growable: false);
    for (final key in legacyKeys) {
      final value = await raw.read(key);
      await raw.write(_key(profileScope.activeProfileId, key), value);
      await raw.delete(key);
    }
    await raw.write(marker, true);
  }

  Future<void> close() => _changes.close();
}

final class JsonLocalReplicaFactory implements LocalReplicaFactory {
  const JsonLocalReplicaFactory(this.stores);
  final Map<String, ProfileScopedJsonStore> stores;

  @override
  Future<LocalReplica> open(String profileId) async =>
      _CompositeJsonReplica(profileId, stores);

  @override
  Future<void> deleteProfile(String profileId) async {
    for (final store in stores.values) {
      await store.deleteProfile(profileId);
    }
  }
}

final class _CompositeJsonReplica implements LocalReplica {
  _CompositeJsonReplica(this.profileId, this.stores) {
    for (final entry in stores.entries) {
      _subscriptions.add(entry.value.changes.listen((change) {
        _changes.add(LocalReplicaChange(
            '${entry.key}/${Uri.encodeComponent(change.key)}', change.origin));
      }));
    }
  }

  final String profileId;
  final Map<String, ProfileScopedJsonStore> stores;
  final StreamController<LocalReplicaChange> _changes =
      StreamController.broadcast();
  final List<StreamSubscription<LocalReplicaChange>> _subscriptions = [];

  @override
  Stream<LocalReplicaChange> get changes => _changes.stream;

  (ProfileScopedJsonStore, String) _target(String key) {
    final slash = key.indexOf('/');
    if (slash <= 0) {
      throw FormatException('Composite sync key is invalid: $key');
    }
    final store = stores[key.substring(0, slash)];
    if (store == null) {
      throw StateError('Sync store is no longer configured: $key');
    }
    return (store, Uri.decodeComponent(key.substring(slash + 1)));
  }

  @override
  Future<List<LocalObjectMetadata>> scan() async {
    final result = <LocalObjectMetadata>[];
    for (final entry in stores.entries) {
      for (final key in await entry.value.listFor(profileId)) {
        final value = await entry.value.readFor(profileId, key);
        final data = _encodeJson(value);
        result.add(LocalObjectMetadata(
          key: '${entry.key}/${Uri.encodeComponent(key)}',
          version: _hash(data),
        ));
      }
    }
    return result..sort((a, b) => a.key.compareTo(b.key));
  }

  @override
  Future<LocalObject?> read(String key) async {
    final target = _target(key);
    final value = await target.$1.readFor(profileId, target.$2);
    if (value == null) return null;
    final data = _encodeJson(value);
    return LocalObject(key: key, data: data, version: _hash(data));
  }

  @override
  Future<bool> write(
    String key,
    Uint8List data, {
    String? expectedVersion,
    SyncMutationOrigin origin = SyncMutationOrigin.remote,
  }) async {
    final target = _target(key);
    final current = await target.$1.readFor(profileId, target.$2);
    if (expectedVersion != null &&
        (current == null || _hash(_encodeJson(current)) != expectedVersion)) {
      return false;
    }
    if (expectedVersion == null && current != null) return false;
    await target.$1.writeFor(
        profileId, target.$2, jsonDecode(utf8.decode(data)),
        origin: origin);
    return true;
  }

  @override
  Future<bool> delete(
    String key, {
    String? expectedVersion,
    SyncMutationOrigin origin = SyncMutationOrigin.remote,
  }) async {
    final target = _target(key);
    final current = await target.$1.readFor(profileId, target.$2);
    if (current == null) return true;
    if (expectedVersion != null &&
        _hash(_encodeJson(current)) != expectedVersion) {
      return false;
    }
    await target.$1.deleteFor(profileId, target.$2, origin: origin);
    return true;
  }

  @override
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _changes.close();
  }

  Uint8List _encodeJson(Object? value) =>
      Uint8List.fromList(utf8.encode(jsonEncode(value)));
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

final class JsonReconciliationStateRepository
    implements ReconciliationStateRepository {
  const JsonReconciliationStateRepository(this.raw,
      {required this.instanceName});
  final JsonStore raw;
  final String instanceName;
  String _key(String profileId) =>
      '$_syncStatePrefix$instanceName/${Uri.encodeComponent(profileId)}';

  @override
  Future<Map<String, Object?>> load(String profileId) async {
    final value = await raw.read(_key(profileId));
    return value is Map ? value.cast<String, Object?>() : <String, Object?>{};
  }

  @override
  Future<void> save(String profileId, Map<String, Object?> state) =>
      raw.write(_key(profileId), state);

  @override
  Future<List<SyncConflict>> conflicts(String profileId) async {
    final state = await load(profileId);
    final values = state['conflicts'];
    if (values is! Map) return const [];
    return values.values.whereType<Map>().map((value) {
      final map = value.cast<String, Object?>();
      return SyncConflict(
        id: map['id'] as String,
        key: map['key'] as String,
        local: _decode(map['local']),
        remote: _decode(map['remote']),
        base: _decode(map['base']),
      );
    }).toList(growable: false);
  }

  @override
  Future<void> resolve(String profileId, String conflictId,
      SyncConflictResolution resolution) async {
    final state = await load(profileId);
    final values = state['resolutions'] is Map
        ? (state['resolutions'] as Map).cast<String, Object?>()
        : <String, Object?>{};
    values[conflictId] = {
      'choice': resolution.choice.name,
      if (resolution.merged != null) 'merged': base64Encode(resolution.merged!),
    };
    state['resolutions'] = values;
    await save(profileId, state);
  }

  Uint8List? _decode(Object? value) =>
      value is String ? base64Decode(value) : null;
}
