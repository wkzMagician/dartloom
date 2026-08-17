import 'dart:io';

class GitRepository {
  const GitRepository(this.directory);
  final Directory directory;

  Future<void> ensureClean() async {
    final result = await Process.run('git', ['status', '--porcelain'],
        workingDirectory: directory.path);
    if (result.exitCode != 0) throw StateError('Not a Git repository.');
    if ((result.stdout as String).trim().isNotEmpty) {
      throw StateError(
          'Working tree contains uncommitted changes. Commit or stash them before cloud build.');
    }
  }

  Future<String> head() async {
    final result = await Process.run('git', ['rev-parse', 'HEAD'],
        workingDirectory: directory.path);
    if (result.exitCode != 0)
      throw StateError('Unable to resolve current commit.');
    return (result.stdout as String).trim();
  }

  Future<String> branch() async {
    final result = await Process.run('git', ['branch', '--show-current'],
        workingDirectory: directory.path);
    if (result.exitCode != 0 || (result.stdout as String).trim().isEmpty) {
      throw StateError('Unable to resolve current Git branch.');
    }
    return (result.stdout as String).trim();
  }
}
