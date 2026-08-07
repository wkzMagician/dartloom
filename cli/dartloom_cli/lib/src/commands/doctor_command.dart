import 'dart:io';

import '../config/config_loader.dart';
import '../process/process_runner.dart';
import 'command_support.dart';

class DoctorCommand {
  DoctorCommand(this.runner, {ConfigLoader? loader})
      : _loader = loader ?? const ConfigLoader();
  final ProcessRunner runner;
  final ConfigLoader _loader;

  Future<bool> run(Directory project) async {
    stdout.writeln('Dartloom Doctor\n');
    var healthy = true;
    Future<void> check(String label, String executable, List<String> args,
        {String? advice}) async {
      final result =
          await runner.run(executable, args, workingDirectory: project.path);
      final ok = result.exitCode == 0;
      healthy &= ok;
      stdout.writeln(
          '${label.padRight(20)} ${ok ? 'OK' : 'MISSING'}${ok ? '' : '  ${advice ?? ''}'}');
    }

    await check('Flutter', executableFor('flutter'), ['--version'],
        advice: 'Install Flutter and add it to PATH.');
    await check('Dart', executableFor('dart'), ['--version'],
        advice: 'Install Dart or Flutter.');
    await check('Git', 'git', ['--version'], advice: 'Install Git.');
    await check('GitHub CLI', 'gh', ['--version'],
        advice: 'Install GitHub CLI for releases.');
    final configExists =
        await File('${project.path}${Platform.pathSeparator}dartloom.yaml')
            .exists();
    final pubspecExists =
        await File('${project.path}${Platform.pathSeparator}pubspec.yaml')
            .exists();
    final git = await Directory('${project.path}${Platform.pathSeparator}.git')
        .exists();
    for (final entry in [
      ('dartloom.yaml', configExists),
      ('pubspec.yaml', pubspecExists),
      ('Git repository', git)
    ]) {
      healthy &= entry.$2;
      stdout.writeln('${entry.$1.padRight(20)} ${entry.$2 ? 'OK' : 'MISSING'}');
    }
    if (configExists) {
      try {
        await _loader.load(project);
      } on Object catch (error) {
        healthy = false;
        stdout.writeln('Configuration         INVALID  $error');
      }
    }
    return healthy;
  }
}
