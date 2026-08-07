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
          'dependencies:\n${capabilityDependency(packageName, source: updated.capabilitySource, packagesDirectory: localPackagesDirectory(project))}',
        );
      }
    }

    await _loader.save(project, updated);
    await pubspec.writeAsString(content);
    await File(
      '${project.path}${Platform.pathSeparator}lib${Platform.pathSeparator}capabilities${Platform.pathSeparator}capabilities.dart',
    ).writeAsString(capabilityGlue(updated.capabilities));
    final appDirectory = Directory(
      '${project.path}${Platform.pathSeparator}lib${Platform.pathSeparator}app',
    );
    await appDirectory.create(recursive: true);
    await File(
      '${appDirectory.path}${Platform.pathSeparator}app.dart',
    ).writeAsString(appShell(updated));
    await runRequired(
        runner, executableFor('flutter'), ['pub', 'get'], project);
    await runRequired(runner, executableFor('dart'), ['format', '.'], project);
    await CheckCommand(runner).run(project);
    return change;
  }

  /// Switches all enabled capability dependencies between GitHub and pub.dev.
  Future<void> setSource(Directory project, CapabilitySource source) async {
    final current = await _loader.load(project);
    final updated = current.copyWith(capabilitySource: source);
    final pubspec =
        File('${project.path}${Platform.pathSeparator}pubspec.yaml');
    var content = await pubspec.readAsString();
    for (final capability in Capability.values) {
      content = content.replaceFirst(_dependencyPattern(capability), '');
    }
    final dependencies = [
      for (final capability in Capability.values)
        if (updated.capabilities.contains(capability))
          capabilityDependency(
            CapabilityRegistry.all[capability]!.packageName,
            source: source,
            packagesDirectory: localPackagesDirectory(project),
          ),
    ].join();
    if (dependencies.isNotEmpty) {
      content = content.replaceFirst(
        RegExp(r'dependencies:\r?\n'),
        'dependencies:\n$dependencies',
      );
    }
    await _loader.save(project, updated);
    await pubspec.writeAsString(content);
    await runRequired(
        runner, executableFor('flutter'), ['pub', 'get'], project);
    await runRequired(runner, executableFor('dart'), ['format', '.'], project);
    await CheckCommand(runner).run(project);
  }

  RegExp _dependencyPattern(Capability capability) {
    final packageName = CapabilityRegistry.all[capability]!.packageName;
    return RegExp(
      '^  ${RegExp.escape(packageName)}:(?: [^\\r\\n]+)?\\r?\\n(?: {4,}.*\\r?\\n)*',
      multiLine: true,
    );
  }
}
