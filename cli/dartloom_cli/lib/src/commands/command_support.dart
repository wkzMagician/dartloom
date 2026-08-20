import 'dart:io';

import '../process/process_runner.dart';

class CommandFailure implements Exception {
  CommandFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<void> runRequired(ProcessRunner runner, String executable,
    List<String> arguments, Directory directory) async {
  final result =
      await runner.run(executable, arguments, workingDirectory: directory.path);
  if (result.stdout.isNotEmpty) stdout.write(result.stdout);
  if (result.stderr.isNotEmpty) stderr.write(result.stderr);
  if (result.exitCode != 0) {
    throw CommandFailure(
        '$executable ${arguments.join(' ')} failed (exit ${result.exitCode}).');
  }
}

String executableFor(String name) => Platform.isWindows ? '$name.bat' : name;

Directory? localPackagesDirectory(Directory start) {
  final override = Platform.environment['DARTLOOM_PACKAGES_PATH'];
  if (override != null && Directory(override).existsSync()) {
    return Directory(override);
  }
  var current = start.absolute;
  while (true) {
    final candidate =
        Directory('${current.path}${Platform.pathSeparator}packages');
    if (candidate.existsSync()) return candidate;
    final parent = current.parent;
    if (parent.path == current.path) return null;
    current = parent;
  }
}

String projectNameFromPubspec(Directory project) {
  final file = File('${project.path}${Platform.pathSeparator}pubspec.yaml');
  if (!file.existsSync()) return 'dartloom_app';
  final match = RegExp(r'^name:\s*([A-Za-z0-9_-]+)\s*$', multiLine: true)
      .firstMatch(file.readAsStringSync());
  return match?.group(1) ?? 'dartloom_app';
}
