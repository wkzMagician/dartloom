import 'dart:io';

import '../commands/command_support.dart';
import 'process_runner.dart';

/// RepoFlow is a host dependency for project creation. It remains a gh
/// extension so users can update it independently of Dart package caches.
class RepoFlowRunner {
  const RepoFlowRunner(this.runner);

  final ProcessRunner runner;

  Future<void> init(
    Directory project, {
    required String name,
    required String visibility,
    String? topic,
  }) async {
    late final ProcessResultData gh;
    try {
      gh = await runner.run(
        'gh',
        ['--version'],
        workingDirectory: project.path,
      );
    } on ProcessException {
      throw CommandFailure(
        'GitHub CLI (gh) is required. Install it and run `gh auth login`.',
      );
    }
    if (gh.exitCode != 0) {
      throw CommandFailure(
        'GitHub CLI (gh) is required. Install it and run `gh auth login`.',
      );
    }

    var version = await runner.run(
      'gh',
      ['repoflow', 'version'],
      workingDirectory: project.path,
    );
    if (version.exitCode != 0) {
      stdout.writeln('RepoFlow not found. Installing...');
      await runRequired(
        runner,
        'gh',
        ['extension', 'install', 'wkzMagician/gh-repoflow'],
        project,
      );
      version = await runner.run(
        'gh',
        ['repoflow', 'version'],
        workingDirectory: project.path,
      );
      if (version.exitCode != 0) {
        throw CommandFailure(
          'RepoFlow installation completed but `gh repoflow version` failed.',
        );
      }
    }
    if (version.stdout.isNotEmpty) stdout.write(version.stdout);
    if (version.stderr.isNotEmpty) stderr.write(version.stderr);

    final arguments = <String>[
      'repoflow',
      'init',
      '--name',
      name,
      '--$visibility',
    ];
    if (topic != null && topic.trim().isNotEmpty) {
      arguments
        ..add('--topic')
        ..add(topic.trim());
    }
    await runRequired(runner, 'gh', arguments, project);
  }
}
