import 'dart:io';

import 'command_support.dart';

class ReleaseCommand {
  const ReleaseCommand();

  Future<void> run(Directory project, {String? version}) async {
    final workflow = File(
        '${project.path}${Platform.pathSeparator}.github${Platform.pathSeparator}workflows${Platform.pathSeparator}release.yml');
    if (!await workflow.exists()) {
      throw CommandFailure(
          'Dartloom release workflow not found. Run `dartloom update` to add it.');
    }
    final status = await Process.run('git', ['status', '--porcelain'],
        workingDirectory: project.path);
    if ((status.stdout as String).trim().isNotEmpty) {
      throw CommandFailure(
          'Working tree contains uncommitted changes. Commit or stash them before release.');
    }
    final file = File('${project.path}${Platform.pathSeparator}pubspec.yaml');
    final source = await file.readAsString();
    final current = RegExp(r'^version:\s*([^\s]+)', multiLine: true)
        .firstMatch(source)
        ?.group(1);
    final next = version ?? current;
    if (next == null ||
        !RegExp(r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$')
            .hasMatch(next)) {
      throw CommandFailure(
          'Invalid or missing version. Expected SemVer such as 1.4.0.');
    }
    final tag = 'v$next';
    final tagCheck = await Process.run(
        'git', ['rev-parse', '--verify', 'refs/tags/$tag'],
        workingDirectory: project.path);
    if (tagCheck.exitCode == 0) {
      throw CommandFailure('Git tag already exists: $tag');
    }
    final updated = source.replaceFirst(
        RegExp(r'^version:\s*[^\r\n]+', multiLine: true), 'version: $next');
    if (updated == source) {
      throw CommandFailure('No version field found in pubspec.yaml.');
    }
    await file.writeAsString(updated);
    await _git(project, ['add', 'pubspec.yaml']);
    await _git(project, ['commit', '-m', 'chore: release $next']);
    await _git(project, ['tag', '-a', tag, '-m', 'Release $next']);
    await _git(project, ['push', 'origin', 'HEAD']);
    await _git(project, ['push', 'origin', tag]);
    stdout.writeln(
        '✓ Release $next pushed; release.yml will build and publish it.');
  }

  Future<void> _git(Directory project, List<String> args) async {
    final result =
        await Process.run('git', args, workingDirectory: project.path);
    if (result.exitCode != 0) {
      throw CommandFailure('git ${args.join(' ')} failed: ${result.stderr}');
    }
  }
}
