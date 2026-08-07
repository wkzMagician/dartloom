import 'dart:io';

import 'package:args/args.dart';

import 'package:dartloom_cli/src/capabilities/capability_registry.dart';
import 'package:dartloom_cli/src/commands/add_command.dart';
import 'package:dartloom_cli/src/commands/build_command.dart';
import 'package:dartloom_cli/src/commands/cap_list_command.dart';
import 'package:dartloom_cli/src/commands/cap_tui.dart';
import 'package:dartloom_cli/src/commands/check_command.dart';
import 'package:dartloom_cli/src/commands/command_support.dart';
import 'package:dartloom_cli/src/commands/doctor_command.dart';
import 'package:dartloom_cli/src/commands/new_command.dart';
import 'package:dartloom_cli/src/commands/release_command.dart';
import 'package:dartloom_cli/src/commands/remove_command.dart';
import 'package:dartloom_cli/src/config/dartloom_config.dart';
import 'package:dartloom_cli/src/process/process_runner.dart';

Future<void> main(List<String> arguments) async {
  final runner = const SystemProcessRunner();
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addCommand('new')
    ..addCommand('cap')
    ..addCommand('check')
    ..addCommand('build')
    ..addCommand('release')
    ..addCommand('doctor');
  parser.commands['new']!
    ..addOption('org', defaultsTo: 'com.example')
    ..addOption('platforms', defaultsTo: 'android,windows,macos')
    ..addOption('capabilities', defaultsTo: 'settings,storage,logging');
  parser.commands['cap']!
    ..addCommand('add')
    ..addCommand('list')
    ..addCommand('remove');
  try {
    final results = parser.parse(arguments);
    if (results['help'] == true || results.command == null) {
      return _usage(parser);
    }
    final command = results.command!;
    switch (command.name) {
      case 'new':
        if (command.rest.length != 1) {
          throw CommandFailure(
              'Usage: dartloom new <name> [--org=...] [--platforms=...] [--capabilities=...]');
        }
        await NewCommand(runner).run(
          parent: Directory.current,
          name: command.rest.single,
          organization: command['org'] as String,
          platforms: _platforms(command['platforms'] as String),
          capabilities: _capabilities(command['capabilities'] as String),
        );
      case 'cap':
        final subcommand = command.command;
        if (subcommand == null) {
          await CapTui(runner).run(Directory.current);
          return;
        }
        switch (subcommand.name) {
          case 'add':
            if (subcommand.rest.length != 1) {
              throw CommandFailure('Usage: dartloom cap add <capability>');
            }
            await AddCommand(runner)
                .run(Directory.current, subcommand.rest.single);
          case 'remove':
            if (subcommand.rest.length != 1) {
              throw CommandFailure('Usage: dartloom cap remove <capability>');
            }
            await RemoveCommand(runner)
                .run(Directory.current, subcommand.rest.single);
          case 'list':
            if (subcommand.rest.isNotEmpty) {
              throw CommandFailure('Usage: dartloom cap list');
            }
            await CapListCommand().run(Directory.current);
        }
      case 'check':
        await CheckCommand(runner).run(Directory.current);
      case 'build':
        await BuildCommand(runner).run(Directory.current, command.rest);
      case 'release':
        if (command.rest.length != 1) {
          throw CommandFailure('Usage: dartloom release <version>');
        }
        await ReleaseCommand(runner)
            .run(Directory.current, command.rest.single);
      case 'doctor':
        if (!await DoctorCommand(runner).run(Directory.current)) exitCode = 1;
    }
  } on FormatException catch (error) {
    stderr.writeln(error);
    _usage(parser, error: true);
  } on Object catch (error) {
    stderr.writeln('Dartloom: $error');
    exitCode = 1;
  }
}

Set<TargetPlatform> _platforms(String raw) => raw
    .split(',')
    .where((item) => item.isNotEmpty)
    .map((item) => TargetPlatformName.parse(item.trim()))
    .toSet();
Set<Capability> _capabilities(String raw) => raw
    .split(',')
    .where((item) => item.isNotEmpty)
    .map((item) => CapabilityRegistry.parse(item.trim()))
    .toSet();

void _usage(ArgParser parser, {bool error = false}) {
  (error ? stderr : stdout)
      .writeln('''Dartloom — Flutter application lifecycle tooling

Usage: dartloom <command> [arguments]

Commands:
  new <name>       Create a managed Flutter application.
  cap [command]    Manage capabilities interactively or by subcommand.
  check            Format, analyze, and test the current app.
  build [target]   Build enabled targets into dist/.
  release <ver>    Commit, tag, and push a release.
  doctor           Check development prerequisites.

Capability commands:
  cap              Open the terminal capability manager.
  cap list         List enabled and available capabilities.
  cap add <name>   Enable a capability.
  cap remove <n>   Disable a capability.

${parser.usage}''');
}
