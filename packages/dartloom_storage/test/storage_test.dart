import 'package:dartloom_storage/dartloom_storage.dart';
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
}
