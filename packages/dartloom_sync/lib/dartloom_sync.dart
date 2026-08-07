enum SyncStatus { idle, syncing, succeeded, failed }

class SyncResult {
  const SyncResult({required this.status, this.message});
  final SyncStatus status;
  final String? message;
  bool get isSuccess => status == SyncStatus.succeeded;
}

abstract interface class LocalSyncSource {
  Future<void> push();
}

abstract interface class RemoteSyncSource {
  Future<void> pull();
}

abstract interface class SyncEngine {
  Future<SyncResult> sync();
  Future<SyncStatus> status();
}

class NoopRemoteSyncSource implements RemoteSyncSource {
  const NoopRemoteSyncSource();
  @override
  Future<void> pull() async {}
}

class NoopSyncEngine implements SyncEngine {
  SyncStatus _status = SyncStatus.idle;
  @override
  Future<SyncResult> sync() async {
    _status = SyncStatus.syncing;
    _status = SyncStatus.succeeded;
    return const SyncResult(
        status: SyncStatus.succeeded, message: 'Noop sync completed.');
  }

  @override
  Future<SyncStatus> status() async => _status;
}
