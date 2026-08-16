@TestOn('chrome')
library;

import 'dart:typed_data';

import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:dartloom_storage_indexeddb/dartloom_storage_indexeddb.dart';
import 'package:test/test.dart';

void main() {
  test('persists across store reopen and broadcasts to another context',
      () async {
    final namespace = 'dartloom-test-${DateTime.now().microsecondsSinceEpoch}';
    final first = IndexedDbObjectStore(namespace: namespace);
    await first.write('persisted', Uint8List.fromList([7, 8, 9]));
    await first.close();

    final reopened = IndexedDbObjectStore(namespace: namespace);
    expect(await reopened.read('persisted'), [7, 8, 9]);
    final second = IndexedDbObjectStore(namespace: namespace);
    await second.scan();
    final change = second.changes.first;
    await reopened.write('cross-context', Uint8List.fromList([1]));
    expect((await change).kind, StorageChangeKind.created);
    await reopened.close();
    await second.close();
  });
}
