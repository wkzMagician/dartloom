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

/// Finds the monorepo's local capability packages when developing Dartloom.
/// A published CLI can override this with DARTLOOM_PACKAGES_PATH.
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

const dartloomRepositoryUrl = 'https://github.com/wkzMagician/dartloom.git';
const dartloomPackageVersion = '^0.1.0';

String capabilityDependency(String packageName,
    {Directory? packagesDirectory}) {
  if (packagesDirectory != null) {
    return '  $packageName:\n    path: ${packagesDirectory.path.replaceAll('\\', '/')}/$packageName\n';
  }
  if (Platform.environment['DARTLOOM_CAPABILITY_SOURCE'] != 'git') {
    return '  $packageName: $dartloomPackageVersion\n';
  }
  return '  $packageName:\n    git:\n      url: $dartloomRepositoryUrl\n      path: packages/$packageName\n';
}
