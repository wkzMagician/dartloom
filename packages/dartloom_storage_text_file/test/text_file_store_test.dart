import 'dart:io';
import 'dart:typed_data';

import 'package:dartloom_storage_text_file/dartloom_storage_text_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('writes atomically and prevents path traversal', () async {
    final directory = await Directory.systemTemp.createTemp('dartloom_text');
    addTearDown(() => directory.delete(recursive: true));
    final store = TextFileStore(directory);
    await store.write('folder/a.md', '# A');
    expect(await store.read('folder/a.md'), '# A');
    expect(await store.list(), ['folder/a.md']);
    expect(() => store.write('../escape', 'bad'), throwsArgumentError);
  });

  test('raw directory replica scans bytes and rejects unsafe keys', () async {
    final directory = await Directory.systemTemp.createTemp('dartloom_replica');
    addTearDown(() => directory.delete(recursive: true));
    final store = await FileDirectoryStore.openAt(root: directory);
    addTearDown(store.close);
    await store.writeBytes('folder/a.md', Uint8List.fromList([1, 2, 3]));
    expect((await store.scan()).single.key, 'folder/a.md');
    expect(await store.readBytes('folder/a.md'), [1, 2, 3]);
    expect(store.acceptsKey('../escape'), isFalse);
    expect(() => store.readBytes('../escape'), throwsArgumentError);
  });
}
