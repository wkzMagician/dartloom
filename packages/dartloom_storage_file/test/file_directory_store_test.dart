import 'dart:io';
import 'dart:typed_data';
import 'package:dartloom_storage_file/dartloom_storage_file.dart';
import 'package:test/test.dart';

void main() {
  test('FileObjectStore is binary safe', () async {
    final root = await Directory.systemTemp.createTemp('dartloom-object-');
    final store = await FileObjectStore.open(root: root);
    await store.write('nested/data.bin', Uint8List.fromList([0, 1, 255]));
    expect(await store.read('nested/data.bin'), [0, 1, 255]);
    expect((await store.scan()).single.contentHash, isNotNull);
    await store.close();
    await root.delete(recursive: true);
  });
}
