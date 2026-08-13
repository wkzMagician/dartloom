import 'package:dartloom_sync/dartloom_sync.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

typedef DartloomSyncCallbackDispatcher = void Function();
typedef DartloomSyncWorkerRunner = Future<bool> Function(String instanceName);

void executeDartloomSyncWorker(DartloomSyncWorkerRunner runner) {
  Workmanager().executeTask((task, inputData) async {
    final instance = inputData?['instance'];
    if (instance is! String || instance.isEmpty) return false;
    final timeoutMs = inputData?['timeout_ms'];
    final work = runner(instance);
    if (timeoutMs is! int || timeoutMs <= 0) return work;
    return work.timeout(
      Duration(milliseconds: timeoutMs),
      onTimeout: () => false,
    );
  });
}

final class WorkmanagerSyncBackgroundScheduler
    implements SyncBackgroundScheduler {
  WorkmanagerSyncBackgroundScheduler({
    required this.callbackDispatcher,
    Workmanager? workmanager,
  }) : _workmanager = workmanager ?? Workmanager();

  final DartloomSyncCallbackDispatcher callbackDispatcher;
  final Workmanager _workmanager;
  final Map<String, SyncBackgroundPolicy> _policies = {};
  bool _initialized = false;

  String _periodicName(String instanceName) =>
      'dartloom.sync.$instanceName.periodic';
  String _pendingName(String instanceName) =>
      'dartloom.sync.$instanceName.pending';

  Future<void> _initialize() async {
    if (_initialized) return;
    await _workmanager.initialize(callbackDispatcher);
    _initialized = true;
  }

  @override
  Future<void> configure(
      String instanceName, SyncBackgroundPolicy? policy) async {
    if (!_isMobile) return;
    await _initialize();
    if (policy == null || !policy.enabled) {
      _policies.remove(instanceName);
      await cancel(instanceName);
      return;
    }
    _policies[instanceName] = policy;
    final frequency = defaultTargetPlatform == TargetPlatform.android
        ? policy.periodicInterval
        : policy.earliestBegin;
    await _workmanager.registerPeriodicTask(
      _periodicName(instanceName),
      'dartloomSync',
      frequency: frequency,
      flexInterval: defaultTargetPlatform == TargetPlatform.android
          ? policy.flexInterval
          : null,
      inputData: {
        'instance': instanceName,
        'trigger': 'background',
        'timeout_ms': policy.timeout.inMilliseconds,
      },
      constraints: Constraints(
        networkType: _networkType(policy),
        requiresBatteryNotLow: policy.requiresBatteryNotLow,
        requiresCharging: policy.requiresCharging,
      ),
    );
  }

  @override
  Future<void> enqueue(String instanceName) async {
    if (!_isMobile) return;
    await _initialize();
    final policy = _policies[instanceName];
    await _workmanager.registerOneOffTask(
      _pendingName(instanceName),
      'dartloomSync',
      inputData: {
        'instance': instanceName,
        'trigger': 'background',
        if (policy != null) 'timeout_ms': policy.timeout.inMilliseconds,
      },
      constraints: Constraints(
        networkType:
            policy == null ? NetworkType.connected : _networkType(policy),
      ),
    );
  }

  @override
  Future<void> cancel(String instanceName) async {
    if (!_isMobile) return;
    await _workmanager.cancelByUniqueName(_periodicName(instanceName));
    await _workmanager.cancelByUniqueName(_pendingName(instanceName));
  }

  NetworkType _networkType(SyncBackgroundPolicy policy) {
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        !policy.requiresNetwork) {
      return NetworkType.notRequired;
    }
    return policy.network == 'unmetered'
        ? NetworkType.unmetered
        : NetworkType.connected;
  }

  bool get _isMobile =>
      !kIsWeb &&
      {TargetPlatform.android, TargetPlatform.iOS}
          .contains(defaultTargetPlatform);
}
