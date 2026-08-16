import 'dart:typed_data';
import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:test/test.dart';

void main() {
  test('memory ObjectStore stores bytes and emits changes', () async {
    final store = MemoryObjectStore();
    final changes = <StorageChange>[];
    final subscription = store.changes.listen(changes.add);
    await store.write('note.bin', Uint8List.fromList([1, 2]));
    expect(await store.read('note.bin'), [1, 2]);
    expect((await store.scan()).single.size, 2);
    await store.delete('note.bin');
    expect(changes.map((change) => change.kind),
        [StorageChangeKind.created, StorageChangeKind.deleted]);
    await subscription.cancel();
    await store.close();
  });
}
