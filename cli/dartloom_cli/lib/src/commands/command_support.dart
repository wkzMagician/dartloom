import 'dart:io';

import '../capabilities/capability_registry.dart';
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
String rewriteDartloomDependencies(
  String content,
  DartloomConfig config, {
  Directory? packagesDirectory,
}) {
  const dependencyStart = '  # dartloom:dependencies:start';
  const dependencyEnd = '  # dartloom:dependencies:end';
  const overrideStart = '  # dartloom:overrides:start';
  const overrideEnd = '  # dartloom:overrides:end';
  var result = content
      .replaceAll(
        RegExp(
          '${RegExp.escape(dependencyStart)}[\\s\\S]*?${RegExp.escape(dependencyEnd)}\\r?\\n?',
        ),
        '',
      )
      .replaceAll(
        RegExp(
          '${RegExp.escape(overrideStart)}[\\s\\S]*?${RegExp.escape(overrideEnd)}\\r?\\n?',
        ),
        '',
      );
  for (final name in CapabilityRegistry.allPackageNames) {
    result = result.replaceAll(
      RegExp(
        '^  ${RegExp.escape(name)}:(?: [^\\r\\n]+)?\\r?\\n(?: {4,}.*\\r?\\n)*',
        multiLine: true,
      ),
      '',
    );
  }
  final packages = CapabilityRegistry.packagesFor(config);
  final dependencyBlock = StringBuffer()..writeln(dependencyStart);
  for (final package in packages) {
    dependencyBlock.writeln('  ${package.name}: ${package.version}');
  }
  dependencyBlock.writeln(dependencyEnd);
  result = result.replaceFirst(
    RegExp(r'dependencies:\r?\n'),
    'dependencies:\n$dependencyBlock',
  );

  if (config.capabilitySource == CapabilitySource.github) {
    final overrideBlock = StringBuffer()..writeln(overrideStart);
    for (final package in packages) {
      final local = packagesDirectory == null
          ? null
          : Directory(
              '${packagesDirectory.path}${Platform.pathSeparator}${package.name}',
            );
      overrideBlock.writeln('  ${package.name}:');
      if (local != null && local.existsSync()) {
        overrideBlock.writeln(
          '    path: ${local.path.replaceAll('\\', '/')}',
        );
      } else {
        overrideBlock
          ..writeln('    git:')
          ..writeln('      url: $dartloomRepositoryUrl')
          ..writeln('      path: ${package.path}');
      }
    }
    overrideBlock.writeln(overrideEnd);
    if (RegExp(r'^dependency_overrides:\r?$', multiLine: true)
        .hasMatch(result)) {
      result = result.replaceFirst(
        RegExp(r'dependency_overrides:\r?\n'),
        'dependency_overrides:\n$overrideBlock',
      );
    } else {
      result = '${result.trimRight()}\n\ndependency_overrides:\n$overrideBlock';
    }
  }
  result = result.replaceAll(
    RegExp(r'\ndependency_overrides:\r?\n(?=\S|$)'),
    '\n',
  );
  return result.endsWith('\n') ? result : '$result\n';
}
