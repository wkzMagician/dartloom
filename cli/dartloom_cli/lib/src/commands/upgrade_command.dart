import 'dart:io';

import '../capabilities/capability_registry.dart';
import '../config/config_loader.dart';
import '../process/process_runner.dart';
import '../templates/managed_templates.dart';
import 'check_command.dart';
import 'command_support.dart';

/// Refreshes Dartloom-owned files. Application features are never modified.
class UpgradeCommand {
  UpgradeCommand(this.runner, {ConfigLoader? loader})
      : _loader = loader ?? const ConfigLoader();

  final ProcessRunner runner;
  final ConfigLoader _loader;

  Future<void> run(
    Directory project, {
    required bool dryRun,
    required bool upgradeCapabilities,
  }) async {
    final config = await _loader.load(project);
    final files = <String, String>{
      'AGENTS.md': agentInstructions,
      '.github/workflows/ci.yml': ciWorkflow,
      '.github/workflows/release.yml': releaseWorkflow(config),
      'lib/capabilities/capabilities.dart': capabilityGlue(config.capabilities),
      'lib/app/app.dart': appShell(config),
    };
    stdout.writeln('Dartloom Upgrade${dryRun ? ' (dry run)' : ''}\n');
    for (final entry in files.entries) {
      final file = File(
          '${project.path}${Platform.pathSeparator}${entry.key.replaceAll('/', Platform.pathSeparator)}');
      if (dryRun) {
        stdout.writeln('Would overwrite ${entry.key}');
      } else {
        await file.parent.create(recursive: true);
        await file.writeAsString(entry.value);
        stdout.writeln('Updated ${entry.key}');
      }
    }
    if (dryRun) return;

    if (upgradeCapabilities && config.capabilities.isNotEmpty) {
      final packages = config.capabilities
          .map((capability) => CapabilityRegistry.all[capability]!.packageName)
          .toList();
      await runRequired(
        runner,
        executableFor('flutter'),
        ['pub', 'upgrade', ...packages],
        project,
      );
    }
    await CheckCommand(runner).run(project);
  }
}
