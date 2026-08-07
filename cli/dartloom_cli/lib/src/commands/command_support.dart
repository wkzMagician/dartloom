import 'dart:io';

import '../config/dartloom_config.dart';
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
    {required CapabilitySource source, Directory? packagesDirectory}) {
  final localPackage = packagesDirectory == null
      ? null
      : Directory(
          '${packagesDirectory.path}${Platform.pathSeparator}$packageName');
  if (source == CapabilitySource.github &&
      localPackage != null &&
      localPackage.existsSync()) {
    return '  $packageName:\n    path: ${localPackage.path.replaceAll('\\', '/')}\n';
  }
  if (source == CapabilitySource.pub) {
    return '  $packageName: $dartloomPackageVersion\n';
  }
  return '  $packageName:\n    git:\n      url: $dartloomRepositoryUrl\n      path: packages/$packageName\n';
}
