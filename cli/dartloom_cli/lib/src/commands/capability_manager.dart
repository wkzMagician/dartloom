import 'dart:io';

import '../config/config_loader.dart';
import '../config/dartloom_config.dart';
import '../capabilities/capability_registry.dart';
import '../process/process_runner.dart';
import '../templates/managed_templates.dart';
import 'check_command.dart';
import 'command_support.dart';

class CapabilityChange {
  const CapabilityChange({
    required this.added,
    required this.removed,
    required this.changed,
  });
  final Set<String> added;
  final Set<String> removed;
  final Set<String> changed;
  bool get isEmpty => added.isEmpty && removed.isEmpty && changed.isEmpty;
}

class CapabilityManager {
  CapabilityManager(this.runner, {ConfigLoader? loader})
      : _loader = loader ?? const ConfigLoader();

  final ProcessRunner runner;
  final ConfigLoader _loader;

  Future<CapabilityChange> apply(
    Directory project,
    Map<Capability, Map<String, CapabilityInstanceConfig>> desired,
  ) async {
    final current = await _loader.load(project);
    final before = _flatten(current.capabilities);
    final after = _flatten(desired);
    final change = CapabilityChange(
      added: after.keys.toSet().difference(before.keys.toSet()),
      removed: before.keys.toSet().difference(after.keys.toSet()),
      changed: after.keys
          .where((key) => before.containsKey(key) && before[key] != after[key])
          .toSet(),
    );
    if (change.isEmpty) return change;
    final next = current.copyWith(capabilities: desired);
    final errors = CapabilityRegistry.validationErrors(next);
    if (errors.isNotEmpty) throw ConfigException(errors.join(' '));
    await _writeProject(project, next);
    return change;
  }

  Future<void> setSource(Directory project, CapabilitySource source) async {
    final current = await _loader.load(project);
    await _writeProject(
      project,
      current.copyWith(capabilitySource: source),
      writeTemplates: false,
    );
  }

  Future<void> _writeProject(
    Directory project,
    DartloomConfig config, {
    bool writeTemplates = true,
  }) async {
    final pubspec =
        File('${project.path}${Platform.pathSeparator}pubspec.yaml');
    final content = rewriteDartloomDependencies(
      await pubspec.readAsString(),
      config,
      packagesDirectory: localPackagesDirectory(project),
    );
    await _loader.save(project, config);
    await pubspec.writeAsString(content);
    if (writeTemplates) {
      final capabilities = File(
        '${project.path}${Platform.pathSeparator}lib${Platform.pathSeparator}capabilities${Platform.pathSeparator}capabilities.dart',
      );
      await capabilities.parent.create(recursive: true);
      await capabilities.writeAsString(capabilityGlue(config));
      final bootstrap = File(
        '${project.path}${Platform.pathSeparator}lib${Platform.pathSeparator}capabilities${Platform.pathSeparator}bootstrap.dart',
      );
      await bootstrap.writeAsString(capabilityBootstrap);
    }
    await runRequired(
        runner, executableFor('flutter'), ['pub', 'upgrade'], project);
    if (config.enabledCapabilities.contains(Capability.localization)) {
      await runRequired(
        runner,
        executableFor('flutter'),
        ['gen-l10n'],
        project,
      );
    }
    await runRequired(runner, executableFor('dart'), ['format', '.'], project);
    await CheckCommand(runner).run(project);
  }

  Map<String, String> _flatten(
    Map<Capability, Map<String, CapabilityInstanceConfig>> capabilities,
  ) =>
      {
        for (final capability in capabilities.entries)
          for (final instance in capability.value.entries)
            '${capability.key.name}.${instance.key}':
                '${instance.value.implementation}|${instance.value.factory}|${instance.value.options}|${instance.value.dependsOn}|${instance.value.stores}|${instance.value.backend?.implementation}|${instance.value.backend?.options}|${instance.value.mergeFactory}|${instance.value.policy}',
      };
}
