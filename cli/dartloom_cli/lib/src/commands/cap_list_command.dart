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
      final instances = config.capabilities[capability] ?? const {};
      final enabled = instances.isNotEmpty ? 'enabled ' : 'disabled';
      final supported =
          metadata.platforms.map((platform) => platform.name).join(', ');
      stdout.writeln('${capability.name.padRight(12)} $enabled  $supported');
      for (final instance in instances.entries) {
        final backend = instance.value.backend == null
            ? ''
            : ' + ${instance.value.backend!.implementation}';
        stdout.writeln(
          '  ${instance.key.padRight(10)} ${instance.value.implementation}$backend',
        );
      }
    }
  }
}
