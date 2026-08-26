import 'dart:io';

import '../commands/command_support.dart';
import 'process_runner.dart';

/// RepoFlow is a host dependency of project creation. It remains a gh
/// extension so users can update it independently of the Dart package cache.
class RepoFlowRunner {
  const RepoFlowRunner(this.runner);

  final ProcessRunner runner;

  Future<void> init(Directory project,
      {required String name, required String visibility}) async {
    final version = await runner.run('gh', ['repoflow', 'version'],
        workingDirectory: project.path);
    if (version.exitCode != 0) {
      throw CommandFailure(
          'gh repoflow is required by dartloom new. Install it with '
          'gh extension install wkzmagician/gh-repoflow.');
    }
    if (version.stdout.isNotEmpty) stdout.write(version.stdout);
    if (version.stderr.isNotEmpty) stderr.write(version.stderr);
    await runRequired(
        runner,
        'gh',
        [
          'repoflow',
          'init',
          '--name',
          name,
          '--$visibility',
        ],
        project);
  }
}
