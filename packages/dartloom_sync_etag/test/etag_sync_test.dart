import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartloom_sync/dartloom_sync.dart';
import 'package:dartloom_sync_etag/dartloom_sync_etag.dart';
import 'package:test/test.dart';

void main() {
  test('uploads, downloads, deletes, and preserves conflicts', () async {
    final local = _Local();
    final remote = _Remote();
    final state = _State();
    const reconciler = EtagReconciler();
    local.externalWrite('a', _bytes('local'));
    var result = await reconciler.reconcile(_request(local, remote, state));
    expect(result.uploaded, 1);
    remote.externalWrite('a', _bytes('remote'));
    result = await reconciler.reconcile(_request(local, remote, state));
    expect(result.downloaded, 1);
    local.externalWrite('a', _bytes('local edit'));
    remote.externalWrite('a', _bytes('remote edit'));
    result = await reconciler.reconcile(_request(local, remote, state));
    expect(result.conflicts, 1);

    await state.resolve(
      'default',
      'default::a',
      const SyncConflictResolution(SyncConflictChoice.remote),
    );
    result = await reconciler.reconcile(_request(local, remote, state));
    expect(result.conflicts, 0);
    expect(String.fromCharCodes(local.values['a']!), 'remote edit');
  });

  test('enforces the configured maximum object size', () async {
    final local = _Local()..externalWrite('large', _bytes('too large'));
    final policy = <String, Object?>{
      ..._policy,
      'execution': {
        ...(_policy['execution']! as Map<String, Object?>),
        'max_object_size': '1b',
      },
    };

    final report = await const EtagReconciler().reconcile(
      _request(local, _Remote(), _State(), policy: policy),
    );

    expect(report.failure?.kind, SyncFailureKind.configuration);
  });

  test('retains tombstones and applies delete-versus-update policy', () async {
    final local = _Local()..externalWrite('a', _bytes('value'));
    final remote = _Remote();
    final state = _State();
    const reconciler = EtagReconciler();
    await reconciler.reconcile(_request(local, remote, state));
    local.values.remove('a');
    await reconciler.reconcile(_request(local, remote, state));
    expect(remote.values, isEmpty);
    expect(
      ((state.value['records'] as Map)['a'] as Map)['tombstone'],
      isTrue,
    );

    remote.externalWrite('a', _bytes('stale update'));
    final deleteWins = <String, Object?>{
      ..._policy,
      'conflicts': {'strategy': 'preserve', 'delete_vs_update': 'delete_wins'},
    };
    final report = await reconciler.reconcile(
      _request(local, remote, state, policy: deleteWins),
    );
    expect(report.conflicts, 0);
    expect(remote.values, isEmpty);

    await reconciler.reconcile(
      _request(
        local,
        remote,
        state,
        policy: deleteWins,
        now: DateTime.utc(2026, 2, 1),
      ),
    );
    expect((state.value['records'] as Map).containsKey('a'), isFalse);
  });
}

SyncReconcileRequest _request(
  _Local local,
  _Remote remote,
  _State state, {
  Map<String, Object?>? policy,
  DateTime? now,
}) =>
    SyncReconcileRequest(
      profileId: 'default',
      trigger: SyncTrigger.manual,
      local: local,
      remote: remote,
      state: state,
      policy: SyncPolicyCodec.resolve(policy ?? _policy, 'windows'),
      now: now ?? DateTime.utc(2026),
    );

final _policy = <String, Object?>{
  'mode': 'manual',
  'triggers': {
    'startup': false,
    'resume': false,
    'connectivity_restored': false,
    'local_write': {'enabled': false, 'debounce': '2s', 'max_delay': '10s'}
  },
  'discovery': {
    'remote_changes': 'disabled',
    'poll_interval': '60s',
    'safety_reconcile_interval': '15m'
  },
  'execution': {
    'timeout': '2m',
    'busy_behavior': 'reject',
    'max_parallel_transfers': 1,
    'max_object_size': '20mb'
  },
  'retry': {
    'strategy': 'none',
    'initial_delay': '5s',
    'fixed_delay': '30s',
    'sequence': <String>[],
    'multiplier': 2,
    'max_delay': '10m',
    'jitter': '0%',
    'max_attempts': 0
  },
  'conflicts': {'strategy': 'preserve', 'delete_vs_update': 'conflict'},
  'state': {'base_payload': 'always', 'tombstone_retention': '30d'},
  'profiles': {'sync_on_activate': false, 'existing_data': 'attach_to_default'},
};

Uint8List _bytes(String value) => Uint8List.fromList(value.codeUnits);
String _version(Uint8List value) => sha256.convert(value).toString();

final class _Local implements LocalReplica {
  final values = <String, Uint8List>{};
  final controller = StreamController<LocalReplicaChange>.broadcast();
  void externalWrite(String key, Uint8List data) => values[key] = data;
  @override
  Stream<LocalReplicaChange> get changes => controller.stream;
  @override
  Future<void> close() => controller.close();
  @override
  Future<bool> delete(String key,
      {String? expectedVersion,
      SyncMutationOrigin origin = SyncMutationOrigin.remote}) async {
    if (expectedVersion != null &&
        values[key] != null &&
        _version(values[key]!) != expectedVersion) {
      return false;
    }
    values.remove(key);
    return true;
  }

  @override
  Future<LocalObject?> read(String key) async => values[key] == null
      ? null
      : LocalObject(
          key: key, data: values[key]!, version: _version(values[key]!));
  @override
  Future<List<LocalObjectMetadata>> scan() async => [
        for (final entry in values.entries)
          LocalObjectMetadata(key: entry.key, version: _version(entry.value))
      ];
  @override
  Future<bool> write(String key, Uint8List data,
      {String? expectedVersion,
      SyncMutationOrigin origin = SyncMutationOrigin.remote}) async {
    if (expectedVersion != null &&
        values[key] != null &&
        _version(values[key]!) != expectedVersion) {
      return false;
    }
    values[key] = data;
    return true;
  }
}

final class _Remote implements RemoteReplica {
  final values = <String, Uint8List>{};
  final versions = <String, String>{};
  int revision = 0;
  void externalWrite(String key, Uint8List data) {
    values[key] = data;
    versions[key] = 'v${++revision}';
  }

  @override
  RemoteReplicaCapabilities get capabilities => const RemoteReplicaCapabilities(
      deltaScan: false, changeFeed: false, conditionalWrites: true);
  @override
  Stream<void>? get changeHints => null;
  @override
  Future<void> close() async {}
  @override
  Future<void> delete(String key, {RemoteWriteCondition? condition}) async {
    values.remove(key);
    versions.remove(key);
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<RemoteObject?> read(String key) async => values[key] == null
      ? null
      : RemoteObject(key: key, data: values[key]!, version: versions[key]!);
  @override
  Future<RemoteScan> scan({String? cursor}) async =>
      RemoteScan(kind: SyncScanKind.full, objects: [
        for (final key in values.keys)
          RemoteObjectMetadata(key: key, version: versions[key]!)
      ]);
  @override
  Future<String> write(String key, Uint8List data,
      {RemoteWriteCondition? condition}) async {
    externalWrite(key, data);
    return versions[key]!;
  }
}

final class _State implements ReconciliationStateRepository {
  Map<String, Object?> value = {};
  @override
  Future<List<SyncConflict>> conflicts(String profileId) async => const [];
  @override
  Future<Map<String, Object?>> load(String profileId) async => value;
  @override
  Future<void> resolve(String profileId, String conflictId,
      SyncConflictResolution resolution) async {
    final resolutions = value['resolutions'] is Map
        ? (value['resolutions'] as Map).cast<String, Object?>()
        : <String, Object?>{};
    resolutions[conflictId] = {
      'choice': resolution.choice.name,
      if (resolution.merged != null) 'merged': resolution.merged,
    };
    value['resolutions'] = resolutions;
  }

  @override
  Future<void> save(String profileId, Map<String, Object?> state) async =>
      value = state;
}
