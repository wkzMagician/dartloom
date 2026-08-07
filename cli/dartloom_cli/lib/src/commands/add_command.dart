import 'dart:io';

import '../capabilities/capability_registry.dart';
import '../config/config_loader.dart';
import '../config/dartloom_config.dart';
import '../process/process_runner.dart';
import 'capability_manager.dart';

class AddCommand {
  AddCommand(this.runner, {ConfigLoader? loader})
      : _loader = loader ?? const ConfigLoader(),
        _manager = CapabilityManager(runner, loader: loader);

  final ProcessRunner runner;
  final ConfigLoader _loader;
  final CapabilityManager _manager;

  Future<void> run(Directory project, String rawCapability) async {
    final capability = CapabilityRegistry.parse(rawCapability);
    final current = await _loader.load(project);
    final capabilities = {
      for (final entry in current.capabilities.entries)
        entry.key: {...entry.value},
    };
    if (capabilities.containsKey(capability)) {
      stdout.writeln('${capability.name} is already enabled. Nothing to do.');
      return;
    }
    capabilities[capability] = CapabilityDefaults.forCapability(capability);
    if (capability == Capability.sync) {
      capabilities.putIfAbsent(
        Capability.storage,
        () => CapabilityDefaults.forCapability(Capability.storage),
      );
      capabilities[Capability.storage]!.putIfAbsent(
        'json',
        () => CapabilityDefaults.forCapability(Capability.storage)['json']!,
      );
    }
    final change = await _manager.apply(project, capabilities);
    if (change.isEmpty) {
      stdout.writeln('${capability.name} is already enabled. Nothing to do.');
      return;
    }
    stdout.writeln('Enabled ${capability.name}.');
  }
}
