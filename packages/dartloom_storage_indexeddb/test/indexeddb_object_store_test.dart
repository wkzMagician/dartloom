import 'dart:typed_data';
import 'package:dartloom_storage_indexeddb/dartloom_storage_indexeddb.dart';
import 'package:test/test.dart';

void main() {
  test('stores binary objects in a namespace', () async {
    final store = IndexedDbObjectStore(namespace: 'business');
    await store.write('a', Uint8List.fromList([1, 2]));
    expect(await store.read('a'), [1, 2]);
    expect((await store.scan()).single.key, 'a');
    await store.close();
  });
}
