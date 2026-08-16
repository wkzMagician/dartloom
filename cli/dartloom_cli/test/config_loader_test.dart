import 'package:test/test.dart';
import 'package:dartloom_cli/dartloom_cli.dart';

void main() {
  test('reads the project configuration model', () {
    final config = const ConfigLoader().parse('''platforms:
  - android
  - windows
packages:
  - dartloom_storage
  - dartloom_storage_file
''');
    expect(config.platforms,
        containsAll([TargetPlatform.android, TargetPlatform.windows]));
    expect(config.packages, ['dartloom_storage', 'dartloom_storage_file']);
    expect(config.toYaml(), contains('platforms:'));
  });

  test('rejects legacy configuration shapes', () {
    expect(() => const ConfigLoader().parse('legacy: true'),
        throwsA(isA<ConfigException>()));
  });
}
