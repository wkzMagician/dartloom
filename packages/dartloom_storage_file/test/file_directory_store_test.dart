import 'dart:io';
import 'dart:typed_data';

import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:dartloom_storage_file/dartloom_storage_file.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late Directory root;
  late Directory metadata;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('dartloom_file_store');
    root = Directory('${temporary.path}${Platform.pathSeparator}business');
    metadata = Directory('${temporary.path}${Platform.pathSeparator}metadata');
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('round-trips UTF-8, non-UTF-8, and binary bytes', () async {
    final store =
        await FileDirectoryStore.open(root: root, metadataRoot: metadata);
    addTearDown(store.close);
    final fixtures = <String, Uint8List>{
      'utf8.md': Uint8List.fromList('浮念'.codeUnits),
      'invalid.bin': Uint8List.fromList([0xff, 0xfe, 0x00]),
      'binary.bin': Uint8List.fromList(List.generate(256, (index) => index)),
    };
    for (final entry in fixtures.entries) {
      await store.writeBytes(entry.key, entry.value);
      expect(await store.readBytes(entry.key), entry.value);
    }
    expect((await store.explicitIntents()).length, 3);
  });

  test('external changes are diagnostics and never intent', () async {
    final store =
        await FileDirectoryStore.open(root: root, metadataRoot: metadata);
    addTearDown(store.close);
    await store.writeBytes('known.md', Uint8List.fromList([1]));
    for (final intent in await store.explicitIntents()) {
      await store.forgetExplicitIntent(intent.operationId);
    }
    await File('${root.path}${Platform.pathSeparator}known.md')
        .writeAsBytes([2]);
    await File('${root.path}${Platform.pathSeparator}new.md').writeAsBytes([3]);
    final scan = await store.scan();
    expect(scan.singleWhere((item) => item.key == 'known.md').observation,
        ReplicaObservation.untrustedLocalChange);
    expect(scan.singleWhere((item) => item.key == 'new.md').observation,
        ReplicaObservation.unregisteredLocalObject);
    expect(await store.explicitIntents(), isEmpty);
    await File('${root.path}${Platform.pathSeparator}known.md').delete();
    expect(
        (await store.scan())
            .singleWhere((item) => item.key == 'known.md')
            .observation,
        ReplicaObservation.unexpectedMissing);
    expect(await store.explicitDeletedKeys(), isEmpty);
  });

  test('authorized deletion persists and root loss is not bulk delete',
      () async {
    var store =
        await FileDirectoryStore.open(root: root, metadataRoot: metadata);
    await store.writeBytes('a.md', Uint8List.fromList([1]));
    for (final intent in await store.explicitIntents()) {
      await store.forgetExplicitIntent(intent.operationId);
    }
    await store.delete('a.md');
    expect(await store.explicitDeletedKeys(), {'a.md'});
    await store.close();

    store = await FileDirectoryStore.open(root: root, metadataRoot: metadata);
    expect(await store.explicitDeletedKeys(), {'a.md'});
    await root.delete(recursive: true);
    await store.scan();
    expect(await root.exists(), isTrue);
    expect(await store.explicitDeletedKeys(), {'a.md'});
    await store.close();
  });

  test('requires safe absolute roots outside metadata', () async {
    expect(
      () => FileDirectoryStore.open(
        root: Directory('relative'),
        metadataRoot: metadata,
      ),
      throwsArgumentError,
    );
    final store =
        await FileDirectoryStore.open(root: root, metadataRoot: metadata);
    addTearDown(store.close);
    expect(store.acceptsKey(''), isFalse);
    expect(store.acceptsKey('../escape'), isFalse);
    expect(store.acceptsKey('/absolute'), isFalse);
  });

  test('does not follow links outside the business root', () async {
    final outside = Directory(
      '${temporary.path}${Platform.pathSeparator}outside',
    )..createSync();
    final outsideFile = File(
      '${outside.path}${Platform.pathSeparator}secret.bin',
    )..writeAsBytesSync([9]);
    await root.create(recursive: true);
    final link = Link('${root.path}${Platform.pathSeparator}escape.bin');
    try {
      await link.create(outsideFile.path);
    } on FileSystemException {
      return;
    }
    final store = await FileDirectoryStore.open(
      root: root,
      metadataRoot: metadata,
    );
    addTearDown(store.close);
    expect(
      () => store.readBytes('escape.bin'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await store.scan(), isEmpty);
  });
}
