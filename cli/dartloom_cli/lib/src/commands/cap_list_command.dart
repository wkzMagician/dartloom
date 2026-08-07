import 'dart:io';

import '../capabilities/capability_registry.dart';
import '../config/config_loader.dart';
import '../config/dartloom_config.dart';

class CapListCommand {
  CapListCommand({ConfigLoader? loader})
      : _loader = loader ?? const ConfigLoader();
  final ConfigLoader _loader;

  Future<void> run(Directory project) async {
    final config = await _loader.load(project);
    stdout.writeln(
        'Dartloom Capabilities (source: ${config.capabilitySource.name})\n');
    for (final capability in Capability.values) {
      final metadata = CapabilityRegistry.all[capability]!;
      final enabled =
          config.capabilities.contains(capability) ? 'enabled ' : 'disabled';
      final supported =
          metadata.platforms.map((platform) => platform.name).join(', ');
      stdout.writeln('${capability.name.padRight(12)} $enabled  $supported');
    }
  }
}
