import 'dart:io';
import 'dart:typed_data';

import 'package:dartloom_storage_json_file/dartloom_storage_json_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('persists JSON values across store instances', () async {
    final directory = await Directory.systemTemp.createTemp('dartloom_json');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}data.json');
    final first = JsonFileStore(file);
    await first.write('config', {'theme': 'dark'});
    final second = JsonFileStore(file);
    expect(await second.read('config'), {'theme': 'dark'});
  });

  test('directory store keeps replica paths and bytes isomorphic', () async {
    final base = await Directory.systemTemp.createTemp('dartloom_directory');
    addTearDown(() => base.delete(recursive: true));
    final data = Directory('${base.path}${Platform.pathSeparator}MiniTodo');
    final metadata = Directory('${base.path}${Platform.pathSeparator}meta');
    final store = await JsonDirectoryStore.openAt(
      directory: data,
      metadataDirectory: metadata,
      allowedKeys: const {'.mini-todo.json'},
      allowedPrefixes: const ['todo-'],
    );
    addTearDown(store.close);

    final remoteBytes = Uint8List.fromList('{ "id": "42" }'.codeUnits);
    await store.writeReplicaBytes('todo-42', remoteBytes);

    expect(
        await File('${data.path}${Platform.pathSeparator}todo-42')
            .readAsBytes(),
        remoteBytes);
    expect(await store.read('todo-42'), {'id': '42'});
    expect(store.acceptsReplicaKey('other-app-file'), isFalse);
    expect(await metadata.list().isEmpty, isFalse);
  });

  test('directory store persists local deletions outside the replica',
      () async {
    final base = await Directory.systemTemp.createTemp('dartloom_deletions');
    addTearDown(() => base.delete(recursive: true));
    final data = Directory('${base.path}${Platform.pathSeparator}MiniTodo');
    final metadata = Directory('${base.path}${Platform.pathSeparator}meta');
    final store = await JsonDirectoryStore.openAt(
      directory: data,
      metadataDirectory: metadata,
    );
    await store.write('todo-1', {'id': '1'});
    await store.delete('todo-1');
    expect(await store.deletedKeys(), {'todo-1'});
    expect(await data.list().isEmpty, isTrue);
    await store.forgetDeletedKey('todo-1');
    expect(await store.deletedKeys(), isEmpty);
    await store.close();
  });

  test('legacy migration exports allowed records and preserves the source',
      () async {
    final base = await Directory.systemTemp.createTemp('dartloom_legacy');
    addTearDown(() => base.delete(recursive: true));
    final legacy = File('${base.path}${Platform.pathSeparator}data.json');
    await legacy.writeAsString('''{
      "__dartloom_profiles/default/todo-1": {"id":"1"},
      "__dartloom_profiles/default/other": {"secret":true},
      "__dartloom_sync_v3/default/default": {"records":{}}
    }''');
    final data = Directory('${base.path}${Platform.pathSeparator}MiniTodo');
    final store = await JsonDirectoryStore.openAt(
      directory: data,
      metadataDirectory: Directory(
        '${base.path}${Platform.pathSeparator}metadata',
      ),
      legacyJsonFile: legacy,
      legacyKeyPrefix: '__dartloom_profiles/default/',
      allowedPrefixes: const ['todo-'],
    );

    expect(await store.list(), ['todo-1']);
    expect(await legacy.exists(), isTrue);
    expect(await store.read('other'), isNull);
    await store.close();
  });
}
