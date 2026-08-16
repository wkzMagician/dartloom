import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dartloom_storage/dartloom_storage.dart';

/// Shared contract checks for every ObjectStore backend.
void objectStoreContract(Future<ObjectStore> Function() open) {
  test('supports binary round trips and key validation', () async {
    final store = await open();
    addTearDown(store.close);
    expect(store.acceptsKey('nested/object'), isTrue);
    expect(store.acceptsKey('../escape'), isFalse);
    final bytes = Uint8List.fromList([0, 1, 2, 255]);
    await store.write('nested/object', bytes);
    expect(await store.read('nested/object'), bytes);
    expect((await store.scan()).single.size, bytes.length);
  });
}
