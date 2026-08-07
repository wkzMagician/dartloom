import 'dart:io';

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
}
