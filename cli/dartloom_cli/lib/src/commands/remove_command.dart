import 'dart:io';

import '../capabilities/capability_registry.dart';
import '../config/config_loader.dart';
import '../process/process_runner.dart';
import 'check_command.dart';
import 'command_support.dart';
import 'new_command.dart' show capabilityGlue;

class RemoveCommand {
  RemoveCommand(this.runner, {ConfigLoader? loader})
      : _loader = loader ?? const ConfigLoader();

  final ProcessRunner runner;
  final ConfigLoader _loader;

  Future<void> run(Directory project, String rawCapability) async {
    final capability = CapabilityRegistry.parse(rawCapability);
    final config = await _loader.load(project);
    if (!config.capabilities.contains(capability)) {
      stdout.writeln('${capability.name} is not enabled. Nothing to do.');
      return;
    }

    final updated = config.copyWith(
      capabilities: {...config.capabilities}..remove(capability),
    );
    await _loader.save(project, updated);
    final metadata = CapabilityRegistry.all[capability]!;
    final pubspec =
        File('${project.path}${Platform.pathSeparator}pubspec.yaml');
    final content = await pubspec.readAsString();
    final dependency = RegExp(
      '^  ${RegExp.escape(metadata.packageName)}:\\r?\\n(?: {4,}.*\\r?\\n)*',
      multiLine: true,
    );
    await pubspec.writeAsString(content.replaceFirst(dependency, ''));
    await File(
      '${project.path}${Platform.pathSeparator}lib${Platform.pathSeparator}capabilities${Platform.pathSeparator}capabilities.dart',
    ).writeAsString(capabilityGlue(updated.capabilities));
    await runRequired(
        runner, executableFor('flutter'), ['pub', 'get'], project);
    await runRequired(runner, executableFor('dart'), ['format', '.'], project);
    await CheckCommand(runner).run(project);
  }
}
