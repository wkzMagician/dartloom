import 'package:dartloom_cli/src/build/build_target.dart';
import 'package:dartloom_cli/src/config/dartloom_config.dart';
import 'package:test/test.dart';

void main() {
  test('parses a configured build target', () {
    expect(BuildTarget.parse('windows').platform, TargetPlatform.windows);
  });

  test('rejects an invalid build target', () {
    expect(() => BuildTarget.parse('desktop'), throwsArgumentError);
  });
}
