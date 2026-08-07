import 'dart:io';

import '../capabilities/capability_registry.dart';
import '../config/config_loader.dart';
import '../config/dartloom_config.dart';
import '../process/process_runner.dart';
import '../templates/managed_templates.dart';
import 'check_command.dart';
import 'command_support.dart';

class CapabilityChange {
  const CapabilityChange({required this.added, required this.removed});

  final Set<Capability> added;
  final Set<Capability> removed;
  bool get isEmpty => added.isEmpty && removed.isEmpty;
}

/// Applies an entire capability selection before resolving dependencies once.
class CapabilityManager {
  CapabilityManager(this.runner, {ConfigLoader? loader})
      : _loader = loader ?? const ConfigLoader();

  final ProcessRunner runner;
  final ConfigLoader _loader;

  Future<CapabilityChange> apply(
    Directory project,
    Set<Capability> desiredCapabilities,
  ) async {
    final current = await _loader.load(project);
    final added = desiredCapabilities.difference(current.capabilities);
    final removed = current.capabilities.difference(desiredCapabilities);
    final change = CapabilityChange(added: added, removed: removed);
    if (change.isEmpty) return change;

    final updated = current.copyWith(capabilities: desiredCapabilities);
    final pubspec =
        File('${project.path}${Platform.pathSeparator}pubspec.yaml');
    var content = await pubspec.readAsString();
    for (final capability in removed) {
      content = content.replaceFirst(_dependencyPattern(capability), '');
    }
    for (final capability in added) {
      final packageName = CapabilityRegistry.all[capability]!.packageName;
      if (!content.contains('$packageName:')) {
        content = content.replaceFirst(
          RegExp(r'dependencies:\r?\n'),
          'dependencies:\n${capabilityDependency(packageName, packagesDirectory: localPackagesDirectory(project))}',
        );
      }
    }

    await _loader.save(project, updated);
    await pubspec.writeAsString(content);
    await File(
      '${project.path}${Platform.pathSeparator}lib${Platform.pathSeparator}capabilities${Platform.pathSeparator}capabilities.dart',
    ).writeAsString(capabilityGlue(updated.capabilities));
    await runRequired(
        runner, executableFor('flutter'), ['pub', 'get'], project);
    await runRequired(runner, executableFor('dart'), ['format', '.'], project);
    await CheckCommand(runner).run(project);
    return change;
  }

  RegExp _dependencyPattern(Capability capability) {
    final packageName = CapabilityRegistry.all[capability]!.packageName;
    return RegExp(
      '^  ${RegExp.escape(packageName)}:\\r?\\n(?: {4,}.*\\r?\\n)*',
      multiLine: true,
    );
  }
}
