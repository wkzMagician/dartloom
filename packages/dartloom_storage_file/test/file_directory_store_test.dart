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

  test('exclusive lock permits nested durable operations', () async {
    final root = await Directory.systemTemp.createTemp('dartloom-lock-');
    final store = await FileObjectStore.open(root: root);
    await store.withExclusiveLock(
        () => store.write('nested/data.bin', Uint8List.fromList([9, 8, 7])));
    expect(await store.read('nested/data.bin'), [9, 8, 7]);
    await store.close();
    await root.delete(recursive: true);
  });

  test('accepts hierarchical keys without an opt-in flag', () async {
    final root = await Directory.systemTemp.createTemp('dartloom-keys-');
    final store = await FileObjectStore.open(root: root);
    await store.write(
        '__dartloom_journal/v1/events/00000000000000000001-a-prepared.json',
        Uint8List.fromList([1]));
    await store.write(
        '__dartloom_journal/v1/sequence', Uint8List.fromList([2]));
    expect(await store.scan(), hasLength(2));
    expect(
      (await store.scan()).map((item) => item.key),
      containsAll([
        '__dartloom_journal/v1/events/00000000000000000001-a-prepared.json',
        '__dartloom_journal/v1/sequence',
      ]),
    );
    await store.close();
    await root.delete(recursive: true);
  });
}
