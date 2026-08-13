import 'dart:io';

import 'package:dartloom/src/build/build_target.dart';
import 'package:dartloom/src/commands/build_command.dart';
import 'package:dartloom/src/config/dartloom_config.dart';
import 'package:dartloom/src/packaging/package_target.dart';
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

  test('restores Android Gradle properties after a stable build', () async {
    final project = await Directory.systemTemp.createTemp('dartloom_gradle');
    addTearDown(() => project.delete(recursive: true));
    final properties = File(
      '${project.path}${Platform.pathSeparator}android${Platform.pathSeparator}gradle.properties',
    );
    await properties.parent.create(recursive: true);
    await properties.writeAsString('android.useAndroidX=true\n');

    await withStableAndroidKotlinBuild(project, () async {
      final duringBuild = await properties.readAsString();
      if (Platform.isWindows) {
        expect(duringBuild, contains('kotlin.incremental=false'));
      }
    });

    expect(await properties.readAsString(), 'android.useAndroidX=true\n');

    await expectLater(
      withStableAndroidKotlinBuild<void>(project, () async {
        throw StateError('build failed');
      }),
      throwsStateError,
    );
    expect(await properties.readAsString(), 'android.useAndroidX=true\n');
  });
}
