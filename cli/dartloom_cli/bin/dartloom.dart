import 'dart:io';

import 'package:args/args.dart';
import 'package:dartloom_cli/src/commands/check_command.dart';
import 'package:dartloom_cli/src/commands/command_support.dart';
import 'package:dartloom_cli/src/commands/new_command.dart';
import 'package:dartloom_cli/src/commands/update_command.dart';
import 'package:dartloom_cli/src/config/dartloom_config.dart';
import 'package:dartloom_cli/src/process/process_runner.dart';
import 'package:dartloom_cli/src/commands/build_command.dart';
import 'package:dartloom_cli/src/build/build_models.dart';
import 'package:dartloom_cli/src/commands/release_command.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()..addFlag('help', abbr: 'h', negatable: false);
  for (final command in ['new', 'update', 'check', 'build', 'release']) {
    parser.addCommand(command);
  }
  parser.commands['new']!.addOption('platforms');
  parser.commands['new']!.addOption('packages');
  parser.commands['new']!.addOption('visibility', defaultsTo: 'public');
  parser.commands['build']!.addOption('mode', defaultsTo: 'release');
  try {
    final results = parser.parse(arguments);
    if (results['help'] == true || results.command == null) {
      _usage();
      return;
    }
    final command = results.command!;
    final runner = const SystemProcessRunner();
    final path = Directory.current.path;
    switch (command.name) {
      case 'new':
        if (command.rest.length != 1) {
          throw CommandFailure('Usage: dartloom new <project-name>');
        }
        await NewCommand(runner).run(
            parent: Directory.current,
            name: command.rest.single,
            platforms: _platforms(command['platforms'] as String?),
            packages: _packages(command['packages'] as String?),
            visibility: command['visibility'] as String);
      case 'update':
        if (command.rest.isNotEmpty) {
          throw CommandFailure('Usage: dartloom update');
        }
        await UpdateCommand(runner).run(Directory(path));
      case 'check':
        if (command.rest.isNotEmpty) {
          throw CommandFailure('Usage: dartloom check');
        }
        await CheckCommand().run(Directory(path));
      case 'build':
        if (command.rest.length != 1) {
          throw CommandFailure('Usage: dartloom build <platform|all>');
        }
        final target = command.rest.single.toLowerCase();
        await BuildCommand().run(target,
            all: target == 'all',
            mode: BuildModeName.parse(command['mode'] as String));
      case 'release':
        if (command.rest.length > 1) {
          throw CommandFailure('Usage: dartloom release [version]');
        }
        await const ReleaseCommand().run(Directory.current,
            version: command.rest.isEmpty ? null : command.rest.single);
    }
  } on FormatException catch (error) {
    stderr.writeln(error);
    _usage();
    exitCode = 2;
  } on Object catch (error) {
    stderr.writeln('Dartloom: $error');
    exitCode = 1;
  }
}

Set<TargetPlatform>? _platforms(String? raw) => raw == null
    ? null
    : {
        for (final value in raw.split(','))
          TargetPlatformName.parse(value.trim())
      };
List<String>? _packages(String? raw) =>
    raw?.split(',').where((e) => e.isNotEmpty).toList();

void _usage() => stdout.writeln('''Dartloom — Flutter project configurator

Usage:
  dartloom new <project-name>
  dartloom update
  dartloom check
  dartloom build <platform|all>
  dartloom release [version]
''');
