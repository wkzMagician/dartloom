import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:test/test.dart';

void main() {
  test('memory storage has a lifecycle', () async {
    final store = MemoryLocalStore();
    await store.initialize();
    expect(store.isInitialized, isTrue);
    await store.close();
    expect(store.isInitialized, isFalse);
  });
}
