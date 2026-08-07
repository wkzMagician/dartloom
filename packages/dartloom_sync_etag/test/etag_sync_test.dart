import 'dart:typed_data';

import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:dartloom_sync/dartloom_sync.dart';
import 'package:dartloom_sync_etag/dartloom_sync_etag.dart';
import 'package:test/test.dart';

void main() {
  test('uploads, downloads, deletes, and preserves conflicts', () async {
    final localStore = MemoryTextStore();
    final state = MemoryJsonStore();
    final remote = FakeRemoteStore();
    final engine = EtagSyncEngine(
      local: TextLocalSyncStore(localStore),
      remote: remote,
      stateStore: JsonSyncStateStore(state, key: 'state'),
    );

    await localStore.write('a.md', 'local');
    expect((await engine.sync()).uploaded, 1);
    expect(String.fromCharCodes(remote.values['a.md']!), 'local');

    remote.externalWrite('a.md', Uint8List.fromList('remote'.codeUnits));
    expect((await engine.sync()).downloaded, 1);
    expect(await localStore.read('a.md'), 'remote');

    await localStore.write('a.md', 'local edit');
    remote.externalWrite('a.md', Uint8List.fromList('remote edit'.codeUnits));
    final conflict = await engine.sync();
    expect(conflict.status, SyncStatus.conflicted);
    expect(await engine.conflicts(), hasLength(1));

    final merged = EtagSyncEngine(
      local: TextLocalSyncStore(localStore),
      remote: remote,
      stateStore: JsonSyncStateStore(state, key: 'state'),
      merge: (_) async => Uint8List.fromList('merged'.codeUnits),
    );
    expect((await merged.sync()).status, SyncStatus.succeeded);
    expect(await localStore.read('a.md'), 'merged');

    await localStore.delete('a.md');
    expect((await merged.sync()).deleted, 1);
    expect(remote.values, isEmpty);
  });

  test('turns a failed ETag precondition into a preserved conflict', () async {
    final localStore = MemoryTextStore();
    final state = MemoryJsonStore();
    final remote = FakeRemoteStore();
    final engine = EtagSyncEngine(
      local: TextLocalSyncStore(localStore),
      remote: remote,
      stateStore: JsonSyncStateStore(state, key: 'state'),
    );
    await localStore.write('a.md', 'one');
    await engine.sync();
    await localStore.write('a.md', 'two');
    remote.failNextWrite = true;
    final result = await engine.sync();
    expect(result.status, SyncStatus.conflicted);
    expect(result.conflicts, 1);
  });
}

final class FakeRemoteStore implements RemoteObjectStore {
  final values = <String, Uint8List>{};
  final _etags = <String, String>{};
  var _revision = 0;
  bool failNextWrite = false;

  void externalWrite(String key, Uint8List value) {
    values[key] = value;
    _etags[key] = 'etag-${++_revision}';
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<List<RemoteObjectMetadata>> list() async => [
        for (final key in values.keys)
          RemoteObjectMetadata(key: key, etag: _etags[key]!),
      ];
  @override
  Future<SyncObject?> read(String key) async => values[key] == null
      ? null
      : SyncObject(key: key, data: values[key]!, etag: _etags[key]);
  @override
  Future<String> write(
    String key,
    Uint8List data, {
    String? ifMatch,
    bool createOnly = false,
  }) async {
    if (failNextWrite) {
      failNextWrite = false;
      externalWrite(key, Uint8List.fromList('raced'.codeUnits));
      throw SyncPreconditionException(key);
    }
    if ((createOnly && values.containsKey(key)) ||
        (ifMatch != null && _etags[key] != ifMatch)) {
      throw SyncPreconditionException(key);
    }
    externalWrite(key, Uint8List.fromList(data));
    return _etags[key]!;
  }

  @override
  Future<void> delete(String key, {String? ifMatch}) async {
    if (ifMatch != null && _etags[key] != ifMatch) {
      throw SyncPreconditionException(key);
    }
    values.remove(key);
    _etags.remove(key);
  }
}
