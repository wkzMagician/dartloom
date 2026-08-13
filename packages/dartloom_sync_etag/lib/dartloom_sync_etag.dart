import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartloom_sync/dartloom_sync.dart';

final class EtagReconciler implements SyncReconciler {
  const EtagReconciler();

  @override
  Future<SyncRunReport> reconcile(SyncReconcileRequest request) async {
    var uploaded = 0;
    var downloaded = 0;
    var deletedLocally = 0;
    var deletedRemotely = 0;
    final conflicts = <String, Map<String, Object?>>{};
    try {
      await request.remote.initialize();
      final state = await request.state.load(request.profileId);
      final records = _map(state['records']);
      final resolutions = _map(state['resolutions']);
      final localMetadata = {
        for (final item in await request.local.scan()) item.key: item,
      };
      final remoteScan =
          await request.remote.scan(cursor: state['cursor'] as String?);
      final remoteMetadata = {
        for (final item in remoteScan.objects) item.key: item,
      };
      if (remoteScan.kind == SyncScanKind.delta) {
        final known = _map(state['remote']);
        for (final entry in known.entries) {
          final item = _mapOrNull(entry.value);
          final version = item?['version'];
          if (version is String && !remoteMetadata.containsKey(entry.key)) {
            remoteMetadata[entry.key] =
                RemoteObjectMetadata(key: entry.key, version: version);
          }
        }
        for (final key in remoteScan.deletedKeys) {
          remoteMetadata.remove(key);
        }
      }
      final keys = <String>{
        ...localMetadata.keys,
        ...remoteMetadata.keys,
        ...records.keys
      }.toList()
        ..sort();

      for (final key in keys) {
        final localObject = await request.local.read(key);
        final remoteMeta = remoteMetadata[key];
        final record = _mapOrNull(records[key]);
        if (record?['tombstone'] == true &&
            localObject == null &&
            remoteMeta == null) {
          final deletedAt =
              DateTime.tryParse(record?['deletedAt'] as String? ?? '');
          if (deletedAt == null ||
              request.now.difference(deletedAt) >=
                  request.policy.state.tombstoneRetention) {
            records.remove(key);
          }
          continue;
        }
        final localHash = _hash(localObject?.data);
        final baseHash = record?['baseHash'] as String?;
        final previousRemoteVersion = record?['remoteVersion'] as String?;
        final localChanged =
            record == null ? localObject != null : localHash != baseHash;
        final remoteChanged = record == null
            ? remoteMeta != null
            : remoteMeta?.version != previousRemoteVersion;

        if (!localChanged && !remoteChanged) continue;
        if (localChanged && !remoteChanged) {
          if (localObject == null) {
            try {
              await request.remote.delete(key,
                  condition: previousRemoteVersion == null
                      ? null
                      : RemoteWriteCondition.version(previousRemoteVersion));
              records[key] = _tombstone(request.now);
              remoteMetadata.remove(key);
              deletedRemotely++;
            } on RemotePreconditionException {
              await _recordConflict(
                  conflicts, key, null, await request.remote.read(key), record);
            }
          } else {
            _checkObjectSize(key, localObject.data, request.policy);
            try {
              final version = await request.remote.write(
                key,
                localObject.data,
                condition: record == null
                    ? const RemoteWriteCondition.create()
                    : previousRemoteVersion == null
                        ? null
                        : RemoteWriteCondition.version(previousRemoteVersion),
              );
              records[key] = _record(version, localObject.data, request.policy);
              remoteMetadata[key] =
                  RemoteObjectMetadata(key: key, version: version);
              uploaded++;
            } on RemotePreconditionException {
              await _recordConflict(conflicts, key, localObject.data,
                  await request.remote.read(key), record);
            }
          }
          continue;
        }

        if (!localChanged && remoteChanged) {
          final remoteObject = await request.remote.read(key);
          if (remoteObject == null) {
            final deleted = await request.local
                .delete(key, expectedVersion: localObject?.version);
            if (!deleted) {
              await _recordConflict(conflicts, key,
                  (await request.local.read(key))?.data, null, record);
              continue;
            }
            records[key] = _tombstone(request.now);
            deletedLocally++;
          } else {
            _checkObjectSize(key, remoteObject.data, request.policy);
            final written = await request.local.write(key, remoteObject.data,
                expectedVersion: localObject?.version);
            if (!written) {
              await _recordConflict(conflicts, key,
                  (await request.local.read(key))?.data, remoteObject, record);
              continue;
            }
            records[key] = _record(
                remoteObject.version, remoteObject.data, request.policy);
            downloaded++;
          }
          continue;
        }

        final remoteObject = await request.remote.read(key);
        if (localObject == null && remoteObject == null) {
          records[key] = _tombstone(request.now);
          continue;
        }
        if (localObject != null &&
            remoteObject != null &&
            _hash(remoteObject.data) == localHash) {
          records[key] =
              _record(remoteObject.version, localObject.data, request.policy);
          continue;
        }
        final conflict = SyncConflict(
          id: _conflictId(request.profileId, key),
          key: key,
          local: localObject?.data,
          remote: remoteObject?.data,
          base: _decode(record?['base']),
        );
        final resolution = await _resolve(
          conflict,
          request,
          _mapOrNull(resolutions[conflict.id]),
        );
        if (resolution == null) {
          conflicts[conflict.id] = _conflictMap(conflict);
          continue;
        }
        resolutions.remove(conflict.id);
        if (resolution.$1 == null) {
          if (localObject != null) {
            if (!await request.local
                .delete(key, expectedVersion: localObject.version)) {
              conflicts[conflict.id] = _conflictMap(conflict);
              continue;
            }
            deletedLocally++;
          }
          if (remoteObject != null) {
            try {
              await request.remote.delete(key,
                  condition:
                      RemoteWriteCondition.version(remoteObject.version));
              remoteMetadata.remove(key);
              deletedRemotely++;
            } on RemotePreconditionException {
              conflicts[conflict.id] = _conflictMap(conflict);
              continue;
            }
          }
          records[key] = _tombstone(request.now);
          continue;
        }
        final data = resolution.$1!;
        _checkObjectSize(key, data, request.policy);
        if (localObject == null || _hash(localObject.data) != _hash(data)) {
          if (!await request.local
              .write(key, data, expectedVersion: localObject?.version)) {
            conflicts[conflict.id] = _conflictMap(conflict);
            continue;
          }
          downloaded++;
        }
        try {
          final version = await request.remote.write(
            key,
            data,
            condition: remoteObject == null
                ? const RemoteWriteCondition.create()
                : RemoteWriteCondition.version(remoteObject.version),
          );
          records[key] = _record(version, data, request.policy);
          remoteMetadata[key] =
              RemoteObjectMetadata(key: key, version: version);
          uploaded++;
        } on RemotePreconditionException {
          conflicts[conflict.id] = _conflictMap(conflict);
        }
      }

      state['records'] = records;
      state['resolutions'] = resolutions;
      state['remote'] = {
        for (final entry in remoteMetadata.entries)
          entry.key: {'version': entry.value.version},
      };
      state['cursor'] = remoteScan.cursor;
      state['conflicts'] = conflicts;
      await request.state.save(request.profileId, state);
      return SyncRunReport(
        trigger: request.trigger,
        uploaded: uploaded,
        downloaded: downloaded,
        deletedLocally: deletedLocally,
        deletedRemotely: deletedRemotely,
        conflicts: conflicts.length,
      );
    } on SyncOperationException catch (error) {
      return SyncRunReport(trigger: request.trigger, failure: error.failure);
    } on TimeoutException {
      return SyncRunReport(
        trigger: request.trigger,
        failure: const SyncFailure(
            SyncFailureKind.timeout, 'Remote operation timed out.',
            retryable: true),
      );
    } on Object catch (error) {
      return SyncRunReport(
        trigger: request.trigger,
        failure: SyncFailure(SyncFailureKind.unknown, error.toString(),
            retryable: true),
      );
    }
  }

  Future<(Uint8List?, bool)?> _resolve(
    SyncConflict conflict,
    SyncReconcileRequest request,
    Map<String, Object?>? storedResolution,
  ) async {
    if (storedResolution != null) {
      final choice = storedResolution['choice'];
      if (choice == 'local') return (conflict.local, true);
      if (choice == 'remote') return (conflict.remote, true);
      if (choice == 'delete') return (null, true);
      if (choice == 'merged') {
        final merged = _decode(storedResolution['merged']);
        if (merged != null) return (merged, true);
      }
      return null;
    }
    if ((conflict.local == null) != (conflict.remote == null)) {
      switch (request.policy.conflicts.deleteVsUpdate) {
        case SyncDeleteConflictStrategy.conflict:
          return null;
        case SyncDeleteConflictStrategy.deleteWins:
          return (null, true);
        case SyncDeleteConflictStrategy.updateWins:
          return (conflict.local ?? conflict.remote, true);
      }
    }
    switch (request.policy.conflicts.strategy) {
      case SyncConflictStrategy.preserve:
        return null;
      case SyncConflictStrategy.localWins:
        return (conflict.local, true);
      case SyncConflictStrategy.remoteWins:
        return (conflict.remote, true);
      case SyncConflictStrategy.merge:
        final merge = request.merge;
        if (merge == null) return null;
        final value = await merge(conflict);
        return value == null ? null : (value, true);
    }
  }

  void _checkObjectSize(String key, Uint8List data, ResolvedSyncPolicy policy) {
    if (data.lengthInBytes <= policy.execution.maxObjectSize) return;
    throw SyncOperationException(SyncFailure(
      SyncFailureKind.configuration,
      'Sync object $key is ${data.lengthInBytes} bytes, above the configured maximum of ${policy.execution.maxObjectSize} bytes.',
    ));
  }

  Future<void> _recordConflict(
    Map<String, Map<String, Object?>> conflicts,
    String key,
    Uint8List? local,
    RemoteObject? remote,
    Map<String, Object?>? record,
  ) async {
    final conflict = SyncConflict(
      id: key,
      key: key,
      local: local,
      remote: remote?.data,
      base: _decode(record?['base']),
    );
    conflicts[conflict.id] = _conflictMap(conflict);
  }

  Map<String, Object?> _record(
          String remoteVersion, Uint8List data, ResolvedSyncPolicy policy) =>
      {
        'remoteVersion': remoteVersion,
        'baseHash': _hash(data),
        if (policy.state.basePayload == SyncBasePayloadPolicy.always)
          'base': base64Encode(data),
      };

  Map<String, Object?> _tombstone(DateTime now) => {
        'tombstone': true,
        'baseHash': '__deleted__',
        'deletedAt': now.toUtc().toIso8601String(),
      };

  Map<String, Object?> _conflictMap(SyncConflict conflict) => {
        'id': conflict.id,
        'key': conflict.key,
        'local': _encode(conflict.local),
        'remote': _encode(conflict.remote),
        'base': _encode(conflict.base),
      };

  String _conflictId(String profileId, String key) => '$profileId::$key';
  String? _hash(Uint8List? data) =>
      data == null ? null : sha256.convert(data).toString();
  String? _encode(Uint8List? data) => data == null ? null : base64Encode(data);
  Uint8List? _decode(Object? data) =>
      data is String ? base64Decode(data) : null;
  Map<String, Object?> _map(Object? value) =>
      value is Map ? value.cast<String, Object?>() : <String, Object?>{};
  Map<String, Object?>? _mapOrNull(Object? value) =>
      value is Map ? value.cast<String, Object?>() : null;
}
