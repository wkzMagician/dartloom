import 'dart:io';

class ProcessResultData {
  const ProcessResultData(this.exitCode, this.stdout, this.stderr);
  final int exitCode;
  final String stdout;
  final String stderr;
}

abstract interface class ProcessRunner {
  Future<ProcessResultData> run(String executable, List<String> arguments,
      {required String workingDirectory});

  Future<void> startDetached(String executable, List<String> arguments,
      {required String workingDirectory});
}

class SystemProcessRunner implements ProcessRunner {
  const SystemProcessRunner();
  @override
  Future<ProcessResultData> run(String executable, List<String> arguments,
      {required String workingDirectory}) async {
    final result = await Process.run(executable, arguments,
        workingDirectory: workingDirectory, runInShell: Platform.isWindows);
    return ProcessResultData(
        result.exitCode, '${result.stdout}', '${result.stderr}');
  }

  @override
  Future<void> startDetached(String executable, List<String> arguments,
      {required String workingDirectory}) async {
    await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: Platform.isWindows,
      mode: ProcessStartMode.detached,
    );
  }
}
