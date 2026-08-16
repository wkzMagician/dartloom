import 'dart:io';

import '../config/config_loader.dart';
import '../config/dartloom_config.dart';
import '../process/process_runner.dart';
import '../templates/managed_templates.dart';
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
      required Set<Capability> capabilities,
      CapabilitySource capabilitySource = CapabilitySource.github}) async {
    if (!RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(name)) {
      throw CommandFailure(
          'Invalid app name "$name". Use lowercase letters, digits, hyphens, and underscores.');
    }
    final projectName = name.replaceAll('-', '_');
    final packageName = name.replaceAll('_', '-');
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
          '--project-name=$projectName',
          '--platforms=$flutterPlatforms',
          name
        ],
        parent);
    final configuredCapabilities =
        <Capability, Map<String, CapabilityInstanceConfig>>{
      for (final capability in capabilities)
        capability: {
          ...CapabilityDefaults.forCapability(
            capability,
            platforms: platforms,
          ),
        },
    };
    if (capabilities.contains(Capability.sync)) {
      configuredCapabilities.putIfAbsent(
        Capability.storage,
        () => {
          ...CapabilityDefaults.forCapability(
            Capability.storage,
            platforms: platforms,
          ),
        },
      );
    }
    final config = DartloomConfig(
        app: AppConfig(
            name: projectName,
            packageName: packageName,
            organization: organization,
            description: '$packageName application'),
        platforms: platforms,
        capabilities: configuredCapabilities,
        capabilitySource: capabilitySource);
    await _loader.save(project, config);
    await _writeManagedFiles(project, config);
    await runRequired(
        runner, executableFor('flutter'), ['pub', 'get'], project);
    if (config.enabledCapabilities.contains(Capability.localization)) {
      await runRequired(
        runner,
        executableFor('flutter'),
        ['gen-l10n'],
        project,
      );
    }
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
    final hasAppOwnedReplica = config.capabilities[Capability.storage]?.values
            .any((value) => value.implementation == 'app_object_store') ??
        false;
    final replicaFactoryImport = hasAppOwnedReplica
        ? "import 'features/dartloom_replica_factory.dart';\n"
        : '';
    final bootstrapArguments = hasAppOwnedReplica
        ? 'customFactories: dartloomApplicationFactories'
        : '';
    await File('${project.path}${separator}lib${separator}main.dart').writeAsString(
        "import 'package:flutter/widgets.dart';\n\nimport 'app/app.dart';\nimport 'capabilities/bootstrap.dart';\n$replicaFactoryImport\nFuture<void> main() async {\n  await bootstrapDartloom($bootstrapArguments);\n  runApp(const DartloomApp());\n}\n");
    await File(
            '${project.path}${separator}lib${separator}app${separator}app.dart')
        .writeAsString(appShell(config));
    await File(
            '${project.path}${separator}lib${separator}app${separator}router.dart')
        .writeAsString(
            "import 'package:flutter/widgets.dart';\n\nRoute<dynamic> onGenerateRoute(RouteSettings settings) =>\n    PageRouteBuilder<void>(pageBuilder: (_, _, _) => const Placeholder());\n");
    await File('${project.path}${separator}test${separator}widget_test.dart')
        .writeAsString(
      "import 'package:flutter_test/flutter_test.dart';\n\nimport 'package:${config.app.name}/app/app.dart';\n\nvoid main() {\n  testWidgets('shows the Dartloom app shell', (tester) async {\n    await tester.pumpWidget(const DartloomApp());\n    expect(find.text('Dartloom app'), findsOneWidget);\n  });\n}\n",
    );
    await File('${project.path}${separator}AGENTS.md')
        .writeAsString(agentInstructions(config));
    await File(
            '${project.path}$separator.github${separator}workflows${separator}ci.yml')
        .writeAsString(ciWorkflow);
    await File(
            '${project.path}$separator.github${separator}workflows${separator}release.yml')
        .writeAsString(releaseWorkflow(config));
    await File(
            '${project.path}${separator}lib${separator}capabilities${separator}capabilities.dart')
        .writeAsString(capabilityGlue(config));
    await File(
            '${project.path}${separator}lib${separator}capabilities${separator}bootstrap.dart')
        .writeAsString(capabilityBootstrap);
    if (hasAppOwnedReplica) {
      await File(
        '${project.path}${separator}lib${separator}features${separator}dartloom_replica_factory.dart',
      ).writeAsString(appOwnedReplicaFactory);
    }
    if (config.enabledCapabilities.contains(Capability.localization)) {
      await Directory('${project.path}${separator}lib${separator}l10n')
          .create(recursive: true);
      await File('${project.path}${separator}l10n.yaml')
          .writeAsString(l10nYaml);
      await File(
        '${project.path}${separator}lib${separator}l10n${separator}app_en.arb',
      ).writeAsString(appEnArb);
      await File(
        '${project.path}${separator}lib${separator}l10n${separator}app_zh.arb',
      ).writeAsString(appZhArb);
    }
    await _addPackageDependencies(project, config);
  }

  Future<void> _addPackageDependencies(
      Directory project, DartloomConfig config) async {
    final pubspec =
        File('${project.path}${Platform.pathSeparator}pubspec.yaml');
    var content = await pubspec.readAsString();
    content = rewriteDartloomDependencies(
      content,
      config,
      packagesDirectory: localPackagesDirectory(project),
    );
    if (config.enabledCapabilities.contains(Capability.localization) &&
        !RegExp(r'^  generate: true$', multiLine: true).hasMatch(content)) {
      content = content.replaceFirst(
        RegExp(r'^flutter:\r?$', multiLine: true),
        'flutter:\n  generate: true',
      );
    }
    await pubspec.writeAsString(content);
  }
}
