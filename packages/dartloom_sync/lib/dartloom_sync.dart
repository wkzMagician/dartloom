import 'dart:async';

export 'sync_scheduler.dart';
import 'dart:math';
import 'dart:typed_data';

enum SyncMode { manual, automatic }

enum SyncPhase {
  idle,
  scheduled,
  syncing,
  succeeded,
  conflicted,
  offline,
  failed
}

enum SyncTrigger {
  manual,
  localWrite,
  startup,
  resume,
  connectivityRestored,
  remoteChange,
  poll,
  background,
  retry
}

enum SyncBusyBehavior { coalesce, coalesceThenRerun, reject }

enum SyncRemoteDiscovery { auto, push, poll, disabled }

enum SyncRetryStrategy { none, fixed, exponential, sequence }

enum SyncConflictStrategy { preserve, localWins, remoteWins, merge }

enum SyncDeleteConflictStrategy { conflict, deleteWins, updateWins }

enum SyncBasePayloadPolicy { always, conflictsOnly, never }

enum SyncMutationOrigin { local, remote }

@Deprecated('Use SyncMutationOrigin.')
enum StoreMutationOrigin {
  application,
  migration,
  conflictResolution,
  remote,
  recovery,
  external
}

enum LocalMutationKind { create, update, delete }

enum LocalObservation {
  trusted,
  untrustedLocalChange,
  unexpectedMissing,
  unregisteredLocalObject
}

final class PendingLocalMutation {
  const PendingLocalMutation(
      {required this.operationId,
      required this.key,
      required this.kind,
      required this.createdAt,
      this.contentHash,
      this.origin = StoreMutationOrigin.application});
  final String operationId;
  final String key;
  final LocalMutationKind kind;
  final DateTime createdAt;
  final String? contentHash;
  final StoreMutationOrigin origin;
}

@Deprecated('Use PendingLocalMutation.')
typedef StoreIntent = PendingLocalMutation;
@Deprecated('Use LocalMutationKind.')
typedef StoreIntentKind = LocalMutationKind;

enum SyncScanKind { full, delta }

enum SyncFailureKind {
  authentication,
  permission,
  notFound,
  precondition,
  invalidResponse,
  serverLimit,
  configuration,
  connectivity,
  timeout,
  conflict,
  cancelled,
  unknown
}

final class SyncFailure {
  const SyncFailure(this.kind, this.message, {this.retryable = false});
  final SyncFailureKind kind;
  final String message;
  final bool retryable;
}

final class SyncOperationException implements Exception {
  const SyncOperationException(this.failure);
  final SyncFailure failure;
  @override
  String toString() => failure.message;
}

final class SyncRunReport {
  const SyncRunReport({
    required this.trigger,
    this.uploaded = 0,
    this.downloaded = 0,
    this.deletedLocally = 0,
    this.deletedRemotely = 0,
    this.conflicts = 0,
    this.failure,
  });

  final SyncTrigger trigger;
  final int uploaded;
  final int downloaded;
  final int deletedLocally;
  final int deletedRemotely;
  final int conflicts;
  final SyncFailure? failure;
  bool get isSuccess => failure == null && conflicts == 0;
}

final class SyncSnapshot {
  const SyncSnapshot({
    required this.phase,
    required this.localRevision,
    this.activeProfileId,
    this.trigger,
    this.lastReport,
    this.lastAttemptAt,
    this.lastSuccessAt,
    this.nextRetryAt,
    this.pending = false,
  });

  const SyncSnapshot.initial()
      : phase = SyncPhase.idle,
        localRevision = 0,
        activeProfileId = null,
        trigger = null,
        lastReport = null,
        lastAttemptAt = null,
        lastSuccessAt = null,
        nextRetryAt = null,
        pending = false;

  final SyncPhase phase;
  final int localRevision;
  final String? activeProfileId;
  final SyncTrigger? trigger;
  final SyncRunReport? lastReport;
  final DateTime? lastAttemptAt;
  final DateTime? lastSuccessAt;
  final DateTime? nextRetryAt;
  final bool pending;

  SyncSnapshot copyWith({
    SyncPhase? phase,
    int? localRevision,
    String? activeProfileId,
    SyncTrigger? trigger,
    SyncRunReport? lastReport,
    DateTime? lastAttemptAt,
    DateTime? lastSuccessAt,
    DateTime? nextRetryAt,
    bool clearNextRetry = false,
    bool? pending,
  }) =>
      SyncSnapshot(
        phase: phase ?? this.phase,
        localRevision: localRevision ?? this.localRevision,
        activeProfileId: activeProfileId ?? this.activeProfileId,
        trigger: trigger ?? this.trigger,
        lastReport: lastReport ?? this.lastReport,
        lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
        lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
        nextRetryAt: clearNextRetry ? null : nextRetryAt ?? this.nextRetryAt,
        pending: pending ?? this.pending,
      );
}

final class SyncProfile {
  const SyncProfile({
    required this.id,
    required this.label,
    required this.backend,
    this.options = const {},
    this.isActive = false,
  });
  final String id;
  final String label;
  final String backend;
  final Map<String, Object?> options;
  final bool isActive;
}

final class SyncProfileDraft {
  const SyncProfileDraft({
    this.id,
    required this.label,
    required this.backend,
    this.options = const {},
    this.secrets = const {},
  });
  final String? id;
  final String label;
  final String backend;
  final Map<String, Object?> options;
  final Map<String, String> secrets;
}

abstract interface class SyncProfileRepository {
  Future<List<SyncProfile>> list();
  Future<SyncProfile?> active();
  Future<Map<String, String>> secrets(String profileId);
  Future<SyncProfile> save(SyncProfileDraft draft);
  Future<void> activate(String profileId);
  Future<void> delete(String profileId, {required bool deleteLocalData});
}

final class LocalObjectMetadata {
  const LocalObjectMetadata({
    required this.key,
    required this.version,
    this.exists = true,
    this.observation = LocalObservation.trusted,
  });
  final String key;
  final String version;
  final bool exists;
  final LocalObservation observation;
}

final class LocalObject {
  const LocalObject(
      {required this.key, required this.data, required this.version});
  final String key;
  final Uint8List data;
  final String version;
}

final class LocalReplicaChange {
  const LocalReplicaChange(this.key, this.origin);
  final String key;
  final SyncMutationOrigin origin;
}

abstract interface class LocalReplica {
  String get identity;
  bool acceptsKey(String key);
  Stream<LocalReplicaChange> get changes;
  Future<List<LocalObjectMetadata>> scan();
  Future<List<PendingLocalMutation>> intents();
  Future<void> forgetIntent(String operationId);
  Future<LocalObject?> read(String key);
  Future<bool> write(
    String key,
    Uint8List data, {
    String? expectedVersion,
    SyncMutationOrigin origin = SyncMutationOrigin.remote,
  });
  Future<bool> delete(
    String key, {
    String? expectedVersion,
    SyncMutationOrigin origin = SyncMutationOrigin.remote,
  });
  Future<void> close();
}

abstract interface class LocalReplicaFactory {
  Future<LocalReplica> open(String profileId);
  Future<void> deleteProfile(String profileId);
}

final class RemoteObjectMetadata {
  const RemoteObjectMetadata({required this.key, required this.version});
  final String key;
  final String version;
}

final class RemoteObject {
  const RemoteObject(
      {required this.key, required this.data, required this.version});
  final String key;
  final Uint8List data;
  final String version;
}

final class RemoteScan {
  const RemoteScan({
    required this.kind,
    required this.objects,
    required this.complete,
    this.deletedKeys = const [],
    this.cursor,
  });
  final SyncScanKind kind;
  final List<RemoteObjectMetadata> objects;

  /// Whether absence from this scan is authoritative.
  final bool complete;
  final List<String> deletedKeys;
  final String? cursor;
}

final class RemoteReplicaCapabilities {
  const RemoteReplicaCapabilities({
    required this.deltaScan,
    required this.changeFeed,
    required this.conditionalWrites,
  });
  final bool deltaScan;
  final bool changeFeed;
  final bool conditionalWrites;
}

sealed class RemoteWriteCondition {
  const RemoteWriteCondition();
  const factory RemoteWriteCondition.create() = RemoteCreateCondition;
  const factory RemoteWriteCondition.version(String version) =
      RemoteVersionCondition;
}

final class RemoteCreateCondition extends RemoteWriteCondition {
  const RemoteCreateCondition();
}

final class RemoteVersionCondition extends RemoteWriteCondition {
  const RemoteVersionCondition(this.version);
  final String version;
}

final class RemotePreconditionException implements Exception {
  const RemotePreconditionException(this.key);
  final String key;
  @override
  String toString() => 'Remote object precondition failed for $key.';
}

abstract interface class RemoteReplica {
  String get identity;
  RemoteReplicaCapabilities get capabilities;
  Stream<void>? get changeHints;
  Future<void> initialize();
  Future<RemoteScan> scan({String? cursor});
  Future<RemoteObject?> read(String key);
  Future<String> write(String key, Uint8List data,
      {RemoteWriteCondition? condition});
  Future<void> delete(String key, {RemoteWriteCondition? condition});
  Future<void> close();
}

abstract interface class SyncBackendFactory {
  String get id;
  RemoteReplicaCapabilities get capabilities;
  Future<void> validateProfile(SyncProfileDraft profile);
  Future<RemoteReplica> open(SyncProfile profile, Map<String, String> secrets);
}

final class SyncConflict {
  const SyncConflict({
    required this.id,
    required this.key,
    this.local,
    this.remote,
    this.base,
  });
  final String id;
  final String key;
  final Uint8List? local;
  final Uint8List? remote;
  final Uint8List? base;
}

enum SyncConflictChoice {
  useLocal,
  useRemote,
  deleteBoth,
  useMerged,
  postpone,
}

final class SyncConflictResolution {
  const SyncConflictResolution(this.choice, {this.merged});
  final SyncConflictChoice choice;
  final Uint8List? merged;
}

abstract interface class ReconciliationStateRepository {
  Future<SyncState> load(String profileId);
  Future<void> save(String profileId, SyncState state);
  Future<List<SyncConflict>> conflicts(String profileId);
  Future<void> resolve(
      String profileId, String conflictId, SyncConflictResolution resolution);
}

final class SyncRecord {
  const SyncRecord({
    this.remoteVersion,
    this.baseHash,
    this.base,
    this.deletedAt,
  });

  final String? remoteVersion;
  final String? baseHash;
  final Uint8List? base;
  final DateTime? deletedAt;
  bool get isTombstone => deletedAt != null;
}

final class StoredConflict {
  const StoredConflict(this.value);
  final SyncConflict value;
}

final class StoredResolution {
  const StoredResolution(this.value);
  final SyncConflictResolution value;
}

final class SyncState {
  const SyncState({
    this.version = 1,
    this.fingerprint,
    this.cursor,
    this.records = const {},
    this.remoteVersions = const {},
    this.conflicts = const {},
    this.resolutions = const {},
  });

  final int version;
  final String? fingerprint;
  final String? cursor;
  final Map<String, SyncRecord> records;
  final Map<String, String> remoteVersions;
  final Map<String, StoredConflict> conflicts;
  final Map<String, StoredResolution> resolutions;

  SyncState copyWith({
    String? fingerprint,
    String? cursor,
    Map<String, SyncRecord>? records,
    Map<String, String>? remoteVersions,
    Map<String, StoredConflict>? conflicts,
    Map<String, StoredResolution>? resolutions,
  }) =>
      SyncState(
        version: version,
        fingerprint: fingerprint ?? this.fingerprint,
        cursor: cursor ?? this.cursor,
        records: records ?? this.records,
        remoteVersions: remoteVersions ?? this.remoteVersions,
        conflicts: conflicts ?? this.conflicts,
        resolutions: resolutions ?? this.resolutions,
      );
}

typedef SyncMergePolicy = Future<Uint8List?> Function(SyncConflict conflict);

final class SyncReconcileRequest {
  const SyncReconcileRequest({
    required this.profileId,
    required this.trigger,
    required this.local,
    required this.remote,
    required this.state,
    required this.policy,
    required this.now,
    this.merge,
  });
  final String profileId;
  final SyncTrigger trigger;
  final LocalReplica local;
  final RemoteReplica remote;
  final ReconciliationStateRepository state;
  final ResolvedSyncPolicy policy;
  final DateTime now;
  final SyncMergePolicy? merge;
}

abstract interface class SyncReconciler {
  Future<SyncRunReport> reconcile(SyncReconcileRequest request);
}

final class SyncLocalWritePolicy {
  const SyncLocalWritePolicy(
      {required this.enabled, required this.debounce, required this.maxDelay});
  final bool enabled;
  final Duration debounce;
  final Duration maxDelay;
}

final class SyncTriggerPolicy {
  const SyncTriggerPolicy({
    required this.startup,
    required this.resume,
    required this.connectivityRestored,
    required this.localWrite,
  });
  final bool startup;
  final bool resume;
  final bool connectivityRestored;
  final SyncLocalWritePolicy localWrite;
}

final class SyncDiscoveryPolicy {
  const SyncDiscoveryPolicy({
    required this.remoteChanges,
    required this.pollInterval,
    required this.safetyReconcileInterval,
  });
  final SyncRemoteDiscovery remoteChanges;
  final Duration pollInterval;
  final Duration safetyReconcileInterval;
}

final class SyncExecutionPolicy {
  const SyncExecutionPolicy(
      {required this.timeout,
      required this.busyBehavior,
      required this.maxParallelTransfers,
      required this.maxObjectSize});
  final Duration timeout;
  final SyncBusyBehavior busyBehavior;
  final int maxParallelTransfers;
  final int maxObjectSize;
}

final class SyncRetryPolicy {
  const SyncRetryPolicy({
    required this.strategy,
    required this.initialDelay,
    required this.fixedDelay,
    required this.sequence,
    required this.multiplier,
    required this.maxDelay,
    required this.jitter,
    required this.maxAttempts,
  });
  final SyncRetryStrategy strategy;
  final Duration initialDelay;
  final Duration fixedDelay;
  final List<Duration> sequence;
  final double multiplier;
  final Duration maxDelay;
  final double jitter;
  final int maxAttempts;

  Duration? delayFor(int attempt, Random random) {
    if (strategy == SyncRetryStrategy.none ||
        (maxAttempts > 0 && attempt > maxAttempts)) {
      return null;
    }
    final base = switch (strategy) {
      SyncRetryStrategy.none => Duration.zero,
      SyncRetryStrategy.fixed => fixedDelay,
      SyncRetryStrategy.exponential => Duration(
          microseconds: min(
            maxDelay.inMicroseconds,
            (initialDelay.inMicroseconds * pow(multiplier, attempt - 1))
                .round(),
          ),
        ),
      SyncRetryStrategy.sequence => sequence.isEmpty
          ? initialDelay
          : sequence[min(attempt - 1, sequence.length - 1)],
    };
    if (jitter == 0) return base;
    final factor = 1 - jitter + random.nextDouble() * jitter * 2;
    return Duration(microseconds: (base.inMicroseconds * factor).round());
  }
}

final class SyncConflictPolicy {
  const SyncConflictPolicy(
      {required this.strategy, required this.deleteVsUpdate});
  final SyncConflictStrategy strategy;
  final SyncDeleteConflictStrategy deleteVsUpdate;
}

final class SyncStatePolicy {
  const SyncStatePolicy(
      {required this.basePayload, required this.tombstoneRetention});
  final SyncBasePayloadPolicy basePayload;
  final Duration tombstoneRetention;
}

final class SyncProfilePolicy {
  const SyncProfilePolicy(
      {required this.syncOnActivate, required this.attachExistingData});
  final bool syncOnActivate;
  final bool attachExistingData;
}

final class SyncBackgroundPolicy {
  const SyncBackgroundPolicy({
    required this.enabled,
    required this.enqueueOnPending,
    required this.periodicInterval,
    required this.flexInterval,
    required this.network,
    required this.requiresBatteryNotLow,
    required this.requiresCharging,
    required this.requiresNetwork,
    required this.timeout,
    this.task = 'app_refresh',
    this.earliestBegin = Duration.zero,
  });
  final bool enabled;
  final bool enqueueOnPending;
  final Duration periodicInterval;
  final Duration flexInterval;
  final String network;
  final bool requiresBatteryNotLow;
  final bool requiresCharging;
  final bool requiresNetwork;
  final Duration timeout;
  final String task;
  final Duration earliestBegin;
}

final class ResolvedSyncPolicy {
  const ResolvedSyncPolicy({
    required this.mode,
    required this.triggers,
    required this.discovery,
    required this.execution,
    required this.retry,
    required this.conflicts,
    required this.state,
    required this.profiles,
    this.background,
  });
  final SyncMode mode;
  final SyncTriggerPolicy triggers;
  final SyncDiscoveryPolicy discovery;
  final SyncExecutionPolicy execution;
  final SyncRetryPolicy retry;
  final SyncConflictPolicy conflicts;
  final SyncStatePolicy state;
  final SyncProfilePolicy profiles;
  final SyncBackgroundPolicy? background;
}

abstract final class SyncPolicyCodec {
  static ResolvedSyncPolicy resolve(
      Map<String, Object?> configured, String platform) {
    final base = Map<String, Object?>.fromEntries(
        configured.entries.where((entry) => entry.key != 'platforms'));
    final platforms = configured['platforms'];
    final override = platforms is Map && platforms[platform] is Map
        ? (platforms[platform] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final merged = _merge(
        base,
        Map.fromEntries(
            override.entries.where((entry) => entry.key != 'background')));
    final triggers = _map(merged, 'triggers');
    final localWrite = _map(triggers, 'local_write');
    final discovery = _map(merged, 'discovery');
    final execution = _map(merged, 'execution');
    final retry = _map(merged, 'retry');
    final conflicts = _map(merged, 'conflicts');
    final state = _map(merged, 'state');
    final profiles = _map(merged, 'profiles');
    final backgroundMap = override['background'] is Map
        ? (override['background'] as Map).cast<String, Object?>()
        : null;
    return ResolvedSyncPolicy(
      mode: SyncMode.values.byName(_string(merged, 'mode')),
      triggers: SyncTriggerPolicy(
        startup: _bool(triggers, 'startup'),
        resume: _bool(triggers, 'resume'),
        connectivityRestored: _bool(triggers, 'connectivity_restored'),
        localWrite: SyncLocalWritePolicy(
          enabled: _bool(localWrite, 'enabled'),
          debounce: parseDuration(_string(localWrite, 'debounce')),
          maxDelay: parseDuration(_string(localWrite, 'max_delay')),
        ),
      ),
      discovery: SyncDiscoveryPolicy(
        remoteChanges: SyncRemoteDiscovery.values
            .byName(_string(discovery, 'remote_changes')),
        pollInterval: parseDuration(_string(discovery, 'poll_interval')),
        safetyReconcileInterval:
            parseDuration(_string(discovery, 'safety_reconcile_interval')),
      ),
      execution: SyncExecutionPolicy(
        timeout: parseDuration(_string(execution, 'timeout')),
        busyBehavior: SyncBusyBehavior.values
            .byName(_camelEnum(_string(execution, 'busy_behavior'))),
        maxParallelTransfers: _int(execution, 'max_parallel_transfers'),
        maxObjectSize: parseBytes(_string(execution, 'max_object_size')),
      ),
      retry: SyncRetryPolicy(
        strategy: SyncRetryStrategy.values.byName(_string(retry, 'strategy')),
        initialDelay: parseDuration(_string(retry, 'initial_delay')),
        fixedDelay: parseDuration(_string(retry, 'fixed_delay')),
        sequence: (retry['sequence'] as List)
            .cast<String>()
            .map(parseDuration)
            .toList(growable: false),
        multiplier: (retry['multiplier'] as num).toDouble(),
        maxDelay: parseDuration(_string(retry, 'max_delay')),
        jitter: parsePercentage(_string(retry, 'jitter')),
        maxAttempts: _int(retry, 'max_attempts'),
      ),
      conflicts: SyncConflictPolicy(
        strategy: SyncConflictStrategy.values
            .byName(_camelEnum(_string(conflicts, 'strategy'))),
        deleteVsUpdate: SyncDeleteConflictStrategy.values
            .byName(_camelEnum(_string(conflicts, 'delete_vs_update'))),
      ),
      state: SyncStatePolicy(
        basePayload: SyncBasePayloadPolicy.values
            .byName(_camelEnum(_string(state, 'base_payload'))),
        tombstoneRetention:
            parseDuration(_string(state, 'tombstone_retention')),
      ),
      profiles: SyncProfilePolicy(
        syncOnActivate: _bool(profiles, 'sync_on_activate'),
        attachExistingData:
            _string(profiles, 'existing_data') == 'attach_to_default',
      ),
      background: backgroundMap == null
          ? null
          : SyncBackgroundPolicy(
              enabled: _bool(backgroundMap, 'enabled'),
              enqueueOnPending:
                  backgroundMap['enqueue_on_pending'] as bool? ?? false,
              periodicInterval: parseDuration(
                  backgroundMap['periodic_interval'] as String? ?? '15m'),
              flexInterval: parseDuration(
                  backgroundMap['flex_interval'] as String? ?? '5m'),
              network: backgroundMap['network'] as String? ?? 'connected',
              requiresBatteryNotLow:
                  backgroundMap['requires_battery_not_low'] as bool? ?? false,
              requiresCharging:
                  backgroundMap['requires_charging'] as bool? ?? false,
              requiresNetwork:
                  backgroundMap['requires_network'] as bool? ?? true,
              timeout: parseDuration(_string(backgroundMap, 'timeout')),
              task: backgroundMap['task'] as String? ?? 'app_refresh',
              earliestBegin: parseDuration(
                  backgroundMap['earliest_begin'] as String? ?? '15m'),
            ),
    );
  }

  static Duration parseDuration(String input) {
    final match = RegExp(r'^(\d+(?:\.\d+)?)(ms|s|m|h|d)$')
        .firstMatch(input.toLowerCase());
    if (match == null) throw FormatException('Invalid duration: $input');
    final value = double.parse(match.group(1)!);
    final micros = switch (match.group(2)) {
      'ms' => value * Duration.microsecondsPerMillisecond,
      's' => value * Duration.microsecondsPerSecond,
      'm' => value * Duration.microsecondsPerMinute,
      'h' => value * Duration.microsecondsPerHour,
      'd' => value * Duration.microsecondsPerDay,
      _ => 0,
    };
    return Duration(microseconds: micros.round());
  }

  static int parseBytes(String input) {
    final match = RegExp(r'^(\d+(?:\.\d+)?)(b|kb|mb|gb)$')
        .firstMatch(input.toLowerCase());
    if (match == null) throw FormatException('Invalid byte size: $input');
    final multiplier = switch (match.group(2)) {
      'b' => 1,
      'kb' => 1024,
      'mb' => 1024 * 1024,
      'gb' => 1024 * 1024 * 1024,
      _ => 1
    };
    return (double.parse(match.group(1)!) * multiplier).round();
  }

  static double parsePercentage(String input) {
    if (!input.endsWith('%')) {
      throw FormatException('Invalid percentage: $input');
    }
    return double.parse(input.substring(0, input.length - 1)) / 100;
  }

  static Map<String, Object?> _map(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! Map) throw FormatException('$key must be a map.');
    return value.cast<String, Object?>();
  }

  static String _string(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String) throw FormatException('$key must be a string.');
    return value;
  }

  static bool _bool(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! bool) throw FormatException('$key must be a bool.');
    return value;
  }

  static int _int(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! int) throw FormatException('$key must be an int.');
    return value;
  }

  static String _camelEnum(String value) {
    final parts = value.split('_');
    return parts.first +
        parts
            .skip(1)
            .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
            .join();
  }

  static Map<String, Object?> _merge(
      Map<String, Object?> base, Map<String, Object?> override) {
    final result = <String, Object?>{...base};
    for (final entry in override.entries) {
      if (result[entry.key] is Map && entry.value is Map) {
        result[entry.key] = _merge(
          (result[entry.key] as Map).cast<String, Object?>(),
          (entry.value as Map).cast<String, Object?>(),
        );
      } else {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }
}

abstract interface class SyncRuntimeSignals {
  Stream<void> get resumed;
  Stream<void> get connectivityRestored;
}

abstract interface class SyncBackgroundScheduler {
  Future<void> configure(String instanceName, SyncBackgroundPolicy? policy);
  Future<void> enqueue(String instanceName);
  Future<void> cancel(String instanceName);
}

abstract interface class SyncService {
  SyncSnapshot get snapshot;
  Stream<SyncSnapshot> get states;
  Future<void> start();
  Future<SyncRunReport> syncNow();
  Future<List<SyncProfile>> listProfiles();
  Future<SyncProfile> saveProfile(SyncProfileDraft draft);
  Future<void> activateProfile(String profileId);
  Future<void> deleteProfile(String profileId, {required bool deleteLocalData});
  Future<List<SyncConflict>> listConflicts();
  Future<void> resolveConflict(
      String conflictId, SyncConflictResolution resolution);
  Future<void> dispose();
}

final class SyncCoordinator implements SyncService {
  SyncCoordinator({
    required this.instanceName,
    required this.policy,
    required this.profiles,
    required this.localFactory,
    required this.stateRepository,
    required this.reconciler,
    required this.backends,
    this.runtimeSignals,
    this.backgroundScheduler,
    this.merge,
    DateTime Function()? now,
    Random? random,
  })  : _now = now ?? DateTime.now,
        _random = random ?? Random();

  final String instanceName;
  final ResolvedSyncPolicy policy;
  final SyncProfileRepository profiles;
  final LocalReplicaFactory localFactory;
  final ReconciliationStateRepository stateRepository;
  final SyncReconciler reconciler;
  final Map<String, SyncBackendFactory> backends;
  final SyncRuntimeSignals? runtimeSignals;
  final SyncBackgroundScheduler? backgroundScheduler;
  final SyncMergePolicy? merge;
  final DateTime Function() _now;
  final Random _random;
  final StreamController<SyncSnapshot> _states = StreamController.broadcast();
  SyncSnapshot _snapshot = const SyncSnapshot.initial();
  LocalReplica? _local;
  RemoteReplica? _remote;
  RemoteReplicaCapabilities? _remoteCapabilities;
  StreamSubscription<Object?>? _localSubscription;
  StreamSubscription<Object?>? _resumeSubscription;
  StreamSubscription<Object?>? _connectivitySubscription;
  StreamSubscription<Object?>? _remoteSubscription;
  Timer? _debounceTimer;
  Timer? _maxDelayTimer;
  Timer? _pollTimer;
  Timer? _retryTimer;
  Future<SyncRunReport>? _running;
  bool _rerun = false;
  int _retryAttempt = 0;
  bool _started = false;
  bool _disposed = false;

  @override
  SyncSnapshot get snapshot => _snapshot;
  @override
  Stream<SyncSnapshot> get states => _states.stream;

  void _emit(SyncSnapshot value) {
    _snapshot = value;
    if (!_states.isClosed) _states.add(value);
  }

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _openActiveProfile();
    _resumeSubscription = runtimeSignals?.resumed.listen((_) {
      if (policy.mode == SyncMode.automatic && policy.triggers.resume) {
        _schedule(SyncTrigger.resume);
      }
    });
    _connectivitySubscription =
        runtimeSignals?.connectivityRestored.listen((_) {
      if (policy.mode == SyncMode.automatic &&
          policy.triggers.connectivityRestored) {
        _retryAttempt = 0;
        _schedule(SyncTrigger.connectivityRestored);
      }
    });
    await backgroundScheduler?.configure(
      instanceName,
      policy.mode == SyncMode.automatic ? policy.background : null,
    );
    _configureDiscovery();
    if (policy.mode == SyncMode.automatic && policy.triggers.startup) {
      _schedule(SyncTrigger.startup);
    }
  }

  Future<void> _openActiveProfile() async {
    await _localSubscription?.cancel();
    await _remoteSubscription?.cancel();
    await _local?.close();
    await _remote?.close();
    _local = null;
    _remote = null;
    _remoteCapabilities = null;
    final profile = await profiles.active();
    _emit(_snapshot.copyWith(
        activeProfileId: profile?.id,
        localRevision: _snapshot.localRevision + 1));
    if (profile == null || profile.backend.isEmpty) return;
    final backend = backends[profile.backend];
    if (backend == null) {
      throw StateError('Unknown sync backend ${profile.backend}.');
    }
    _local = await localFactory.open(profile.id);
    _remote = await backend.open(profile, await profiles.secrets(profile.id));
    _remoteCapabilities = backend.capabilities;
    _localSubscription = _local!.changes.listen((change) {
      if (change.origin != SyncMutationOrigin.local ||
          policy.mode != SyncMode.automatic ||
          !policy.triggers.localWrite.enabled) {
        return;
      }
      _scheduleLocalWrite();
    });
    final discovery = _resolvedDiscovery(backend.capabilities);
    if (discovery == SyncRemoteDiscovery.push) {
      final hints = _remote!.changeHints;
      if (hints != null) {
        _remoteSubscription =
            hints.listen((_) => _schedule(SyncTrigger.remoteChange));
      }
    }
  }

  SyncRemoteDiscovery _resolvedDiscovery(
      RemoteReplicaCapabilities capabilities) {
    if (policy.discovery.remoteChanges != SyncRemoteDiscovery.auto) {
      return policy.discovery.remoteChanges;
    }
    return capabilities.changeFeed
        ? SyncRemoteDiscovery.push
        : SyncRemoteDiscovery.poll;
  }

  void _configureDiscovery() {
    _pollTimer?.cancel();
    if (policy.mode != SyncMode.automatic || _remote == null) return;
    final capabilities = _remoteCapabilities;
    if (capabilities == null) return;
    final discovery = _resolvedDiscovery(capabilities);
    if (discovery == SyncRemoteDiscovery.poll) {
      _pollTimer = Timer.periodic(
          policy.discovery.pollInterval, (_) => _schedule(SyncTrigger.poll));
    } else if (discovery == SyncRemoteDiscovery.push &&
        policy.discovery.safetyReconcileInterval > Duration.zero) {
      _pollTimer = Timer.periodic(policy.discovery.safetyReconcileInterval,
          (_) => _schedule(SyncTrigger.poll));
    }
  }

  void _scheduleLocalWrite() {
    _emit(_snapshot.copyWith(
        phase: SyncPhase.scheduled,
        pending: true,
        trigger: SyncTrigger.localWrite));
    _debounceTimer?.cancel();
    _debounceTimer = Timer(policy.triggers.localWrite.debounce,
        () => _schedule(SyncTrigger.localWrite));
    _maxDelayTimer ??= Timer(policy.triggers.localWrite.maxDelay, () {
      _maxDelayTimer = null;
      _debounceTimer?.cancel();
      _schedule(SyncTrigger.localWrite);
    });
    if (policy.background?.enqueueOnPending == true) {
      backgroundScheduler?.enqueue(instanceName);
    }
  }

  void _schedule(SyncTrigger trigger) {
    if (_disposed) return;
    unawaited(_run(trigger));
  }

  Future<SyncRunReport> _run(SyncTrigger trigger) async {
    if (_running case final running?) {
      switch (policy.execution.busyBehavior) {
        case SyncBusyBehavior.reject:
          return SyncRunReport(
              trigger: trigger,
              failure: const SyncFailure(
                  SyncFailureKind.cancelled, 'A sync is already running.'));
        case SyncBusyBehavior.coalesce:
          return running;
        case SyncBusyBehavior.coalesceThenRerun:
          _rerun = true;
          return running;
      }
    }
    final local = _local;
    final remote = _remote;
    final profileId = _snapshot.activeProfileId;
    if (local == null || remote == null || profileId == null) {
      return SyncRunReport(
          trigger: trigger,
          failure: const SyncFailure(SyncFailureKind.configuration,
              'No configured active sync profile.'));
    }
    _debounceTimer?.cancel();
    _maxDelayTimer?.cancel();
    _maxDelayTimer = null;
    _retryTimer?.cancel();
    final startedAt = _now();
    _emit(_snapshot.copyWith(
        phase: SyncPhase.syncing,
        trigger: trigger,
        lastAttemptAt: startedAt,
        pending: false,
        clearNextRetry: true));
    final future = reconciler
        .reconcile(SyncReconcileRequest(
          profileId: profileId,
          trigger: trigger,
          local: local,
          remote: remote,
          state: stateRepository,
          policy: policy,
          now: _now(),
          merge: merge,
        ))
        .timeout(
          policy.execution.timeout,
          onTimeout: () => SyncRunReport(
              trigger: trigger,
              failure: const SyncFailure(
                  SyncFailureKind.timeout, 'Sync timed out.',
                  retryable: true)),
        );
    _running = future;
    final report = await future;
    _running = null;
    final phase = report.failure != null
        ? (report.failure!.kind == SyncFailureKind.connectivity
            ? SyncPhase.offline
            : SyncPhase.failed)
        : report.conflicts > 0
            ? SyncPhase.conflicted
            : SyncPhase.succeeded;
    if (report.isSuccess) _retryAttempt = 0;
    _emit(_snapshot.copyWith(
      phase: phase,
      lastReport: report,
      lastSuccessAt: report.isSuccess ? _now() : null,
      localRevision: _snapshot.localRevision +
          (report.downloaded + report.deletedLocally > 0 ? 1 : 0),
    ));
    if (report.failure?.retryable == true &&
        policy.mode == SyncMode.automatic) {
      _scheduleRetry();
    }
    if (_rerun) {
      _rerun = false;
      return _run(SyncTrigger.localWrite);
    }
    return report;
  }

  void _scheduleRetry() {
    final delay = policy.retry.delayFor(++_retryAttempt, _random);
    if (delay == null) return;
    final next = _now().add(delay);
    _emit(_snapshot.copyWith(
        phase: SyncPhase.scheduled, nextRetryAt: next, pending: true));
    _retryTimer = Timer(delay, () => _schedule(SyncTrigger.retry));
  }

  @override
  Future<SyncRunReport> syncNow() => _run(SyncTrigger.manual);
  @override
  Future<List<SyncProfile>> listProfiles() => profiles.list();

  @override
  Future<SyncProfile> saveProfile(SyncProfileDraft draft) async {
    final backend = backends[draft.backend];
    if (backend == null) {
      throw ArgumentError.value(
          draft.backend, 'backend', 'Unknown sync backend.');
    }
    await backend.validateProfile(draft);
    return profiles.save(draft);
  }

  @override
  Future<void> activateProfile(String profileId) async {
    if (_running != null) await _running;
    await profiles.activate(profileId);
    await _openActiveProfile();
    _configureDiscovery();
    if (policy.mode == SyncMode.automatic && policy.profiles.syncOnActivate) {
      _schedule(SyncTrigger.startup);
    }
  }

  @override
  Future<void> deleteProfile(String profileId,
      {required bool deleteLocalData}) async {
    if (_snapshot.activeProfileId == profileId) {
      throw StateError('Activate another profile before deleting $profileId.');
    }
    await profiles.delete(profileId, deleteLocalData: deleteLocalData);
    if (deleteLocalData) await localFactory.deleteProfile(profileId);
  }

  @override
  Future<List<SyncConflict>> listConflicts() async {
    final id = _snapshot.activeProfileId;
    return id == null ? const [] : stateRepository.conflicts(id);
  }

  @override
  Future<void> resolveConflict(
      String conflictId, SyncConflictResolution resolution) async {
    final id = _snapshot.activeProfileId;
    if (id == null) throw StateError('No active sync profile.');
    await stateRepository.resolve(id, conflictId, resolution);
    if (policy.mode == SyncMode.automatic) _schedule(SyncTrigger.localWrite);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _debounceTimer?.cancel();
    _maxDelayTimer?.cancel();
    _pollTimer?.cancel();
    _retryTimer?.cancel();
    await _localSubscription?.cancel();
    await _resumeSubscription?.cancel();
    await _connectivitySubscription?.cancel();
    await _remoteSubscription?.cancel();
    await _local?.close();
    await _remote?.close();
    await backgroundScheduler?.cancel(instanceName);
    await _states.close();
  }
}
