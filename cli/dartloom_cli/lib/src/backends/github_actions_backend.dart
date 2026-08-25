import 'dart:convert';
import 'dart:io';

import '../build/build_models.dart';

class GitHubActionsBackend implements CloudBuildBackend {
  GitHubActionsBackend({
    required this.owner,
    required this.repository,
    required this.token,
    this.workflow = 'dartloom-build.yml',
  });
  final String owner, repository, token, workflow;
  final HttpClient _client = HttpClient();
  String get _base => 'https://api.github.com/repos/$owner/$repository';
  Future<HttpClientResponse> _request(
    String method,
    String url, [
    Object? body,
  ]) async {
    final request = await _client.openUrl(method, Uri.parse(url));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.set('Accept', 'application/vnd.github+json');
    request.headers.set(HttpHeaders.userAgentHeader, 'dartloom');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    if (response.statusCode >= 300) {
      throw HttpException(
        'GitHub API ${response.statusCode}: ${await response.transform(utf8.decoder).join()}',
      );
    }
    return response;
  }

  @override
  Future<String> trigger(BuildRequest request) async {
    final beforeTrigger = DateTime.now().toUtc().subtract(
          const Duration(seconds: 5),
        );
    await _request('POST', '$_base/actions/workflows/$workflow/dispatches', {
      'ref': request.workflowRef ?? request.gitRef,
      'inputs': {
        'platform': request.platform,
        'git_ref': request.gitRef,
        'mode': request.mode.name,
      },
    });

    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final response = await _request(
        'GET',
        '$_base/actions/workflows/$workflow/runs?head_sha=${request.gitRef}&event=workflow_dispatch',
      );
      final data = jsonDecode(
        await response.transform(utf8.decoder).join(),
      ) as Map<String, dynamic>;
      final runs = data['workflow_runs'] as List?;
      if (runs != null && runs.isNotEmpty) {
        final latestRun = runs.first as Map<String, dynamic>;
        final createdAtStr = latestRun['created_at'] as String?;
        final createdAt =
            createdAtStr != null ? DateTime.tryParse(createdAtStr) : null;
        if (createdAt == null || createdAt.isAfter(beforeTrigger)) {
          return latestRun['id'].toString();
        }
      }
    }
    throw StateError(
      'Timed out waiting for GitHub Actions workflow run to start.',
    );
  }

  @override
  Future<BuildStatus> status(String runId) async {
    final response = await _request('GET', '$_base/actions/runs/$runId');
    final data = jsonDecode(
      await response.transform(utf8.decoder).join(),
    ) as Map<String, dynamic>;
    if (data['status'] != 'completed') {
      return data['status'] == 'queued'
          ? BuildStatus.queued
          : BuildStatus.running;
    }
    return switch (data['conclusion']) {
      'success' => BuildStatus.succeeded,
      'cancelled' => BuildStatus.cancelled,
      _ => BuildStatus.failed,
    };
  }

  @override
  Future<List<Artifact>> artifacts(String runId) async {
    final response = await _request(
      'GET',
      '$_base/actions/runs/$runId/artifacts',
    );
    final data = jsonDecode(
      await response.transform(utf8.decoder).join(),
    ) as Map<String, dynamic>;
    return (data['artifacts'] as List)
        .map(
          (a) => Artifact(
            id: a['id'] as int,
            name: a['name'] as String,
            downloadUrl: a['archive_download_url'] as String,
            runId: runId,
          ),
        )
        .toList();
  }

  @override
  Future<void> download(Artifact artifact, Directory target) async {
    target.createSync(recursive: true);
    final archive = File(
      '${target.path}${Platform.pathSeparator}${artifact.name}.zip',
    );
    if (archive.existsSync()) {
      await archive.delete();
    }
    if (artifact.runId != null) {
      final ghDownloaded = await _downloadWithGh(artifact, target);
      if (ghDownloaded == true) {
        return;
      }
      throw StateError(
        'GitHub CLI could not download ${artifact.name} within 30 seconds.',
      );
    }

    final response = await _request('GET', artifact.downloadUrl);
    try {
      await response.pipe(archive.openWrite()).timeout(
            const Duration(minutes: 2),
          );
    } catch (_) {
      if (archive.existsSync()) {
        await archive.delete();
      }
      rethrow;
    }
  }

  Future<bool> _downloadWithGh(Artifact artifact, Directory target) async {
    try {
      final process = await Process.start('gh', [
        'run',
        'download',
        artifact.runId!,
        '--repo',
        '$owner/$repository',
        '--name',
        artifact.name,
        '--dir',
        target.path,
      ]);
      final stdoutDone = process.stdout.drain<void>();
      final stderrDone = process.stderr.drain<void>();
      var timedOut = false;
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          timedOut = true;
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      if (!timedOut) {
        await Future.wait([stdoutDone, stderrDone]);
      }
      if (exitCode == 0) {
        return true;
      }
      stderr.writeln(
        'gh run download failed.',
      );
    } on ProcessException {
      // GitHub CLI is optional when GITHUB_TOKEN is supplied.
      return false;
    }
    return false;
  }

  @override
  String runUrl(String runId) =>
      'https://github.com/$owner/$repository/actions/runs/$runId';
}
