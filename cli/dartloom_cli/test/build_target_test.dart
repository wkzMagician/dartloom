import 'package:dartloom_cli/src/build/build_target.dart';
import 'package:dartloom_cli/src/config/dartloom_config.dart';
import 'package:dartloom_cli/src/packaging/package_target.dart';
import 'package:test/test.dart';

void main() {
  test('parses a configured build target', () {
    expect(BuildTarget.parse('windows').platform, TargetPlatform.windows);
  });

  test('rejects an invalid build target', () {
    expect(() => BuildTarget.parse('desktop'), throwsArgumentError);
  });

  test('resolves supported installer and package formats', () {
    expect(PackageTarget.parse('windows', 'exe'), PackageTarget.windowsExe);
    expect(PackageTarget.parse('linux', 'rpm'), PackageTarget.linuxRpm);
  });

  test('rejects unsupported package formats', () {
    expect(() => PackageTarget.parse('macos', 'dmg'), throwsArgumentError);
  });
}
