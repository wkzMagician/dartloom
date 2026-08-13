import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:dartloom_sync/dartloom_sync.dart';

final class EtagReconciler implements SyncReconciler {
  const EtagReconciler();

  @override
  Future<SyncRunReport> reconcile(SyncReconcileRequest request) async {
    var uploaded = 0;
    var downloaded = 0;
    var deletedLocally = 0;
    var deletedRemotely = 0;
    try {
      var state = await request.state.load(request.profileId);
      await request.remote.initialize();
      final fingerprint = _hash(Uint8List.fromList(utf8.encode(
        'dartloom-sync-v5\n${request.local.identity}\n${request.remote.identity}',
      )));
      if (state.fingerprint != null && state.fingerprint != fingerprint) {
        state = SyncState(fingerprint: fingerprint);
      }

      final records = Map<String, SyncRecord>.of(state.records);
      final conflicts = <String, StoredConflict>{};
      final resolutions = Map<String, StoredResolution>.of(state.resolutions);
      final remoteVersions = Map<String, String>.of(state.remoteVersions);
      final intents = await request.local.intents();
      final intentsByKey = <String, List<StoreIntent>>{};
      for (final intent in intents) {
        (intentsByKey[intent.key] ??= []).add(intent);
      }
      final localScan = {
        for (final item in await request.local.scan()) item.key: item,
      };
      final remoteScan = await request.remote.scan(cursor: state.cursor);
      final remoteMetadata = <String, RemoteObjectMetadata>{
        for (final item in remoteScan.objects)
          if (request.local.acceptsKey(item.key)) item.key: item,
      };
      if (remoteScan.kind == SyncScanKind.delta || !remoteScan.complete) {
        for (final entry in remoteVersions.entries) {
          remoteMetadata.putIfAbsent(
            entry.key,
            () => RemoteObjectMetadata(key: entry.key, version: entry.value),
          );
        }
      }
      for (final key in remoteScan.deletedKeys) {
        remoteMetadata.remove(key);
      }

      final keys = <String>{
        ...localScan.keys,
        ...intentsByKey.keys,
        ...remoteMetadata.keys,
        ...records.keys,
      }.toList()
        ..sort();

      for (final key in keys) {
        if (!request.local.acceptsKey(key)) continue;
        final localMeta = localScan[key];
        final local =
            localMeta?.exists == false ? null : await request.local.read(key);
        final remoteMeta = remoteMetadata[key];
        final record = records[key];
        final keyIntents = intentsByKey[key] ?? const <StoreIntent>[];
        final intent = keyIntents.isEmpty ? null : keyIntents.last;
        final remoteAbsenceAuthoritative =
            remoteScan.deletedKeys.contains(key) ||
                (remoteScan.kind == SyncScanKind.full && remoteScan.complete);
        final remoteChanged = record == null
            ? remoteMeta != null
            : remoteMeta != null
                ? remoteMeta.version != record.remoteVersion
                : remoteAbsenceAuthoritative && !record.isTombstone;

        if (record?.isTombstone == true &&
            local == null &&
            remoteMeta == null &&
            intent == null) {
          if (record!.deletedAt == null ||
              request.now.difference(record.deletedAt!) >=
                  request.policy.state.tombstoneRetention) {
            records.remove(key);
          }
          continue;
        }

        // No authorized local intent means local bytes are observed only.
        // Restore known/remote data, ignore unregistered new files, and never
        // derive a remote mutation from absence or an incomplete scan.
        if (intent == null) {
          if (remoteMeta != null) {
            final remote = await request.remote.read(key);
            if (remote == null) continue;
            _checkObjectSize(key, remote.data, request.policy);
            if (local == null || _hash(local.data) != _hash(remote.data)) {
              final written = await request.local.write(
                key,
                remote.data,
                expectedVersion: local?.version,
              );
              if (!written) {
                conflicts[_conflictId(request.profileId, key)] = StoredConflict(
                  _conflict(
                      request.profileId, key, local?.data, remote, record),
                );
                continue;
              }
              downloaded++;
            }
            records[key] = _record(remote.version, remote.data, request.policy);
            remoteVersions[key] = remote.version;
          } else if (record != null &&
              remoteAbsenceAuthoritative &&
              local != null) {
            // Remote deletion is authoritative only after a complete scan.
            final deleted = await request.local.delete(
              key,
              expectedVersion: local.version,
            );
            if (deleted) {
              records[key] = _tombstone(request.now);
              remoteVersions.remove(key);
              deletedLocally++;
            }
          }
          continue;
        }

        if (intent.kind == StoreIntentKind.delete) {
          if (remoteMeta == null) {
            if (!remoteAbsenceAuthoritative) continue;
            records[key] = _tombstone(request.now);
            await _forget(request, keyIntents);
            continue;
          }
          if (remoteChanged) {
            switch (request.policy.conflicts.deleteVsUpdate) {
              case SyncDeleteConflictStrategy.conflict:
                conflicts[_conflictId(request.profileId, key)] = StoredConflict(
                  _conflict(
                    request.profileId,
                    key,
                    null,
                    await request.remote.read(key),
                    record,
                  ),
                );
                continue;
              case SyncDeleteConflictStrategy.deleteWins:
                try {
                  await request.remote.delete(
                    key,
                    condition: RemoteWriteCondition.version(remoteMeta.version),
                  );
                  records[key] = _tombstone(request.now);
                  remoteVersions.remove(key);
                  await _forget(request, keyIntents);
                  deletedRemotely++;
                } on RemotePreconditionException {
                  conflicts[_conflictId(request.profileId, key)] =
                      StoredConflict(_conflict(
                    request.profileId,
                    key,
                    null,
                    await request.remote.read(key),
                    record,
                  ));
                }
                continue;
              case SyncDeleteConflictStrategy.updateWins:
                final remote = await request.remote.read(key);
                if (remote != null &&
                    await request.local.write(key, remote.data)) {
                  records[key] =
                      _record(remote.version, remote.data, request.policy);
                  remoteVersions[key] = remote.version;
                  await _forget(request, keyIntents);
                  downloaded++;
                  continue;
                }
                conflicts[_conflictId(request.profileId, key)] = StoredConflict(
                  _conflict(request.profileId, key, null, remote, record),
                );
                continue;
            }
          }
          try {
            await request.remote.delete(
              key,
              condition: record?.remoteVersion == null
                  ? null
                  : RemoteWriteCondition.version(record!.remoteVersion!),
            );
            records[key] = _tombstone(request.now);
            remoteVersions.remove(key);
            await _forget(request, keyIntents);
            deletedRemotely++;
          } on RemotePreconditionException {
            conflicts[_conflictId(request.profileId, key)] = StoredConflict(
              _conflict(
                request.profileId,
                key,
                null,
                await request.remote.read(key),
                record,
              ),
            );
          }
          continue;
        }

        if (local == null) {
          // An intent without its payload is corrupt/incomplete. Preserve both
          // sides and surface a conflict instead of deleting anything.
          conflicts[_conflictId(request.profileId, key)] = StoredConflict(
            _conflict(
              request.profileId,
              key,
              null,
              await request.remote.read(key),
              record,
            ),
          );
          continue;
        }

        if (!remoteChanged) {
          _checkObjectSize(key, local.data, request.policy);
          try {
            final version = await request.remote.write(
              key,
              local.data,
              condition: record?.remoteVersion == null
                  ? const RemoteWriteCondition.create()
                  : RemoteWriteCondition.version(record!.remoteVersion!),
            );
            records[key] = _record(version, local.data, request.policy);
            remoteVersions[key] = version;
            await _forget(request, keyIntents);
            uploaded++;
          } on RemotePreconditionException {
            conflicts[_conflictId(request.profileId, key)] = StoredConflict(
              _conflict(
                request.profileId,
                key,
                local.data,
                await request.remote.read(key),
                record,
              ),
            );
          }
          continue;
        }

        final remote = await request.remote.read(key);
        final conflict = _conflict(
          request.profileId,
          key,
          local.data,
          remote,
          record,
        );
        final resolution = await _resolve(
          conflict,
          request,
          resolutions[conflict.id]?.value,
        );
        if (resolution == null ||
            resolution.choice == SyncConflictChoice.postpone) {
          conflicts[conflict.id] = StoredConflict(conflict);
          continue;
        }
        resolutions.remove(conflict.id);
        if (resolution.choice == SyncConflictChoice.deleteBoth) {
          await request.local.delete(key, expectedVersion: local.version);
          deletedLocally++;
          if (remote != null) {
            await request.remote.delete(
              key,
              condition: RemoteWriteCondition.version(remote.version),
            );
            deletedRemotely++;
          }
          records[key] = _tombstone(request.now);
          remoteVersions.remove(key);
          await _forget(request, keyIntents);
          continue;
        }
        final data = switch (resolution.choice) {
          SyncConflictChoice.useLocal => conflict.local,
          SyncConflictChoice.useRemote => conflict.remote,
          SyncConflictChoice.useMerged => resolution.merged,
          SyncConflictChoice.deleteBoth || SyncConflictChoice.postpone => null,
        };
        if (data == null) {
          conflicts[conflict.id] = StoredConflict(conflict);
          continue;
        }
        _checkObjectSize(key, data, request.policy);
        if (_hash(local.data) != _hash(data)) {
          if (!await request.local
              .write(key, data, expectedVersion: local.version)) {
            conflicts[conflict.id] = StoredConflict(conflict);
            continue;
          }
          downloaded++;
        }
        try {
          final version = await request.remote.write(
            key,
            data,
            condition: remote == null
                ? const RemoteWriteCondition.create()
                : RemoteWriteCondition.version(remote.version),
          );
          records[key] = _record(version, data, request.policy);
          remoteVersions[key] = version;
          await _forget(request, keyIntents);
          uploaded++;
        } on RemotePreconditionException {
          conflicts[conflict.id] = StoredConflict(conflict);
        }
      }

      await request.state.save(
        request.profileId,
        SyncState(
          fingerprint: fingerprint,
          cursor: remoteScan.cursor,
          records: Map.unmodifiable(records),
          remoteVersions: Map.unmodifiable(remoteVersions),
          conflicts: Map.unmodifiable(conflicts),
          resolutions: Map.unmodifiable(resolutions),
        ),
      );
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
    } on FormatException catch (error) {
      return SyncRunReport(
        trigger: request.trigger,
        failure: SyncFailure(
          SyncFailureKind.configuration,
          error.message,
          retryable: false,
        ),
      );
    } on TimeoutException {
      return SyncRunReport(
        trigger: request.trigger,
        failure: const SyncFailure(
          SyncFailureKind.timeout,
          'Remote operation timed out.',
          retryable: true,
        ),
      );
    } on Object catch (error) {
      return SyncRunReport(
        trigger: request.trigger,
        failure: SyncFailure(
          SyncFailureKind.unknown,
          error.toString(),
          retryable: true,
        ),
      );
    }
  }

  Future<SyncConflictResolution?> _resolve(
    SyncConflict conflict,
    SyncReconcileRequest request,
    SyncConflictResolution? stored,
  ) async {
    if (stored != null) return stored;
    if ((conflict.local == null) != (conflict.remote == null)) {
      return switch (request.policy.conflicts.deleteVsUpdate) {
        SyncDeleteConflictStrategy.conflict => null,
        SyncDeleteConflictStrategy.deleteWins =>
          const SyncConflictResolution(SyncConflictChoice.deleteBoth),
        SyncDeleteConflictStrategy.updateWins => SyncConflictResolution(
            conflict.local == null
                ? SyncConflictChoice.useRemote
                : SyncConflictChoice.useLocal,
          ),
      };
    }
    return switch (request.policy.conflicts.strategy) {
      SyncConflictStrategy.preserve => null,
      SyncConflictStrategy.localWins =>
        const SyncConflictResolution(SyncConflictChoice.useLocal),
      SyncConflictStrategy.remoteWins =>
        const SyncConflictResolution(SyncConflictChoice.useRemote),
      SyncConflictStrategy.merge => await _merge(conflict, request.merge),
    };
  }

  Future<SyncConflictResolution?> _merge(
    SyncConflict conflict,
    SyncMergePolicy? merge,
  ) async {
    if (merge == null) return null;
    final value = await merge(conflict);
    return value == null
        ? null
        : SyncConflictResolution(SyncConflictChoice.useMerged, merged: value);
  }

  SyncConflict _conflict(
    String profileId,
    String key,
    Uint8List? local,
    RemoteObject? remote,
    SyncRecord? record,
  ) =>
      SyncConflict(
        id: _conflictId(profileId, key),
        key: key,
        local: local,
        remote: remote?.data,
        base: record?.base,
      );

  Future<void> _forget(
    SyncReconcileRequest request,
    List<StoreIntent> intents,
  ) async {
    for (final intent in intents) {
      await request.local.forgetIntent(intent.operationId);
    }
  }

  SyncRecord _record(
    String remoteVersion,
    Uint8List data,
    ResolvedSyncPolicy policy,
  ) =>
      SyncRecord(
        remoteVersion: remoteVersion,
        baseHash: _hash(data),
        base: policy.state.basePayload == SyncBasePayloadPolicy.never
            ? null
            : Uint8List.fromList(data),
      );

  SyncRecord _tombstone(DateTime now) => SyncRecord(
        baseHash: '__deleted__',
        deletedAt: now.toUtc(),
      );

  void _checkObjectSize(String key, Uint8List data, ResolvedSyncPolicy policy) {
    if (data.lengthInBytes <= policy.execution.maxObjectSize) return;
    throw SyncOperationException(SyncFailure(
      SyncFailureKind.configuration,
      'Sync object $key is ${data.lengthInBytes} bytes, above the configured maximum of ${policy.execution.maxObjectSize} bytes.',
    ));
  }

  String _conflictId(String profileId, String key) => '$profileId::$key';
  String _hash(Uint8List data) => sha256.convert(data).toString();
}
