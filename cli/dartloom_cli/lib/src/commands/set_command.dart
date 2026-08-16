import 'dart:io';

import '../config/config_loader.dart';
import '../config/dartloom_config.dart';
import 'command_support.dart';

class SetCommand {
  const SetCommand({ConfigLoader? loader})
      : _loader = loader ?? const ConfigLoader();
  final ConfigLoader _loader;

  Future<void> run(Directory project, String property, String value) async {
    if (property != 'platforms') {
      throw CommandFailure('Supported settings: platforms.');
    }
    final platforms = <TargetPlatform>{};
    for (final raw in value.split(',')) {
      final item = raw.trim().toLowerCase();
      if (item.isEmpty) continue;
      try {
        platforms.add(TargetPlatform.values.byName(item));
      } on ArgumentError {
        throw CommandFailure(
            'Unknown platform "$item". Supported platforms: ${TargetPlatform.values.map((p) => p.name).join(', ')}.');
      }
    }
    if (platforms.isEmpty) {
      throw CommandFailure('At least one platform is required.');
    }
    final current = await _loader.load(project);
    await _loader.save(project, current.copyWith(platforms: platforms));
    stdout.writeln(
        'Updated platforms: ${TargetPlatform.values.where(platforms.contains).map((p) => p.name).join(', ')}');
  }
}
