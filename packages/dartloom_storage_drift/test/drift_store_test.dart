import 'package:dartloom_storage_drift/dartloom_storage_drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stores documents without exposing Drift to the contract', () async {
    final store = DriftDocumentStore(NativeDatabase.memory());
    addTearDown(store.close);
    await store.initialize();
    await store.write('items', '1', {'done': false});
    expect(await store.read('items', '1'), {'done': false});
    expect(await store.list('items'), ['1']);
    await store.deleteDocument('items', '1');
    expect(await store.read('items', '1'), isNull);
  });
}
