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

  test('structured JSON codec round-trips nested values', () {
    const value = <String, Object?>{
      'version': 2,
      'enabled': true,
      'labels': ['one', 'two'],
      'nested': {'unknownField': 'preserved'},
    };
    expect(SettingsJsonCodec.decode(SettingsJsonCodec.encode(value)), value);
  });

  test('structured JSON codec rejects unsupported and malformed values', () {
    expect(() => SettingsJsonCodec.encode(Object()), throwsArgumentError);
    expect(() => SettingsJsonCodec.decode('{'), throwsFormatException);
  });
}
