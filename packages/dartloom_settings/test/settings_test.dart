import 'package:dartloom_settings/dartloom_settings.dart';
import 'package:test/test.dart';

void main() {
  test('stores and removes typed values', () async {
    final store = MemorySettingsStore();
    await store.write('theme', 'dark');
    expect(await store.read<String>('theme'), 'dark');
    await store.remove('theme');
    expect(await store.read<String>('theme'), isNull);
  });
}
