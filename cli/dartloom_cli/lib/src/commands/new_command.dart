import 'dart:io';

import '../capabilities/capability_registry.dart';
import '../config/config_loader.dart';
import '../config/dartloom_config.dart';
import '../process/process_runner.dart';
import 'check_command.dart';
import 'command_support.dart';

class NewCommand {
  NewCommand(this.runner, {ConfigLoader? loader})
      : _loader = loader ?? const ConfigLoader();
  final ProcessRunner runner;
  final ConfigLoader _loader;

  Future<void> run(
      {required Directory parent,
      required String name,
      required String organization,
      required Set<TargetPlatform> platforms,
      required Set<Capability> capabilities}) async {
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
      throw CommandFailure(
          'Invalid app name "$name". Use lowercase letters, digits, and underscores.');
    }
    final project = Directory('${parent.path}${Platform.pathSeparator}$name');
    if (await project.exists()) {
      throw CommandFailure('Target directory already exists: ${project.path}');
    }
    final flutterPlatforms = platforms.map((item) => item.name).join(',');
    await runRequired(
        runner,
        executableFor('flutter'),
        [
          'create',
          '--org',
          organization,
          '--platforms=$flutterPlatforms',
          name
        ],
        parent);
    final config = DartloomConfig(
        app: AppConfig(
            name: name,
            organization: organization,
            description: '$name application'),
        platforms: platforms,
        capabilities: capabilities);
    await _loader.save(project, config);
    await _writeManagedFiles(project, config);
    await runRequired(
        runner, executableFor('flutter'), ['pub', 'get'], project);
    await runRequired(runner, executableFor('dart'), ['format', '.'], project);
    await CheckCommand(runner).run(project);
  }

  Future<void> _writeManagedFiles(
      Directory project, DartloomConfig config) async {
    final separator = Platform.pathSeparator;
    await Directory('${project.path}${separator}lib${separator}app')
        .create(recursive: true);
    await Directory('${project.path}${separator}lib${separator}features')
        .create(recursive: true);
    await Directory('${project.path}${separator}lib${separator}capabilities')
        .create(recursive: true);
    await Directory('${project.path}${separator}lib${separator}shared')
        .create(recursive: true);
    await Directory('${project.path}$separator.github${separator}workflows')
        .create(recursive: true);
    await File('${project.path}${separator}lib${separator}main.dart')
        .writeAsString(
            "import 'app/bootstrap.dart';\n\nvoid main() => bootstrap();\n");
    await File(
            '${project.path}${separator}lib${separator}app${separator}bootstrap.dart')
        .writeAsString(
            "import 'package:flutter/widgets.dart';\n\nimport 'app.dart';\n\nvoid bootstrap() {\n  WidgetsFlutterBinding.ensureInitialized();\n  runApp(const DartloomApp());\n}\n");
    await File(
            '${project.path}${separator}lib${separator}app${separator}app.dart')
        .writeAsString(
            "import 'package:flutter/material.dart';\n\nclass DartloomApp extends StatelessWidget {\n  const DartloomApp({super.key});\n\n  @override\n  Widget build(BuildContext context) => MaterialApp(\n        title: '${config.app.name}',\n        home: const Scaffold(body: Center(child: Text('Dartloom app')),),\n      );\n}\n");
    await File(
            '${project.path}${separator}lib${separator}app${separator}router.dart')
        .writeAsString(
            "import 'package:flutter/widgets.dart';\n\nRoute<dynamic> onGenerateRoute(RouteSettings settings) =>\n    PageRouteBuilder<void>(pageBuilder: (_, _, _) => const Placeholder());\n");
    await File('${project.path}${separator}test${separator}widget_test.dart')
        .writeAsString(
      "import 'package:flutter_test/flutter_test.dart';\n\nimport 'package:${config.app.name}/app/app.dart';\n\nvoid main() {\n  testWidgets('shows the Dartloom app shell', (tester) async {\n    await tester.pumpWidget(const DartloomApp());\n    expect(find.text('Dartloom app'), findsOneWidget);\n  });\n}\n",
    );
    await File('${project.path}${separator}AGENTS.md').writeAsString(_agents);
    await File(
            '${project.path}$separator.github${separator}workflows${separator}ci.yml')
        .writeAsString(_ciWorkflow);
    await File(
            '${project.path}$separator.github${separator}workflows${separator}release.yml')
        .writeAsString(_releaseWorkflow);
    await File(
            '${project.path}${separator}lib${separator}capabilities${separator}capabilities.dart')
        .writeAsString(capabilityGlue(config.capabilities));
    await _addPackageDependencies(project, config.capabilities);
  }

  Future<void> _addPackageDependencies(
      Directory project, Set<Capability> capabilities) async {
    final pubspec =
        File('${project.path}${Platform.pathSeparator}pubspec.yaml');
    var content = await pubspec.readAsString();
    final repoPackages = localPackagesDirectory(project.parent);
    if (repoPackages == null) return;
    for (final capability in capabilities) {
      final metadata = CapabilityRegistry.all[capability]!;
      final packagePath =
          '${repoPackages.path}${Platform.pathSeparator}${metadata.packageName}';
      if (await Directory(packagePath).exists() &&
          !content.contains('${metadata.packageName}:')) {
        content = content.replaceFirst(
          RegExp(r'dependencies:\r?\n'),
          'dependencies:\n  ${metadata.packageName}:\n    path: ${packagePath.replaceAll('\\', '/')}\n',
        );
      }
    }
    await pubspec.writeAsString(content);
  }
}

String capabilityGlue(Set<Capability> capabilities) => [
      '// Generated by Dartloom. Keep capability wiring here.',
      for (final capability in capabilities)
        "export 'package:${CapabilityRegistry.all[capability]!.packageName}/${CapabilityRegistry.all[capability]!.packageName}.dart';",
      '',
    ].join('\n');

const _agents = '''# Agent Instructions

This project is managed by Dartloom.

## Before modifying code

1. Read `dartloom.yaml`.
2. Inspect existing capabilities before implementing infrastructure.
3. Reuse existing capability packages.
4. Application-specific code belongs in `lib/features`.
5. Shared application glue belongs in `lib/app`.
6. Do not duplicate capability implementations.

## Before finishing

Always run:

```bash
dart format .
flutter analyze
flutter test
```

## Build and release

Do not manually create release artifacts unless explicitly requested. Release artifacts are produced by Dartloom and GitHub Actions.
''';

const _ciWorkflow = '''name: CI
on: [push, pull_request]
jobs:
  check:
    uses: dartloom/dartloom/.github/workflows/flutter_ci.yml@main
''';

const _releaseWorkflow = '''name: Release
on:
  push:
    tags: ['v*']
  workflow_dispatch:
jobs:
  release:
    uses: dartloom/dartloom/.github/workflows/flutter_release.yml@main
    permissions:
      contents: write
''';
