import 'dart:io';

import '../capabilities/capability_registry.dart';
import '../config/config_loader.dart';
import '../process/process_runner.dart';
import 'check_command.dart';
import 'command_support.dart';
import 'new_command.dart' show capabilityGlue;

class AddCommand {
  AddCommand(this.runner, {ConfigLoader? loader})
      : _loader = loader ?? const ConfigLoader();
  final ProcessRunner runner;
  final ConfigLoader _loader;

  Future<void> run(Directory project, String rawCapability) async {
    final capability = CapabilityRegistry.parse(rawCapability);
    final config = await _loader.load(project);
    if (config.capabilities.contains(capability)) {
      stdout.writeln('${capability.name} is already enabled. Nothing to do.');
      return;
    }
    final updated =
        config.copyWith(capabilities: {...config.capabilities, capability});
    await _loader.save(project, updated);
    final metadata = CapabilityRegistry.all[capability]!;
    final pubspec =
        File('${project.path}${Platform.pathSeparator}pubspec.yaml');
    var text = await pubspec.readAsString();
    if (!text.contains('${metadata.packageName}:')) {
      final packages = localPackagesDirectory(project);
      if (packages == null) {
        throw CommandFailure(
            'Cannot locate Dartloom capability packages. Set DARTLOOM_PACKAGES_PATH.');
      }
      final localPath =
          '${packages.path}${Platform.pathSeparator}${metadata.packageName}'
              .replaceAll('\\', '/');
      text = text.replaceFirst(
        RegExp(r'dependencies:\r?\n'),
        'dependencies:\n  ${metadata.packageName}:\n    path: $localPath\n',
      );
      await pubspec.writeAsString(text);
    }
    await File(
            '${project.path}${Platform.pathSeparator}lib${Platform.pathSeparator}capabilities${Platform.pathSeparator}capabilities.dart')
        .writeAsString(capabilityGlue(updated.capabilities));
    await runRequired(
        runner, executableFor('flutter'), ['pub', 'get'], project);
    await runRequired(runner, executableFor('dart'), ['format', '.'], project);
    await CheckCommand(runner).run(project);
  }
}
