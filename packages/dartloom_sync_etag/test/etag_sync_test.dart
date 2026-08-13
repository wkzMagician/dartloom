import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:dartloom_sync/dartloom_sync.dart';
import 'package:dartloom_sync_etag/dartloom_sync_etag.dart';
import 'package:test/test.dart';

void main() {
  test('uploads, downloads, deletes, and preserves conflicts', () async {
    final local = _Local();
    final remote = _Remote();
    final state = _State();
    const reconciler = EtagReconciler();
    local.authorizedWrite('a', _bytes('local'));
    var result = await reconciler.reconcile(_request(local, remote, state));
    expect(result.uploaded, 1);
    remote.externalWrite('a', _bytes('remote'));
    result = await reconciler.reconcile(_request(local, remote, state));
    expect(result.downloaded, 1);
    local.authorizedWrite('a', _bytes('local edit'));
    remote.externalWrite('a', _bytes('remote edit'));
    result = await reconciler.reconcile(_request(local, remote, state));
    expect(result.conflicts, 1);

    await state.resolve(
      'default',
      'default::a',
      const SyncConflictResolution(SyncConflictChoice.useRemote),
    );
    result = await reconciler.reconcile(_request(local, remote, state));
    expect(result.conflicts, 0);
    expect(String.fromCharCodes(local.values['a']!), 'remote edit');
  });

  test('enforces the configured maximum object size', () async {
    final local = _Local()..authorizedWrite('large', _bytes('too large'));
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

  test('restores a missing local object without an explicit deletion',
      () async {
    final local = _Local()..authorizedWrite('a', _bytes('value'));
    final remote = _Remote();
    final state = _State();
    const reconciler = EtagReconciler();
    await reconciler.reconcile(_request(local, remote, state));

    local.values.remove('a');
    final report = await reconciler.reconcile(_request(local, remote, state));

    expect(report.downloaded, 1);
    expect(String.fromCharCodes(local.values['a']!), 'value');
    expect(remote.values, contains('a'));
  });

  test('retains tombstones and applies delete-versus-update policy', () async {
    final local = _Local()..authorizedWrite('a', _bytes('value'));
    final remote = _Remote();
    final state = _State();
    const reconciler = EtagReconciler();
    await reconciler.reconcile(_request(local, remote, state));
    remote.externalWrite('a', _bytes('stale update'));
    local.authorizedDelete('a');
    final deleteWins = <String, Object?>{
      ..._policy,
      'conflicts': {'strategy': 'preserve', 'delete_vs_update': 'delete_wins'},
    };
    final report = await reconciler.reconcile(
      _request(local, remote, state, policy: deleteWins),
    );
    expect(report.conflicts, 0);
    expect(remote.values, isEmpty);
    expect(state.value.records['a']?.isTombstone, isTrue);

    await reconciler.reconcile(
      _request(
        local,
        remote,
        state,
        policy: deleteWins,
        now: DateTime.utc(2026, 2, 1),
      ),
    );
    expect(state.value.records.containsKey('a'), isFalse);
  });

  test('unregistered external files are neither uploaded nor deleted',
      () async {
    final local = _Local()..externalWrite('outside.bin', _bytes('external'));
    final remote = _Remote();
    final report = await const EtagReconciler().reconcile(
      _request(local, remote, _State()),
    );
    expect(report.uploaded, 0);
    expect(report.deletedLocally, 0);
    expect(local.values, contains('outside.bin'));
    expect(remote.values, isEmpty);
  });

  test('external edits and deletions restore the remote baseline', () async {
    final local = _Local()..authorizedWrite('a', _bytes('baseline'));
    final remote = _Remote();
    final state = _State();
    const reconciler = EtagReconciler();
    await reconciler.reconcile(_request(local, remote, state));

    local.externalWrite('a', _bytes('outside edit'));
    var report = await reconciler.reconcile(_request(local, remote, state));
    expect(report.uploaded, 0);
    expect(String.fromCharCodes(local.values['a']!), 'baseline');
    local.externalDelete('a');
    report = await reconciler.reconcile(_request(local, remote, state));
    expect(report.deletedRemotely, 0);
    expect(String.fromCharCodes(local.values['a']!), 'baseline');
  });

  test('incomplete remote scans never delete local or remote data', () async {
    final local = _Local()..authorizedWrite('a', _bytes('value'));
    final remote = _Remote();
    final state = _State();
    const reconciler = EtagReconciler();
    await reconciler.reconcile(_request(local, remote, state));
    remote.complete = false;
    remote.hideFromScan = true;
    final report = await reconciler.reconcile(_request(local, remote, state));
    expect(report.deletedLocally, 0);
    expect(report.deletedRemotely, 0);
    expect(local.values, contains('a'));
    expect(remote.values, contains('a'));
  });

  test('merge receives raw base local and remote bytes with normalized id',
      () async {
    final local = _Local()..authorizedWrite('folder/a', _bytes('base'));
    final remote = _Remote();
    final state = _State();
    const reconciler = EtagReconciler();
    await reconciler.reconcile(_request(local, remote, state));
    local.authorizedWrite('folder/a', _bytes('local'));
    remote.externalWrite('folder/a', _bytes('remote'));
    SyncConflict? seen;
    final mergePolicy = <String, Object?>{
      ..._policy,
      'conflicts': {'strategy': 'merge', 'delete_vs_update': 'conflict'},
    };
    final report = await reconciler.reconcile(
      _request(
        local,
        remote,
        state,
        policy: mergePolicy,
        merge: (conflict) async {
          seen = conflict;
          return _bytes('merged');
        },
      ),
    );
    expect(report.conflicts, 0);
    expect(seen?.id, 'default::folder/a');
    expect(String.fromCharCodes(seen!.base!), 'base');
    expect(String.fromCharCodes(seen!.local!), 'local');
    expect(String.fromCharCodes(seen!.remote!), 'remote');
  });
}

SyncReconcileRequest _request(
  _Local local,
  _Remote remote,
  _State state, {
  Map<String, Object?>? policy,
  DateTime? now,
  SyncMergePolicy? merge,
}) =>
    SyncReconcileRequest(
      profileId: 'default',
      trigger: SyncTrigger.manual,
      local: local,
      remote: remote,
      state: state,
      policy: SyncPolicyCodec.resolve(policy ?? _policy, 'windows'),
      now: now ?? DateTime.utc(2026),
      merge: merge,
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
  final pendingIntents = <StoreIntent>[];
  final controller = StreamController<LocalReplicaChange>.broadcast();
  void externalWrite(String key, Uint8List data) {
    values[key] = data;
  }

  void authorizedWrite(String key, Uint8List data) {
    final kind = values.containsKey(key)
        ? StoreIntentKind.update
        : StoreIntentKind.create;
    values[key] = data;
    pendingIntents.add(_intent(key, kind));
  }

  void externalDelete(String key) {
    values.remove(key);
  }

  void authorizedDelete(String key) {
    values.remove(key);
    pendingIntents.add(_intent(key, StoreIntentKind.delete));
  }

  @override
  String get identity => 'test-local';
  @override
  bool acceptsKey(String key) => true;
  @override
  Future<List<StoreIntent>> intents() async => List.of(pendingIntents);
  @override
  Future<void> forgetIntent(String operationId) async =>
      pendingIntents.removeWhere((intent) => intent.operationId == operationId);
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

  StoreIntent _intent(String key, StoreIntentKind kind) => StoreIntent(
        operationId: '${pendingIntents.length}::$key',
        key: key,
        kind: kind,
        origin: StoreMutationOrigin.application,
        createdAt: DateTime.utc(2026),
      );
}

final class _Remote implements RemoteReplica {
  final values = <String, Uint8List>{};
  final versions = <String, String>{};
  int revision = 0;
  bool complete = true;
  bool hideFromScan = false;
  @override
  String get identity => 'test-remote';
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
  Future<RemoteScan> scan({String? cursor}) async => RemoteScan(
      kind: SyncScanKind.full,
      objects: [
        for (final key in hideFromScan ? const <String>[] : values.keys)
          RemoteObjectMetadata(key: key, version: versions[key]!)
      ],
      complete: complete);
  @override
  Future<String> write(String key, Uint8List data,
      {RemoteWriteCondition? condition}) async {
    externalWrite(key, data);
    return versions[key]!;
  }
}

final class _State implements ReconciliationStateRepository {
  SyncState value = const SyncState();
  @override
  Future<List<SyncConflict>> conflicts(String profileId) async => const [];
  @override
  Future<SyncState> load(String profileId) async => value;
  @override
  Future<void> resolve(String profileId, String conflictId,
      SyncConflictResolution resolution) async {
    final resolutions = Map<String, StoredResolution>.of(value.resolutions)
      ..[conflictId] = StoredResolution(resolution);
    value = value.copyWith(resolutions: resolutions);
  }

  @override
  Future<void> save(String profileId, SyncState state) async => value = state;
}
