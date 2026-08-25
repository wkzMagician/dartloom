import 'dart:io';

import 'package:archive/archive.dart';

import '../backends/github_actions_backend.dart';
import '../build/build_models.dart';
import '../build/git_repository.dart';

class BuildCommand {
  BuildCommand({CloudBuildBackend? backend, GitRepository? repository})
    : _backend = backend,
      _repository = repository;
  final CloudBuildBackend? _backend;
  final GitRepository? _repository;

  Future<void> run(
    String platform, {
    bool all = false,
    BuildMode mode = BuildMode.release,
  }) async {
    final workflow = File(
      '${Directory.current.path}${Platform.pathSeparator}.github${Platform.pathSeparator}workflows${Platform.pathSeparator}dartloom-build.yml',
    );
    if (!await workflow.exists()) {
      throw StateError(
        'Dartloom build workflow not found. Run `dartloom update` to add it.',
      );
    }
    final repo = _repository ?? GitRepository(Directory.current);
    await repo.ensureClean();
    final ref = await repo.head();
    final workflowRef = await repo.branch();
    final backend = _backend ?? await _defaultBackend();
    final platforms = all
        ? BuildPlatform.values
        : [BuildPlatform.parse(platform)];
    for (final platform in platforms) {
      final result = await _build(
        backend,
        repo,
        platform,
        ref,
        workflowRef,
        mode,
      );
      stdout.writeln('✓ ${result.platform} build completed');
      final target = Directory(
        '${Directory.current.path}${Platform.pathSeparator}dist${Platform.pathSeparator}${result.platform}',
      );
      for (final artifact in result.artifacts) {
        await backend.download(artifact, target);
        final zipPath =
            '${target.path}${Platform.pathSeparator}${artifact.name}.zip';
        final zipFile = File(zipPath);
        if (zipFile.existsSync()) {
          stdout.writeln('→ $zipPath');
          _extractArchive(zipFile, target);
        } else {
          stdout.writeln('→ downloaded ${artifact.name} to ${target.path}');
        }
      }
    }
  }

  void _extractArchive(File zipFile, Directory target) {
    if (!zipFile.existsSync()) return;
    try {
      final bytes = zipFile.readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        if (file.isFile) {
          final outFile = File(
            '${target.path}${Platform.pathSeparator}${file.name}',
          );
          outFile.parent.createSync(recursive: true);
          outFile.writeAsBytesSync(file.content as List<int>);
          stdout.writeln('  ↳ extracted ${file.name}');
        }
      }
    } catch (_) {
      // Keep zip intact if extraction fails
    }
  }

  Future<BuildResult> _build(
    CloudBuildBackend backend,
    GitRepository repo,
    String platform,
    String ref,
    String workflowRef,
    BuildMode mode,
  ) async {
    stdout.writeln('→ Triggering $platform build');
    final runId = await backend.trigger(
      BuildRequest(
        platform: platform,
        gitRef: ref,
        workflowRef: workflowRef,
        mode: mode,
      ),
    );
    var status = BuildStatus.queued;
    while (status == BuildStatus.queued || status == BuildStatus.running) {
      await Future<void>.delayed(const Duration(seconds: 2));
      status = await backend.status(runId);
    }
    if (status != BuildStatus.succeeded) {
      throw StateError(
        'Build $status. GitHub Actions: ${backend.runUrl(runId)}',
      );
    }
    return BuildResult(
      runId: runId,
      platform: platform,
      artifacts: await backend.artifacts(runId),
    );
  }

  Future<CloudBuildBackend> _defaultBackend() async {
    final token =
        await _tryGhValue(['auth', 'token']) ??
        Platform.environment['GITHUB_TOKEN'];
    final repository =
        await _tryGhValue([
          'repo',
          'view',
          '--json',
          'nameWithOwner',
          '--jq',
          '.nameWithOwner',
        ]) ??
        Platform.environment['GITHUB_REPOSITORY'];
    if (token == null || repository == null || !repository.contains('/')) {
      throw StateError(
        'Unable to resolve GitHub credentials or repository. Ensure gh is available, or set GITHUB_TOKEN and GITHUB_REPOSITORY=owner/name.',
      );
    }
    final parts = repository.split('/');
    return GitHubActionsBackend(
      owner: parts[0],
      repository: parts[1],
      token: token,
    );
  }

  Future<String?> _tryGhValue(List<String> arguments) async {
    final result = await Process.run(
      'gh',
      arguments,
      workingDirectory: Directory.current.path,
    );
    if (result.exitCode != 0 || (result.stdout as String).trim().isEmpty) {
      return null;
    }
    return (result.stdout as String).trim();
  }
}
