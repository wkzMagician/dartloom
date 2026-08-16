import 'package:dartloom_cli/src/commands/generated_tests.dart';
import 'package:dartloom_cli/src/config/dartloom_config.dart';
import 'package:test/test.dart';

void main() {
  test('generates icon checks for every Flutter platform', () {
    final source = appIconTest(TargetPlatform.values.toSet());

    expect(source,
        contains('android/app/src/main/res/mipmap-hdpi/ic_launcher.png'));
    expect(
        source,
        contains(
            'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json'));
    expect(source, contains('windows/runner/resources/app_icon.ico'));
    expect(
        source,
        contains(
            'macos/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json'));
    expect(source, contains('linux/runner/resources/app_icon.png'));
    expect(source, contains('web/icons/Icon-192.png'));
  });

  test('does not add checks for unselected platforms', () {
    final source =
        appIconTest({TargetPlatform.android, TargetPlatform.windows});

    expect(source,
        contains('android/app/src/main/res/mipmap-hdpi/ic_launcher.png'));
    expect(source, contains('windows/runner/resources/app_icon.ico'));
    expect(source, isNot(contains('web/icons/Icon-192.png')));
  });
}
