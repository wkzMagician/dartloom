import 'dart:io';

import 'package:dartloom_cli/src/commands/add_command.dart';
import 'package:dartloom_cli/src/commands/doctor_command.dart';
import 'package:dartloom_cli/src/commands/new_command.dart';
import 'package:dartloom_cli/src/config/config_loader.dart';
import 'package:dartloom_cli/src/config/dartloom_config.dart';
import 'package:dartloom_cli/src/process/process_runner.dart';
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
      capabilities: {Capability.settings},
    );
    expect(
        await File('${project.path}${Platform.pathSeparator}dartloom.yaml')
            .exists(),
        isTrue);
    expect(
        await File('${project.path}${Platform.pathSeparator}AGENTS.md')
            .exists(),
        isTrue);
    expect(
        await File('${project.path}${Platform.pathSeparator}pubspec.yaml')
            .readAsString(),
        contains('dartloom_settings:'));
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
          capabilities: {Capability.autostart},
        ));
    final runner = FakeRunner();
    await AddCommand(runner).run(project, 'autostart');
    expect(runner.calls, isEmpty);
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
