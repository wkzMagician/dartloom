import 'dart:async';
import 'dart:typed_data';

import 'package:dartloom_sync/dartloom_sync.dart';
import 'package:test/test.dart';

void main() {
  test('policy codec deep merges platform overrides', () {
    final policy = SyncPolicyCodec.resolve(
        _policy({
          'discovery': {'poll_interval': '30s'},
        }),
        'windows');
    expect(policy.discovery.pollInterval, const Duration(seconds: 30));
    expect(policy.triggers.localWrite.debounce, const Duration(seconds: 2));
  });

  test('manual coordinator runs only when requested', () async {
    final reconciler = _RecordingReconciler();
    final scheduler = _BackgroundScheduler();
    final configured = _policy(const {}, mode: 'manual')
      ..['platforms'] = {
        'android': {
          'background': {
            'enabled': true,
            'enqueue_on_pending': true,
            'periodic_interval': '15m',
            'flex_interval': '5m',
            'network': 'connected',
            'requires_battery_not_low': true,
            'requires_charging': false,
            'timeout': '2m',
          },
        },
      };
    final coordinator = SyncCoordinator(
      instanceName: 'default',
      policy: SyncPolicyCodec.resolve(configured, 'android'),
      profiles: _Profiles(),
      localFactory: _LocalFactory(),
      stateRepository: _State(),
      reconciler: reconciler,
      backends: {'fake': _Backend()},
      backgroundScheduler: scheduler,
    );
    await coordinator.start();
    await Future<void>.delayed(Duration.zero);
    expect(reconciler.runs, 0);
    expect(scheduler.configuredPolicy, isNull);
    expect((await coordinator.syncNow()).isSuccess, isTrue);
    expect(reconciler.runs, 1);
    await coordinator.dispose();
  });
}

final class _BackgroundScheduler implements SyncBackgroundScheduler {
  SyncBackgroundPolicy? configuredPolicy;

  @override
  Future<void> cancel(String instanceName) async {}

  @override
  Future<void> configure(
    String instanceName,
    SyncBackgroundPolicy? policy,
  ) async {
    configuredPolicy = policy;
  }

  @override
  Future<void> enqueue(String instanceName) async {}
}

Map<String, Object?> _policy(Map<String, Object?> windows,
        {String mode = 'automatic'}) =>
    {
      'mode': mode,
      'triggers': {
        'startup': true,
        'resume': true,
        'connectivity_restored': true,
        'local_write': {'enabled': true, 'debounce': '2s', 'max_delay': '10s'},
      },
      'discovery': {
        'remote_changes': 'poll',
        'poll_interval': '60s',
        'safety_reconcile_interval': '15m'
      },
      'execution': {
        'timeout': '2m',
        'busy_behavior': 'coalesce_then_rerun',
        'max_parallel_transfers': 4,
        'max_object_size': '20mb'
      },
      'retry': {
        'strategy': 'none',
        'initial_delay': '5s',
        'fixed_delay': '30s',
        'sequence': <String>[],
        'multiplier': 3,
        'max_delay': '10m',
        'jitter': '0%',
        'max_attempts': 0
      },
      'conflicts': {'strategy': 'preserve', 'delete_vs_update': 'conflict'},
      'state': {'base_payload': 'always', 'tombstone_retention': '30d'},
      'profiles': {
        'sync_on_activate': true,
        'existing_data': 'attach_to_default'
      },
      'platforms': {'windows': windows},
    };

final class _RecordingReconciler implements SyncReconciler {
  int runs = 0;
  @override
  Future<SyncRunReport> reconcile(SyncReconcileRequest request) async {
    runs++;
    return SyncRunReport(trigger: request.trigger);
  }
}

final class _Profiles implements SyncProfileRepository {
  final profile = const SyncProfile(
      id: 'default', label: 'Default', backend: 'fake', isActive: true);
  @override
  Future<SyncProfile?> active() async => profile;
  @override
  Future<void> activate(String profileId) async {}
  @override
  Future<void> delete(String profileId,
      {required bool deleteLocalData}) async {}
  @override
  Future<List<SyncProfile>> list() async => [profile];
  @override
  Future<Map<String, String>> secrets(String profileId) async => const {};
  @override
  Future<SyncProfile> save(SyncProfileDraft draft) async => profile;
}

final class _LocalFactory implements LocalReplicaFactory {
  @override
  Future<void> deleteProfile(String profileId) async {}
  @override
  Future<LocalReplica> open(String profileId) async => _Local();
}

final class _Local implements LocalReplica {
  final _changes = StreamController<LocalReplicaChange>.broadcast();
  @override
  Stream<LocalReplicaChange> get changes => _changes.stream;
  @override
  String get identity => 'test-local';
  @override
  bool acceptsKey(String key) => true;
  @override
  Future<List<StoreIntent>> intents() async => const [];
  @override
  Future<void> forgetIntent(String operationId) async {}
  @override
  Future<void> close() => _changes.close();
  @override
  Future<bool> delete(String key,
          {String? expectedVersion,
          SyncMutationOrigin origin = SyncMutationOrigin.remote}) async =>
      true;
  @override
  Future<LocalObject?> read(String key) async => null;
  @override
  Future<List<LocalObjectMetadata>> scan() async => const [];
  @override
  Future<bool> write(String key, Uint8List data,
          {String? expectedVersion,
          SyncMutationOrigin origin = SyncMutationOrigin.remote}) async =>
      true;
}

final class _Backend implements SyncBackendFactory {
  @override
  RemoteReplicaCapabilities get capabilities => const RemoteReplicaCapabilities(
      deltaScan: false, changeFeed: false, conditionalWrites: true);
  @override
  String get id => 'fake';
  @override
  Future<RemoteReplica> open(
          SyncProfile profile, Map<String, String> secrets) async =>
      _Remote();
  @override
  Future<void> validateProfile(SyncProfileDraft profile) async {}
}

final class _Remote implements RemoteReplica {
  @override
  String get identity => 'test-remote';
  @override
  RemoteReplicaCapabilities get capabilities => const RemoteReplicaCapabilities(
      deltaScan: false, changeFeed: false, conditionalWrites: true);
  @override
  Stream<void>? get changeHints => null;
  @override
  Future<void> close() async {}
  @override
  Future<void> delete(String key, {RemoteWriteCondition? condition}) async {}
  @override
  Future<void> initialize() async {}
  @override
  Future<RemoteObject?> read(String key) async => null;
  @override
  Future<RemoteScan> scan({String? cursor}) async =>
      const RemoteScan(kind: SyncScanKind.full, objects: [], complete: true);
  @override
  Future<String> write(String key, Uint8List data,
          {RemoteWriteCondition? condition}) async =>
      'v1';
}

final class _State implements ReconciliationStateRepository {
  @override
  Future<List<SyncConflict>> conflicts(String profileId) async => const [];
  @override
  Future<SyncState> load(String profileId) async => const SyncState();
  @override
  Future<void> resolve(String profileId, String conflictId,
      SyncConflictResolution resolution) async {}
  @override
  Future<void> save(String profileId, SyncState state) async {}
}
