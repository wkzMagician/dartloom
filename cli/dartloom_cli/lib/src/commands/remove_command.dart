import 'dart:io';

import '../capabilities/capability_registry.dart';
import '../config/config_loader.dart';
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
    final change = await _manager.apply(
      project,
      {...current.capabilities}..remove(capability),
    );
    if (change.isEmpty) {
      stdout.writeln('${capability.name} is not enabled. Nothing to do.');
      return;
    }
    stdout.writeln('Removed ${capability.name}.');
  }
}
