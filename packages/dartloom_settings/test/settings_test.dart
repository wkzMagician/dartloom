import 'package:dartloom_settings/dartloom_settings.dart';
import 'package:test/test.dart';

void main() {
  test('stores and removes typed values', () async {
    final store = MemorySettingsStore();
    await store.write('theme', 'dark');
    expect(await store.read('theme'), 'dark');
    await store.remove('theme');
    expect(await store.read('theme'), isNull);
  });

  test('rejects values outside the portable settings types', () async {
    final store = MemorySettingsStore();
    expect(() => store.write('bad', <String, Object?>{}), throwsArgumentError);
  });
}
