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

  test('reads optional platform build hooks and native targets', () {
    final config = const ConfigLoader().parse('''platforms:
  - ios
packages: []
build:
  ios:
    post_build:
      - tool/build_native_targets.sh
    native_targets:
      - AnyProjectTarget
''');
    final ios = config.build[TargetPlatform.ios]!;
    expect(ios.postBuild, ['tool/build_native_targets.sh']);
    expect(ios.nativeTargets, ['AnyProjectTarget']);
    expect(config.toYaml(), contains('native_targets:'));
  });

  test('rejects targets without a platform build hook', () {
    expect(
      () => const ConfigLoader().parse('''platforms:
  - ios
packages: []
build:
  ios:
    native_targets:
      - AnyProjectTarget
'''),
      throwsA(isA<ConfigException>()),
    );
  });
}
