import 'dart:io';

import '../config/config_loader.dart';
import '../packages/package_catalog.dart';
import '../process/process_runner.dart';
import 'command_support.dart';
import 'configuration_tui.dart';
import 'documentation.dart';
import 'workflow_templates.dart';

class UpdateCommand {
  UpdateCommand(this.runner,
      {ConfigLoader? loader, PackageCatalog? catalog, ConfigurationTui? tui})
      : loader = loader ?? const ConfigLoader(),
        catalog = catalog ?? const PackageCatalog(),
        tui = tui ?? const ConfigurationTui();
  final ProcessRunner runner;
  final ConfigLoader loader;
  final PackageCatalog catalog;
  final ConfigurationTui tui;

  Future<void> run(Directory project,
      {bool confirmPlatformRemoval = false}) async {
    final oldConfig = await loader.load(project);
    final packages = await catalog.load(project);
    final next = await tui.select(
        initialPlatforms: oldConfig.platforms,
        initialPackages: oldConfig.packages,
        available: packages);
    final removed = oldConfig.platforms.difference(next.platforms);
    if (removed.isNotEmpty && !confirmPlatformRemoval) {
      stdout.writeln(
          'Platform removal requested: ${removed.map((e) => e.name).join(', ')}.');
      stdout.write(
          'Delete the corresponding Flutter platform directories? [y/N] ');
      if (stdin.readLineSync()?.toLowerCase() != 'y') {
        throw CommandFailure('Platform removal cancelled.');
      }
    }
    final added = next.platforms.difference(oldConfig.platforms);
    if (added.isNotEmpty) {
      await runRequired(
          runner,
          executableFor('flutter'),
          [
            'create',
            '--platforms=${next.platforms.map((e) => e.name).join(',')}'
          ],
          project);
    }
    for (final platform in removed) {
      final directory =
          Directory('${project.path}${Platform.pathSeparator}${platform.name}');
      if (await directory.exists()) await directory.delete(recursive: true);
    }
    await loader.save(project, next);
    await updateDependencies(project, next);
    final workflows = Directory(
        '${project.path}${Platform.pathSeparator}.github${Platform.pathSeparator}workflows');
    await workflows.create(recursive: true);
    final ci = File('${workflows.path}${Platform.pathSeparator}ci.yml');
    await ci.writeAsString(ciWorkflow());
    final cloudBuild =
        File('${workflows.path}${Platform.pathSeparator}dartloom-build.yml');
    await cloudBuild.writeAsString(cloudBuildWorkflow());
    final release =
        File('${workflows.path}${Platform.pathSeparator}release.yml');
    await release.writeAsString(releaseWorkflow(next));
    final installer =
        Directory('${project.path}${Platform.pathSeparator}installer');
    await installer.create(recursive: true);
    final windowsInstallerFile =
        File('${installer.path}${Platform.pathSeparator}windows.iss');
    if (!await windowsInstallerFile.exists()) {
      await windowsInstallerFile.writeAsString(windowsInstaller());
    }
    final agents = File('${project.path}${Platform.pathSeparator}AGENTS.md');
    await agents.writeAsString(await updateAgents(agents, next, catalog));
    if (oldConfig.packages
            .toSet()
            .difference(next.packages.toSet())
            .isNotEmpty ||
        added.isNotEmpty ||
        removed.isNotEmpty) {
      await runRequired(
          runner, executableFor('flutter'), ['pub', 'get'], project);
    }
  }
}
