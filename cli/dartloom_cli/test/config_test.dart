import 'dart:io';

import 'package:dartloom_cli/dartloom_cli.dart';
import 'package:test/test.dart';

void main() {
  test('serializes and loads the complete configuration', () async {
    final directory =
        await Directory.systemTemp.createTemp('dartloom_config_test');
    addTearDown(() => directory.delete(recursive: true));
    final config = DartloomConfig(
      app: const AppConfig(
          name: 'demo', organization: 'com.example', description: 'Demo'),
      platforms: {TargetPlatform.android, TargetPlatform.windows},
      capabilities: {Capability.logging, Capability.storage},
    );
    final loader = const ConfigLoader();
    await loader.save(directory, config);
    final loaded = await loader.load(directory);
    expect(loaded.app.name, 'demo');
    expect(loaded.platforms, config.platforms);
    expect(loaded.capabilities, config.capabilities);
  });

  test('rejects unsupported schema version', () async {
    final directory =
        await Directory.systemTemp.createTemp('dartloom_config_test');
    addTearDown(() => directory.delete(recursive: true));
    await File('${directory.path}${Platform.pathSeparator}dartloom.yaml')
        .writeAsString('schema_version: 2');
    expect(() => const ConfigLoader().load(directory),
        throwsA(isA<ConfigException>()));
  });
}
