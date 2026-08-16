import 'dart:io';

import '../config/config_loader.dart';
import '../packages/package_catalog.dart';
import 'command_support.dart';
import 'documentation.dart';

class CheckCommand {
  CheckCommand({ConfigLoader? loader, PackageCatalog? catalog})
      : loader = loader ?? const ConfigLoader(),
        catalog = catalog ?? const PackageCatalog();
  final ConfigLoader loader;
  final PackageCatalog catalog;

  Future<void> run(Directory project) async {
    final config = await loader.load(project);
    final metadata = await catalog.load(project);
    final byName = {for (final item in metadata) item.name: item};
    final errors = <String>[];
    for (final name in config.packages) {
      final package = byName[name];
      if (package == null) {
        errors.add('Missing metadata for $name.');
        continue;
      }
      if (!package.platforms.containsAll(config.platforms)) {
        errors.add('$name does not support all selected Flutter platforms.');
      }
    }
    final pubspec =
        File('${project.path}${Platform.pathSeparator}pubspec.yaml');
    final pubspecText = await pubspec.readAsString();
    for (final name in config.packages) {
      if (!RegExp('^  ${RegExp.escape(name)}:', multiLine: true)
          .hasMatch(pubspecText)) {
        errors.add('$name is not a direct pubspec dependency.');
      }
    }
    final agents = File('${project.path}${Platform.pathSeparator}AGENTS.md');
    if (!await agents.exists()) {
      errors.add('AGENTS.md is missing.');
    } else if (await updateAgents(agents, config, catalog) !=
        await agents.readAsString()) {
      errors.add('The managed Dartloom section in AGENTS.md is out of date.');
    }
    if (errors.isNotEmpty) throw CommandFailure(errors.join('\n'));
    stdout.writeln('Dartloom configuration is valid.');
  }
}
