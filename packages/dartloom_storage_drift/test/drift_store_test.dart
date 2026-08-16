import 'dart:typed_data';
import 'package:dartloom_storage_drift/dartloom_storage_drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stores binary objects', () async {
    final store = DriftObjectStore(NativeDatabase.memory());
    addTearDown(store.close);
    await store.write('items/1', Uint8List.fromList([1, 2, 3]));
    expect(await store.read('items/1'), [1, 2, 3]);
    expect((await store.scan()).single.key, 'items/1');
  });
}
