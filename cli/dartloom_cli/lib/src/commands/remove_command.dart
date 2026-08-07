import 'dart:io';

import '../capabilities/capability_registry.dart';
import '../config/config_loader.dart';
import '../config/dartloom_config.dart';
import '../process/process_runner.dart';
import 'capability_manager.dart';

class RemoveCommand {
  RemoveCommand(this.runner, {ConfigLoader? loader})
      : _loader = loader ?? const ConfigLoader(),
        _manager = CapabilityManager(runner, loader: loader);

  final ProcessRunner runner;
  final ConfigLoader _loader;
  final CapabilityManager _manager;

  Future<void> run(Directory project, String rawCapability) async {
    final capability = CapabilityRegistry.parse(rawCapability);
    final current = await _loader.load(project);
    if (capability == Capability.storage &&
        current.capabilities.containsKey(Capability.sync)) {
      throw StateError(
        'storage is referenced by sync. Remove sync first or use the interactive manager.',
      );
    }
    final change = await _manager.apply(project, {
      for (final entry in current.capabilities.entries)
        if (entry.key != capability) entry.key: {...entry.value},
    });
    if (change.isEmpty) {
      stdout.writeln('${capability.name} is not enabled. Nothing to do.');
      return;
    }
    stdout.writeln('Removed ${capability.name}.');
  }
}
