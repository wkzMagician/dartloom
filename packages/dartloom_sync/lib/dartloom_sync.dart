import 'dart:typed_data';

enum SyncStatus { idle, syncing, succeeded, conflicted, failed }

class SyncResult {
  const SyncResult({
    required this.status,
    this.message,
    this.uploaded = 0,
    this.downloaded = 0,
    this.deleted = 0,
    this.conflicts = 0,
  });
  final SyncStatus status;
  final String? message;
  final int uploaded;
  final int downloaded;
  final int deleted;
  final int conflicts;
  bool get isSuccess => status == SyncStatus.succeeded;
}

class SyncObject {
  const SyncObject({required this.key, required this.data, this.etag});
  final String key;
  final Uint8List data;
  final String? etag;
}

class RemoteObjectMetadata {
  const RemoteObjectMetadata({required this.key, required this.etag});
  final String key;
  final String etag;
}

abstract interface class LocalSyncStore {
  Future<List<String>> list();
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List data);
  Future<void> delete(String key);
}

abstract interface class RemoteObjectStore {
  Future<void> initialize();
  Future<List<RemoteObjectMetadata>> list();
  Future<SyncObject?> read(String key);
  Future<String> write(
    String key,
    Uint8List data, {
    String? ifMatch,
    bool createOnly = false,
  });
  Future<void> delete(String key, {String? ifMatch});
}

abstract interface class SyncStateStore {
  Future<Map<String, Object?>> load();
  Future<void> save(Map<String, Object?> state);
}

class SyncConflict {
  const SyncConflict({
    required this.key,
    required this.local,
    required this.remote,
    this.base,
  });
  final String key;
  final Uint8List? local;
  final Uint8List? remote;
  final Uint8List? base;
}

typedef SyncMergePolicy = Future<Uint8List?> Function(SyncConflict conflict);

class SyncPreconditionException implements Exception {
  const SyncPreconditionException(this.key);
  final String key;
  @override
  String toString() => 'Remote object precondition failed for $key.';
}

abstract interface class SyncEngine {
  Future<SyncResult> sync();
  Future<SyncStatus> status();
  Future<List<SyncConflict>> conflicts();
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

  @override
  Future<List<SyncConflict>> conflicts() async => const [];
}
