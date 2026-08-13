import 'package:dartloom_storage/dartloom_storage.dart';
import 'dart:typed_data';
import 'package:test/test.dart';

void main() {
  test('memory stores implement text, JSON, and document CRUD', () async {
    final text = MemoryTextStore();
    await text.write('a.md', '# A');
    expect(await text.read('a.md'), '# A');

    final json = MemoryJsonStore();
    await json.write('config', {'theme': 'dark'});
    expect(await json.read('config'), {'theme': 'dark'});

    final database = MemoryDatabaseStore();
    await database.write('items', '1', {'done': false});
    expect(await database.read('items', '1'), {'done': false});
    expect(await database.collections(), ['items']);
  });

  test('memory replica stores raw bytes and mutation origin', () async {
    final store = MemoryReplicaStore();
    final changes = <StoreChange>[];
    final subscription = store.changes.listen(changes.add);
    await store.writeBytes('note.md', Uint8List.fromList([1, 2]));
    expect(await store.readBytes('note.md'), [1, 2]);
    await store.delete('note.md', origin: StoreMutationOrigin.replica);
    expect(changes.map((change) => change.origin), [
      StoreMutationOrigin.local,
      StoreMutationOrigin.replica,
    ]);
    await subscription.cancel();
    await store.close();
  });
}
