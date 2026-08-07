import 'dart:io';

import '../config/config_loader.dart';
import '../config/dartloom_config.dart';
import '../process/process_runner.dart';
import 'capability_manager.dart';

/// Displays or changes the dependency source for this Dartloom application.
class SourceCommand {
  SourceCommand(this.runner, {ConfigLoader? loader})
      : _loader = loader ?? const ConfigLoader(),
        _manager = CapabilityManager(runner, loader: loader);

  final ProcessRunner runner;
  final ConfigLoader _loader;
  final CapabilityManager _manager;

  Future<void> run(Directory project, CapabilitySource? source) async {
    final config = await _loader.load(project);
    if (source == null) {
      stdout.writeln(
          'Dartloom capability source: ${config.capabilitySource.name}');
      stdout.writeln(
        config.capabilitySource == CapabilitySource.github
            ? 'Enabled capabilities resolve from GitHub.'
            : 'Enabled capabilities resolve from pub.dev.',
      );
      return;
    }
    await _manager.setSource(project, source);
    stdout.writeln('Dartloom capability source changed to ${source.name}.');
  }
}
