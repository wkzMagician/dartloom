import 'dart:io';

import 'package:dartloom_cli/src/process/process_runner.dart';
import 'package:dartloom_cli/src/process/repo_flow_runner.dart';
import 'package:test/test.dart';

class _RecordingRunner implements ProcessRunner {
  final calls = <List<String>>[];
  final results = <String, List<ProcessResultData>>{};
  bool throwWhenCheckingGh = false;

  @override
  Future<ProcessResultData> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    final call = [executable, ...arguments];
    calls.add(call);
    if (throwWhenCheckingGh && call.join(' ') == 'gh --version') {
      throw ProcessException('gh', arguments, 'executable not found');
    }
    final key = call.join(' ');
    final queued = results[key];
    if (queued == null || queued.isEmpty) {
      return const ProcessResultData(0, '', '');
    }
    return queued.removeAt(0);
  }

  @override
  Future<void> startDetached(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {}
}

void main() {
  test('passes the topic to RepoFlow init', () async {
    final runner = _RecordingRunner();
    final project = Directory.systemTemp.createTempSync('dartloom-repoflow-');
    addTearDown(() => project.deleteSync(recursive: true));

    await RepoFlowRunner(runner).init(
      project,
      name: 'my_app',
      visibility: 'public',
      topic: 'dartloom',
    );

    expect(
      runner.calls.map((call) => call.join(' ')),
      contains(
        'gh repoflow init --name my_app --public --topic dartloom',
      ),
    );
  });

  test('installs RepoFlow when the extension is missing', () async {
    final runner = _RecordingRunner();
    final project = Directory.systemTemp.createTempSync('dartloom-repoflow-');
    addTearDown(() => project.deleteSync(recursive: true));
    runner.results['gh repoflow version'] = [
      const ProcessResultData(1, '', 'not installed'),
      const ProcessResultData(0, 'gh-repoflow v0.1.5\n', ''),
    ];

    await RepoFlowRunner(runner).init(
      project,
      name: 'my_app',
      visibility: 'public',
    );

    expect(
      runner.calls.map((call) => call.join(' ')),
      contains('gh extension install wkzMagician/gh-repoflow'),
    );
  });

  test('reports a missing GitHub CLI before checking RepoFlow', () async {
    final runner = _RecordingRunner();
    runner.throwWhenCheckingGh = true;
    final project = Directory.systemTemp.createTempSync('dartloom-repoflow-');
    addTearDown(() => project.deleteSync(recursive: true));
    runner.results['gh --version'] = [
      const ProcessResultData(1, '', 'gh not found'),
    ];

    expect(
      () => RepoFlowRunner(runner).init(
        project,
        name: 'my_app',
        visibility: 'public',
      ),
      throwsA(isA<Exception>()),
    );
    expect(runner.calls, hasLength(1));
    expect(runner.calls.single, ['gh', '--version']);
  });
}
