import 'dart:io';
import '../backends/github_actions_backend.dart';
import '../build/build_models.dart';
import '../build/git_repository.dart';

class BuildCommand {
  BuildCommand({CloudBuildBackend? backend, GitRepository? repository})
      : _backend = backend,
        _repository = repository;
  final CloudBuildBackend? _backend;
  final GitRepository? _repository;

  Future<void> run(String platform,
      {bool all = false, BuildMode mode = BuildMode.release}) async {
    final workflow = File(
        '${Directory.current.path}${Platform.pathSeparator}.github${Platform.pathSeparator}workflows${Platform.pathSeparator}dartloom-build.yml');
    if (!await workflow.exists()) {
      throw StateError(
          'Dartloom build workflow not found. Run `dartloom update` to add it.');
    }
    final repo = _repository ?? GitRepository(Directory.current);
    await repo.ensureClean();
    final ref = await repo.head();
    final backend = _backend ?? _defaultBackend();
    final platforms =
        all ? BuildPlatform.values : [BuildPlatform.parse(platform)];
    final results = await Future.wait(
        platforms.map((p) => _build(backend, repo, p, ref, mode)));
    for (final result in results) {
      stdout.writeln('✓ ${result.platform} build completed');
      final target = Directory(
          '${Directory.current.path}${Platform.pathSeparator}dist${Platform.pathSeparator}${result.platform}');
      for (final artifact in result.artifacts) {
        await backend.download(artifact, target);
        stdout.writeln(
            '→ ${target.path}${Platform.pathSeparator}${artifact.name}.zip');
      }
    }
  }

  Future<BuildResult> _build(CloudBuildBackend backend, GitRepository repo,
      String platform, String ref, BuildMode mode) async {
    stdout.writeln('→ Triggering $platform build');
    final runId = await backend
        .trigger(BuildRequest(platform: platform, gitRef: ref, mode: mode));
    var status = BuildStatus.queued;
    while (status == BuildStatus.queued || status == BuildStatus.running) {
      await Future<void>.delayed(const Duration(seconds: 2));
      status = await backend.status(runId);
    }
    if (status != BuildStatus.succeeded)
      throw StateError(
          'Build $status. GitHub Actions: ${backend.runUrl(runId)}');
    return BuildResult(
        runId: runId,
        platform: platform,
        artifacts: await backend.artifacts(runId));
  }

  CloudBuildBackend _defaultBackend() {
    final token = Platform.environment['GITHUB_TOKEN'];
    final repository = Platform.environment['GITHUB_REPOSITORY'];
    if (token == null || repository == null || !repository.contains('/'))
      throw StateError('Set GITHUB_TOKEN and GITHUB_REPOSITORY (owner/name).');
    final parts = repository.split('/');
    return GitHubActionsBackend(
        owner: parts[0], repository: parts[1], token: token);
  }
}
