import 'dart:io';

import '../process/process_runner.dart';
import 'check_command.dart';
import 'command_support.dart';

class ReleaseCommand {
  const ReleaseCommand(this.runner);
  final ProcessRunner runner;

  Future<void> run(Directory project, String version) async {
    if (!RegExp(r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$').hasMatch(version)) {
      throw CommandFailure(
          'Invalid version "$version". Use semantic versioning such as 0.1.0.');
    }
    final status = await runner.run('git', ['status', '--porcelain'],
        workingDirectory: project.path);
    if (status.exitCode != 0) {
      throw CommandFailure('This is not a usable Git repository.');
    }
    if (status.stdout.trim().isNotEmpty) {
      throw CommandFailure('Git working tree must be clean before release.');
    }
    await CheckCommand(runner).run(project);
    final pubspec =
        File('${project.path}${Platform.pathSeparator}pubspec.yaml');
    final original = await pubspec.readAsString();
    final updated = original.replaceFirst(
        RegExp(r'^version:\s*.*$', multiLine: true), 'version: $version');
    if (updated == original) {
      throw CommandFailure('pubspec.yaml does not contain a version field.');
    }
    await pubspec.writeAsString(updated);
    try {
      await runRequired(runner, 'git', ['add', 'pubspec.yaml'], project);
      await runRequired(
          runner, 'git', ['commit', '-m', 'chore: release $version'], project);
      await runRequired(runner, 'git', ['tag', 'v$version'], project);
      await runRequired(runner, 'git', ['push'], project);
      await runRequired(
          runner, 'git', ['push', 'origin', 'v$version'], project);
    } on Object {
      await pubspec.writeAsString(original);
      rethrow;
    }
  }
}
