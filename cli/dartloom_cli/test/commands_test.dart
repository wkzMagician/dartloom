import 'dart:io';

import 'package:dartloom/src/commands/add_command.dart';
import 'package:dartloom/src/commands/capability_manager.dart';
import 'package:dartloom/src/commands/command_support.dart';
import 'package:dartloom/src/commands/doctor_command.dart';
import 'package:dartloom/src/commands/new_command.dart';
import 'package:dartloom/src/commands/remove_command.dart';
import 'package:dartloom/src/commands/self_upgrade_command.dart';
import 'package:dartloom/src/commands/upgrade_command.dart';
import 'package:dartloom/src/config/config_loader.dart';
import 'package:dartloom/src/config/dartloom_config.dart';
import 'package:dartloom/src/process/process_runner.dart';
import 'package:dartloom/src/templates/managed_templates.dart';
import 'package:test/test.dart';

class FakeRunner implements ProcessRunner {
  final calls = <String>[];

  @override
  Future<ProcessResultData> run(String executable, List<String> arguments,
      {required String workingDirectory}) async {
    calls.add('$executable ${arguments.join(' ')}');
    if (arguments.isNotEmpty && arguments.first == 'create') {
      final project = Directory(
          '$workingDirectory${Platform.pathSeparator}${arguments.last}');
      await project.create();
      await Directory('${project.path}${Platform.pathSeparator}test').create();
      await File('${project.path}${Platform.pathSeparator}pubspec.yaml')
          .writeAsString(
              'name: ${arguments.last}\r\ndependencies:\r\n  flutter:\r\n    sdk: flutter\r\n');
    }
    return const ProcessResultData(0, '', '');
  }

  @override
  Future<void> startDetached(String executable, List<String> arguments,
      {required String workingDirectory}) async {
    calls.add('$executable ${arguments.join(' ')}');
  }
}

void main() {
  test('new writes managed files and local capability dependencies', () async {
    final root = Directory.current.parent.parent;
    final name = 'dartloom_test_${DateTime.now().microsecondsSinceEpoch}';
    final project = Directory('${root.path}${Platform.pathSeparator}$name');
    addTearDown(() => project.delete(recursive: true));
    final runner = FakeRunner();
    await NewCommand(runner).run(
      parent: root,
      name: name,
      organization: 'com.example',
      platforms: {TargetPlatform.windows},
      capabilities: {Capability.settings, Capability.localization},
    );
    expect(
        await File('${project.path}${Platform.pathSeparator}dartloom.yaml')
            .exists(),
        isTrue);
    expect(
        await File('${project.path}${Platform.pathSeparator}AGENTS.md')
            .exists(),
        isTrue);
    final generatedPubspec =
        await File('${project.path}${Platform.pathSeparator}pubspec.yaml')
            .readAsString();
    expect(generatedPubspec, contains('dartloom_settings:'));
    expect(generatedPubspec, contains('dartloom_localization:'));
    expect(
      await File(
        '${project.path}${Platform.pathSeparator}lib${Platform.pathSeparator}capabilities${Platform.pathSeparator}capabilities.dart',
      ).readAsString(),
      contains('GenL10nLocalizationService'),
    );
    expect(
      await File(
        '${project.path}${Platform.pathSeparator}lib${Platform.pathSeparator}app${Platform.pathSeparator}app.dart',
      ).readAsString(),
      contains('localizationsDelegates: dartloomLocalizationsDelegates'),
    );
  });

  test('adding an already enabled capability is idempotent', () async {
    final project = await Directory.systemTemp.createTemp('dartloom_add_test');
    addTearDown(() => project.delete(recursive: true));
    final loader = const ConfigLoader();
    await loader.save(
        project,
        DartloomConfig(
          app: const AppConfig(
              name: 'demo', organization: 'com.example', description: ''),
          platforms: {TargetPlatform.windows},
          capabilities: _caps({Capability.autostart}),
        ));
    final runner = FakeRunner();
    await AddCommand(runner).run(project, 'autostart');
    expect(runner.calls, isEmpty);
  });

  test('removing a capability updates config, dependencies, and glue',
      () async {
    final project =
        await Directory.systemTemp.createTemp('dartloom_remove_test');
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
        capabilities: _caps({Capability.autostart}),
      ),
    );
    await File('${project.path}${Platform.pathSeparator}pubspec.yaml')
        .writeAsString(
      'name: demo\ndependencies:\n  dartloom_autostart:\n    path: ../dartloom_autostart\n  flutter:\n    sdk: flutter\n',
    );
    await Directory(
            '${project.path}${Platform.pathSeparator}lib${Platform.pathSeparator}capabilities')
        .create(recursive: true);
    final runner = FakeRunner();
    await RemoveCommand(runner).run(project, 'autostart');
    expect((await loader.load(project)).capabilities, isEmpty);
    expect(
        await File('${project.path}${Platform.pathSeparator}pubspec.yaml')
            .readAsString(),
        isNot(contains('dartloom_autostart')));
  });

  test('capability manager applies multiple changes in one check cycle',
      () async {
    final project =
        await Directory.systemTemp.createTemp('dartloom_batch_test');
    addTearDown(() => project.delete(recursive: true));
    final loader = const ConfigLoader();
    await loader.save(
      project,
      DartloomConfig(
        app: const AppConfig(
            name: 'demo', organization: 'com.example', description: ''),
        platforms: {TargetPlatform.windows},
        capabilities: _caps({Capability.settings, Capability.storage}),
      ),
    );
    await File('${project.path}${Platform.pathSeparator}pubspec.yaml')
        .writeAsString(
      'name: demo\ndependencies:\n  dartloom_settings:\n    path: ../dartloom_settings\n  dartloom_storage:\n    path: ../dartloom_storage\n  flutter:\n    sdk: flutter\n',
    );
    await Directory(
            '${project.path}${Platform.pathSeparator}lib${Platform.pathSeparator}capabilities')
        .create(recursive: true);
    final runner = FakeRunner();
    final change = await CapabilityManager(runner).apply(
      project,
      _caps({Capability.storage, Capability.logging}),
    );
    expect(change.added, {'logging.default'});
    expect(change.removed, {'settings.default'});
    expect(runner.calls.length, 5);
    final pubspec =
        await File('${project.path}${Platform.pathSeparator}pubspec.yaml')
            .readAsString();
    expect(pubspec, contains('dartloom_logging'));
    expect(pubspec, isNot(contains('dartloom_settings')));
  });

  test('upgrade refreshes capability glue without replacing application files',
      () async {
    final project =
        await Directory.systemTemp.createTemp('dartloom_upgrade_test');
    addTearDown(() => project.delete(recursive: true));
    final loader = const ConfigLoader();
    await loader.save(
      project,
      DartloomConfig(
        app: const AppConfig(
            name: 'demo', organization: 'com.example', description: ''),
        platforms: {TargetPlatform.windows},
        capabilities: _caps({Capability.settings}),
      ),
    );
    await File('${project.path}${Platform.pathSeparator}pubspec.yaml')
        .writeAsString('name: demo\ndependencies:\n');
    final app = File(
      '${project.path}${Platform.pathSeparator}lib${Platform.pathSeparator}app${Platform.pathSeparator}app.dart',
    );
    await app.parent.create(recursive: true);
    await app.writeAsString('const application = "keep";');
    final legacyBootstrap = File(
      '${project.path}${Platform.pathSeparator}lib${Platform.pathSeparator}app${Platform.pathSeparator}bootstrap.dart',
    );
    await legacyBootstrap.writeAsString('Future<void> bootstrap() async {}');
    final agents = File('${project.path}${Platform.pathSeparator}AGENTS.md');
    await agents.writeAsString('outdated');
    final feature = File(
        '${project.path}${Platform.pathSeparator}lib${Platform.pathSeparator}features${Platform.pathSeparator}note.dart');
    await feature.parent.create(recursive: true);
    await feature.writeAsString('const note = "keep";');
    final runner = FakeRunner();
    await UpgradeCommand(runner).run(
      project,
      dryRun: false,
    );
    expect(await agents.readAsString(),
        contains('This project is managed by Dartloom.'));
    expect(await feature.readAsString(), 'const note = "keep";');
    expect(await app.readAsString(), 'const application = "keep";');
    expect(
      await legacyBootstrap.readAsString(),
      'Future<void> bootstrap() async {}',
    );
    expect(
      runner.calls,
      contains('flutter.bat --no-version-check pub upgrade'),
    );
    expect(runner.calls.length, 5);
  });

  test('upgrade dry run does not change files', () async {
    final project =
        await Directory.systemTemp.createTemp('dartloom_upgrade_dry_test');
    addTearDown(() => project.delete(recursive: true));
    await const ConfigLoader().save(
      project,
      DartloomConfig(
        app: const AppConfig(
            name: 'demo', organization: 'com.example', description: ''),
        platforms: {TargetPlatform.windows},
        capabilities: {},
      ),
    );
    final agents = File('${project.path}${Platform.pathSeparator}AGENTS.md');
    await agents.writeAsString('keep');
    final runner = FakeRunner();
    await UpgradeCommand(runner).run(
      project,
      dryRun: true,
    );
    expect(await agents.readAsString(), 'keep');
    expect(runner.calls, isEmpty);
  });

  test('upgrade preserves existing localization configuration and ARB files',
      () async {
    final project =
        await Directory.systemTemp.createTemp('dartloom_upgrade_l10n_test');
    addTearDown(() => project.delete(recursive: true));
    await const ConfigLoader().save(
      project,
      DartloomConfig(
        app: const AppConfig(
            name: 'demo', organization: 'com.example', description: ''),
        platforms: {TargetPlatform.windows},
        capabilities: _caps({Capability.localization}),
      ),
    );
    await File('${project.path}${Platform.pathSeparator}pubspec.yaml')
        .writeAsString('name: demo\ndependencies:\n');
    final arb = File(
      '${project.path}${Platform.pathSeparator}lib${Platform.pathSeparator}l10n${Platform.pathSeparator}app_en.arb',
    );
    await arb.parent.create(recursive: true);
    await arb.writeAsString('{"appTitle":"Mini Todo"}');
    await File('${project.path}${Platform.pathSeparator}l10n.yaml')
        .writeAsString('arb-dir: custom_l10n');

    await UpgradeCommand(FakeRunner()).run(project, dryRun: false);

    expect(await arb.readAsString(), '{"appTitle":"Mini Todo"}');
    expect(
      await File('${project.path}${Platform.pathSeparator}l10n.yaml')
          .readAsString(),
      'arb-dir: custom_l10n',
    );
  });

  test('generated registrations skip resident adapters on unsupported targets',
      () {
    final config = DartloomConfig(
      app: const AppConfig(
          name: 'demo', organization: 'com.example', description: ''),
      platforms: {TargetPlatform.android, TargetPlatform.windows},
      capabilities: _caps({Capability.resident}),
    );
    final glue = capabilityGlue(config);
    expect(glue, contains('_dartloomSupportsCurrentPlatform'));
    expect(
      glue,
      contains('const {"windows", "macos", "linux"}'),
    );
    expect(glue, contains('TrayResidentService'));
  });

  test('self-upgrade schedules a detached install', () async {
    final runner = FakeRunner();
    await SelfUpgradeCommand(runner).run(Directory.current);
    expect(runner.calls.single, contains('dart install --overwrite dartloom'));
  });

  test('published capability dependencies use hosted versions by default', () {
    final config = DartloomConfig(
      app: const AppConfig(
          name: 'demo', organization: 'dev.test', description: ''),
      platforms: {TargetPlatform.windows},
      capabilities: _caps({Capability.settings}),
      capabilitySource: CapabilitySource.pub,
    );
    final value = rewriteDartloomDependencies('dependencies:\n', config);
    expect(value, contains('dartloom_settings: ^0.2.0'));
    expect(value, isNot(contains('dependency_overrides:')));
  });

  test('switching source rewrites enabled capability dependencies', () async {
    final project =
        await Directory.systemTemp.createTemp('dartloom_source_switch_test');
    addTearDown(() => project.delete(recursive: true));
    final loader = const ConfigLoader();
    await loader.save(
      project,
      DartloomConfig(
        app: const AppConfig(
            name: 'demo', organization: 'com.example', description: ''),
        platforms: {TargetPlatform.windows},
        capabilities: _caps({Capability.localization}),
        capabilitySource: CapabilitySource.pub,
      ),
    );
    await File('${project.path}${Platform.pathSeparator}pubspec.yaml')
        .writeAsString(
      'name: demo\ndependencies:\n  dartloom_localization: ^0.1.0\n  flutter:\n    sdk: flutter\n',
    );
    final runner = FakeRunner();
    await CapabilityManager(runner).setSource(
      project,
      CapabilitySource.github,
    );
    final pubspec =
        await File('${project.path}${Platform.pathSeparator}pubspec.yaml')
            .readAsString();
    expect(
        pubspec, contains('url: https://github.com/wkzMagician/dartloom.git'));
    expect(pubspec, contains('ref: main'));
    expect(pubspec, isNot(contains('dartloom_localization: ^0.1.0')));
    expect(
        (await loader.load(project)).capabilitySource, CapabilitySource.github);
  });

  test('doctor succeeds when required checks are available', () async {
    final project =
        await Directory.systemTemp.createTemp('dartloom_doctor_test');
    addTearDown(() => project.delete(recursive: true));
    await Directory('${project.path}${Platform.pathSeparator}.git').create();
    await File('${project.path}${Platform.pathSeparator}pubspec.yaml')
        .writeAsString('name: demo');
    await const ConfigLoader().save(
        project,
        DartloomConfig(
          app: const AppConfig(
              name: 'demo', organization: 'com.example', description: ''),
          platforms: {TargetPlatform.windows},
          capabilities: {},
        ));
    expect(await DoctorCommand(FakeRunner()).run(project), isTrue);
  });
}

Map<Capability, Map<String, CapabilityInstanceConfig>> _caps(
  Set<Capability> values,
) =>
    {
      for (final value in values)
        value: {...CapabilityDefaults.forCapability(value)},
    };
