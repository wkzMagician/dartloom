import 'dart:io';

import 'package:dartloom/src/commands/command_support.dart';
import 'package:dartloom/src/commands/set_command.dart';
import 'package:dartloom/src/config/config_loader.dart';
import 'package:dartloom/src/config/dartloom_config.dart';
import 'package:test/test.dart';

void main() {
  test('set platforms validates and persists the selected targets', () async {
    final project = await Directory.systemTemp.createTemp('dartloom_set_test');
    addTearDown(() => project.delete(recursive: true));
    final loader = const ConfigLoader();
    await loader.save(
      project,
      DartloomConfig(
        app: const AppConfig(
          name: 'demo',
          organization: 'com.example',
          description: '',
        ),
        platforms: {TargetPlatform.windows},
        capabilities: const {},
      ),
    );

    await const SetCommand().run(project, 'platforms', 'macos,ios,web');
    expect((await loader.load(project)).platforms, {
      TargetPlatform.macos,
      TargetPlatform.ios,
      TargetPlatform.web,
    });
  });

  test('set platforms rejects unknown targets', () async {
    final project = await Directory.systemTemp.createTemp('dartloom_set_test');
    addTearDown(() => project.delete(recursive: true));
    final loader = const ConfigLoader();
    await loader.save(
      project,
      DartloomConfig(
        app: const AppConfig(
          name: 'demo',
          organization: 'com.example',
          description: '',
        ),
        platforms: {TargetPlatform.windows},
        capabilities: const {},
      ),
    );
    expect(
      () => const SetCommand().run(project, 'platforms', 'windows,playstation'),
      throwsA(isA<CommandFailure>()),
    );
  });
}
