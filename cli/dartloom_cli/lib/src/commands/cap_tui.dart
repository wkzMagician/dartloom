import 'dart:io';

import '../capabilities/capability_registry.dart';
import '../config/config_loader.dart';
import '../config/dartloom_config.dart';
import '../process/process_runner.dart';
import 'add_command.dart';
import 'remove_command.dart';

/// A portable line-based terminal UI. It deliberately avoids terminal-specific
/// escape sequences so it works in PowerShell, cmd, and CI-adjacent terminals.
class CapTui {
  CapTui(this.runner, {ConfigLoader? loader})
      : _loader = loader ?? const ConfigLoader();
  final ProcessRunner runner;
  final ConfigLoader _loader;

  Future<void> run(Directory project) async {
    while (true) {
      final config = await _loader.load(project);
      _render(config);
      stdout.write('\nEnter a number to toggle it, or q to quit: ');
      final response = stdin.readLineSync()?.trim().toLowerCase();
      if (response == null || response == 'q' || response == 'quit') return;
      final index = int.tryParse(response);
      if (index == null || index < 1 || index > Capability.values.length) {
        stdout.writeln('Enter a capability number or q.');
        continue;
      }
      final capability = Capability.values[index - 1];
      if (config.capabilities.contains(capability)) {
        await RemoveCommand(runner, loader: _loader)
            .run(project, capability.name);
      } else {
        await AddCommand(runner, loader: _loader).run(project, capability.name);
      }
    }
  }

  void _render(DartloomConfig config) {
    stdout.writeln('\nDartloom Capability Manager');
    stdout.writeln('Project: ${config.app.name}\n');
    for (var index = 0; index < Capability.values.length; index++) {
      final capability = Capability.values[index];
      final enabled = config.capabilities.contains(capability) ? 'x' : ' ';
      final platforms = CapabilityRegistry.all[capability]!.platforms
          .map((item) => item.name)
          .join(', ');
      stdout
          .writeln('${index + 1}. [$enabled] ${capability.name} ($platforms)');
    }
  }
}
