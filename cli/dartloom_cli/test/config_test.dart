import 'dart:io';

import 'package:dartloom/dartloom.dart';
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
      capabilities: _caps({Capability.logging, Capability.storage}),
      capabilitySource: CapabilitySource.pub,
    );
    final loader = const ConfigLoader();
    await loader.save(directory, config);
    final loaded = await loader.load(directory);
    expect(loaded.app.name, 'demo');
    expect(loaded.platforms, config.platforms);
    expect(loaded.capabilities, config.capabilities);
    expect(loaded.capabilitySource, CapabilitySource.pub);
  });

  test('rejects unsupported schema version', () async {
    final directory =
        await Directory.systemTemp.createTemp('dartloom_config_test');
    addTearDown(() => directory.delete(recursive: true));
    await File('${directory.path}${Platform.pathSeparator}dartloom.yaml')
        .writeAsString('schema_version: 3');
    expect(() => const ConfigLoader().load(directory),
        throwsA(isA<ConfigException>()));
  });

  test('migrates schema 1 defaults once for project update', () async {
    final directory = await Directory.systemTemp.createTemp('dartloom_v1_test');
    addTearDown(() => directory.delete(recursive: true));
    await File('${directory.path}${Platform.pathSeparator}dartloom.yaml')
        .writeAsString('''schema_version: 1
app:
  name: demo
  organization: com.example
platforms:
  windows: true
capabilities:
  settings: true
  storage: true
  logging: true
  autostart: false
  sync: false
  localization: false
  resident: false
''');
    final loader = const ConfigLoader();
    expect(() => loader.load(directory), throwsA(isA<ConfigException>()));
    final migrated = await loader.loadForMigration(directory);
    expect(
      migrated.capabilities[Capability.storage]!['json']!.implementation,
      'json_file',
    );
  });

  test('preserves nested adapter options such as resident menus', () async {
    final directory =
        await Directory.systemTemp.createTemp('dartloom_nested_options_test');
    addTearDown(() => directory.delete(recursive: true));
    final config = DartloomConfig(
      app: const AppConfig(
        name: 'demo',
        organization: 'com.example',
        description: '',
      ),
      platforms: {TargetPlatform.android, TargetPlatform.windows},
      capabilities: {
        Capability.resident: {
          'default': const CapabilityInstanceConfig(
            implementation: 'tray',
            options: {
              'icon_path': r'${RESIDENT_ICON_PATH}',
              'menu': [
                {'id': 'quit', 'label': 'Quit completely'},
                {'separator': true},
              ],
              'left_click': 'menu',
            },
          ),
        },
      },
    );

    const loader = ConfigLoader();
    await loader.save(directory, config);
    final loaded = await loader.load(directory);

    expect(loaded.capabilities, config.capabilities);
  });

  test('rejects unknown implementations and unsupported platforms', () async {
    final directory =
        await Directory.systemTemp.createTemp('dartloom_bad_test');
    addTearDown(() => directory.delete(recursive: true));
    await File('${directory.path}${Platform.pathSeparator}dartloom.yaml')
        .writeAsString('''schema_version: 2
app:
  name: demo
  organization: com.example
platforms:
  web: true
capabilities:
  resident:
    instances:
      default:
        implementation: missing
''');
    expect(
      () => const ConfigLoader().load(directory),
      throwsA(isA<ConfigException>()),
    );
  });
}

Map<Capability, Map<String, CapabilityInstanceConfig>> _caps(
  Set<Capability> values,
) =>
    {
      for (final value in values)
        value: {...CapabilityDefaults.forCapability(value)},
    };
