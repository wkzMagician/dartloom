import 'dart:io';

import 'package:args/args.dart';

import 'package:dartloom/src/capabilities/capability_registry.dart';
import 'package:dartloom/src/commands/add_command.dart';
import 'package:dartloom/src/commands/build_command.dart';
import 'package:dartloom/src/commands/cap_list_command.dart';
import 'package:dartloom/src/commands/cap_tui.dart';
import 'package:dartloom/src/commands/check_command.dart';
import 'package:dartloom/src/commands/command_support.dart';
import 'package:dartloom/src/commands/doctor_command.dart';
import 'package:dartloom/src/commands/new_command.dart';
import 'package:dartloom/src/commands/package_command.dart';
import 'package:dartloom/src/commands/remove_command.dart';
import 'package:dartloom/src/commands/self_upgrade_command.dart';
import 'package:dartloom/src/commands/upgrade_command.dart';
import 'package:dartloom/src/config/dartloom_config.dart';
import 'package:dartloom/src/process/process_runner.dart';

Future<void> main(List<String> arguments) async {
  final runner = const SystemProcessRunner();
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addCommand('new')
    ..addCommand('cap')
    ..addCommand('check')
    ..addCommand('build')
    ..addCommand('package')
    ..addCommand('self-update')
    ..addCommand('project')
    ..addCommand('doctor');
  parser.commands['new']!
    ..addOption('org', defaultsTo: 'com.example')
    ..addOption('platforms', defaultsTo: 'android,windows,macos')
    ..addOption('capabilities', defaultsTo: 'settings,storage,logging')
    ..addOption('source', defaultsTo: 'github');
  parser.commands['cap']!
    ..addCommand('add')
    ..addCommand('list')
    ..addCommand('remove');
  parser.commands['project']!.addCommand('upgrade')
    ..addOption('source', allowed: ['github', 'pub'])
    ..addFlag(
      'dry-run',
      negatable: false,
    );
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
          capabilitySource: _source(command['source'] as String),
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
      case 'package':
        if (command.rest.length != 2) {
          throw CommandFailure(
              'Usage: dartloom package <windows|linux> <format>');
        }
        await PackageCommand(runner).run(
          Directory.current,
          command.rest.first,
          command.rest.last,
        );
      case 'self-update':
        if (command.rest.isNotEmpty) {
          throw CommandFailure('Usage: dartloom self-update');
        }
        await SelfUpgradeCommand(runner).run(Directory.current);
      case 'project':
        final subcommand = command.command;
        if (subcommand == null || subcommand.name != 'upgrade') {
          throw CommandFailure(
              'Usage: dartloom project upgrade [--source=github|pub] [--dry-run]');
        }
        if (subcommand.rest.isNotEmpty) {
          throw CommandFailure(
              'Usage: dartloom project upgrade [--source=github|pub] [--dry-run]');
        }
        await UpgradeCommand(runner).run(
          Directory.current,
          dryRun: subcommand['dry-run'] as bool,
          source: subcommand['source'] == null
              ? null
              : _source(subcommand['source'] as String),
        );
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
CapabilitySource _source(String raw) {
  try {
    return CapabilitySource.values.byName(raw.toLowerCase());
  } on ArgumentError {
    throw CommandFailure('Source must be github or pub.');
  }
}

void _usage(ArgParser parser, {bool error = false}) {
  (error ? stderr : stdout)
      .writeln('''Dartloom — Flutter capability and lifecycle tooling

Usage: dartloom <command> [arguments]

Commands:
  new <name>       Create a managed Flutter application.
  cap [command]    Manage capabilities interactively or by subcommand.
  check            Format, analyze, and test the current app.
  build [target]   Build enabled targets into dist/.
  package          Create an OS installer or system package.
  self-update      Update the installed Dartloom CLI.
  project upgrade  Update Dartloom-managed files in the current app.
  doctor           Check development prerequisites.

Capability commands:
  cap              Open the terminal capability manager.
  cap list         List enabled and available capabilities.
  cap add <name>   Enable a capability.
  cap remove <name> Disable a capability and its instances.

Capability configuration:
  Every capability can have named instances and a selected implementation.
  storage uses the generic instance names text, json, and database.
  Values such as \${WEBDAV_PASSWORD} require --dart-define at app build time.

Dependency source:
  project upgrade --source=github
                   Resolve enabled capabilities from GitHub (development).
  project upgrade --source=pub
                   Resolve enabled capabilities from pub.dev (release).

Package targets:
  package windows exe   Windows Setup.exe (requires Inno Setup/iscc.exe on PATH).
  package windows zip   Portable Windows ZIP.
  package windows msix  Windows MSIX (requires the msix dev dependency).
  package linux deb     Debian/Ubuntu package (Linux host required).
  package linux rpm     Red Hat/Fedora/Rocky/Alma package (Linux host required).

Not yet supported: macOS DMG/PKG, iOS IPA, Android installer formats, and web installers.

Project upgrade options:
  project upgrade --dry-run         List managed files that would be overwritten.
  project upgrade --source=github   Use GitHub/path dependencies.
  project upgrade --source=pub      Use hosted pub.dev dependencies.
  project upgrade                   Refreshes Dartloom dependencies with flutter pub upgrade.

${parser.usage}''');
}
