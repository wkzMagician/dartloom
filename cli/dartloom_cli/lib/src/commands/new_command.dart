import 'dart:io';

import '../config/config_loader.dart';
import '../config/dartloom_config.dart';
import '../packages/package_catalog.dart';
import '../process/process_runner.dart';
import 'command_support.dart';
import 'configuration_tui.dart';
import 'documentation.dart';
import 'generated_tests.dart';
import 'workflow_templates.dart';

class NewCommand {
  NewCommand(this.runner,
      {ConfigLoader? loader, PackageCatalog? catalog, ConfigurationTui? tui})
      : loader = loader ?? const ConfigLoader(),
        catalog = catalog ?? const PackageCatalog(),
        tui = tui ?? const ConfigurationTui();
  final ProcessRunner runner;
  final ConfigLoader loader;
  final PackageCatalog catalog;
  final ConfigurationTui tui;

  Future<void> run(
      {required Directory parent,
      required String name,
      Set<TargetPlatform>? platforms,
      List<String>? packages}) async {
    if (!RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(name)) {
      throw CommandFailure('Invalid project name "$name".');
    }
    final project = Directory('${parent.path}${Platform.pathSeparator}$name');
    if (await project.exists()) {
      throw CommandFailure('Target directory already exists: ${project.path}');
    }
    final available = await catalog.load(parent);
    final selection = await tui.select(
        initialPlatforms: platforms,
        initialPackages: packages,
        available: available);
    await runRequired(
        runner,
        executableFor('flutter'),
        [
          'create',
          '--platforms=${selection.platforms.map((e) => e.name).join(',')}',
          name
        ],
        parent);
    await _write(project, selection);
    await runRequired(
        runner, executableFor('flutter'), ['pub', 'get'], project);
  }

  Future<void> _write(Directory project, DartloomConfig config) async {
    await loader.save(project, config);
    for (final path in ['lib/app', 'lib/features', 'lib/shared', 'test']) {
      await Directory('${project.path}${Platform.pathSeparator}$path')
          .create(recursive: true);
    }
    final iconTest = File(
        '${project.path}${Platform.pathSeparator}test${Platform.pathSeparator}app_icon_test.dart');
    if (!await iconTest.exists()) {
      await iconTest.writeAsString(appIconTest(config.platforms));
    }
    final agents = File('${project.path}${Platform.pathSeparator}AGENTS.md');
    await agents.writeAsString(await updateAgents(agents, config, catalog));
    await updateDependencies(project, config);
    final workflows = Directory(
        '${project.path}${Platform.pathSeparator}.github${Platform.pathSeparator}workflows');
    await workflows.create(recursive: true);
    final appName = projectNameFromPubspec(project);
    final appVersion = projectVersionFromPubspec(project);
    await File('${workflows.path}${Platform.pathSeparator}ci.yml')
        .writeAsString(ciWorkflow());
    await File('${workflows.path}${Platform.pathSeparator}dartloom-build.yml')
        .writeAsString(cloudBuildWorkflow(appName: appName));
    final installer =
        Directory('${project.path}${Platform.pathSeparator}installer');
    await installer.create(recursive: true);
    await File('${installer.path}${Platform.pathSeparator}windows.iss')
        .writeAsString(
            windowsInstaller(appName: appName, appVersion: appVersion));
    await File('${workflows.path}${Platform.pathSeparator}release.yml')
        .writeAsString(releaseWorkflow(config, appName: appName));
  }
}
