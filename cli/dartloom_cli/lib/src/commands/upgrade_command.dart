import 'dart:io';

import '../config/config_loader.dart';
import '../config/dartloom_config.dart';
import '../config/schema5_migration.dart';
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
  }) async {
    final migration = await Schema5ConfigMigrator(loader: _loader).migrate(
      project,
      dryRun: dryRun,
    );
    stdout.writeln(migration.report.toStructuredJson());
    if (migration.report.isBlocked) {
      throw ConfigException(
        'Schema 5 migration is blocked. Resolve every reported app-owned '
        'path TODO and run dartloom upgrade again.',
      );
    }
    final config = migration.config;
    final files = <String, String>{
      'AGENTS.md': agentInstructions(config),
      '.github/workflows/ci.yml': ciWorkflow,
      '.github/workflows/release.yml': releaseWorkflow(config),
      'lib/capabilities/capabilities.dart': capabilityGlue(config),
      'lib/capabilities/bootstrap.dart': capabilityBootstrap,
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
    stdout.writeln(
      dryRun
          ? 'Application startup must call lib/capabilities/bootstrap.dart.'
          : 'Ensure the application calls bootstrapDartloom() before runApp.',
    );
    if (dryRun) return;

    final pubspec =
        File('${project.path}${Platform.pathSeparator}pubspec.yaml');
    var pubspecContent = rewriteDartloomDependencies(
      await pubspec.readAsString(),
      config,
      packagesDirectory: localPackagesDirectory(project),
    );
    if (config.enabledCapabilities.contains(Capability.localization) &&
        !RegExp(r'^  generate: true$', multiLine: true)
            .hasMatch(pubspecContent)) {
      pubspecContent = pubspecContent.replaceFirst(
        RegExp(r'^flutter:\r?$', multiLine: true),
        'flutter:\n  generate: true',
      );
    }
    await pubspec.writeAsString(pubspecContent);

    if (config.enabledCapabilities.contains(Capability.localization)) {
      await _createLocalizationScaffoldingIfMissing(project, dryRun: false);
    }
    // Git dependencies are pinned in pubspec.lock. A plain `pub get` would
    // retain an older Dartloom contract after this command has regenerated
    // glue for the current API, so always resolve a fresh lockfile first.
    stdout.writeln('Refreshing latest Dartloom dependencies and lockfile...');
    await runRequired(
      runner,
      executableFor('flutter'),
      ['--no-version-check', 'pub', 'upgrade'],
      project,
    );
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

  Future<void> _createLocalizationScaffoldingIfMissing(
    Directory project, {
    required bool dryRun,
  }) async {
    const files = <String, String>{
      'l10n.yaml': l10nYaml,
      'lib/l10n/app_en.arb': appEnArb,
      'lib/l10n/app_zh.arb': appZhArb,
    };
    for (final entry in files.entries) {
      final file = File(
        '${project.path}${Platform.pathSeparator}'
        '${entry.key.replaceAll('/', Platform.pathSeparator)}',
      );
      if (await file.exists()) continue;
      if (dryRun) {
        stdout.writeln('Would create ${entry.key} (it is missing)');
      } else {
        await file.parent.create(recursive: true);
        await file.writeAsString(entry.value);
        stdout.writeln('Created ${entry.key} (it was missing)');
      }
    }
  }
}
