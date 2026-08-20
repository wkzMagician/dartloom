import 'package:dartloom_cli/src/commands/workflow_templates.dart';
import 'package:dartloom_cli/src/config/dartloom_config.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('Workflow templates', () {
    test('cloudBuildWorkflow is valid YAML and does not use matrix in job if',
        () {
      final yamlContent = cloudBuildWorkflow();
      final parsed = loadYaml(yamlContent) as YamlMap;
      expect(parsed['name'], 'Dartloom Cloud Build');
      expect(parsed['on']['workflow_dispatch'], isNotNull);

      // Verify jobs
      final jobs = parsed['jobs'] as YamlMap;
      expect(jobs.containsKey('matrix'), isTrue);
      expect(jobs.containsKey('build'), isTrue);

      // Job-level 'if' must not reference matrix
      for (final entry in jobs.entries) {
        final job = entry.value as YamlMap;
        if (job.containsKey('if')) {
          expect(job['if'].toString(), isNot(contains('matrix.')));
        }
      }
    });

    test('ciWorkflow is valid YAML', () {
      final parsed = loadYaml(ciWorkflow()) as YamlMap;
      expect(parsed['name'], 'CI');
      expect(parsed['jobs'], isNotNull);
    });

    test('releaseWorkflow is valid YAML', () {
      final config = DartloomConfig(
        platforms: {TargetPlatform.android, TargetPlatform.ios},
        packages: [],
      );
      final parsed = loadYaml(releaseWorkflow(config)) as YamlMap;
      expect(parsed['name'], 'Release');
      expect(parsed['jobs'], isNotNull);
    });

    test('release artifacts are packaged and named for the project', () {
      final workflow = releaseWorkflow(
        DartloomConfig(
          platforms: TargetPlatform.values.toSet(),
          packages: [],
        ),
        appName: 'mind_bubble',
      );
      expect(workflow, contains('dist/mind_bubble-android.apk'));
      expect(workflow, contains('dist/mind_bubble-android.aab'));
      expect(workflow, contains('dist/mind_bubble-ios.ipa'));
      expect(workflow, contains('dist/mind_bubble-macos.zip'));
      expect(workflow, contains('dist/mind_bubble-linux-x64.tar.gz'));
      expect(workflow, contains('dist/mind_bubble-web.zip'));
      expect(workflow, contains('find downloaded_artifacts'));
      expect(workflow, contains("! -name 'dartloom-build.json'"));
      expect(workflow, isNot(contains('build/app/outputs/**')));
    });

    test('installer uses the project executable name', () {
      final installer =
          windowsInstaller(appName: 'mind_bubble', appVersion: '0.4.5');
      expect(installer, contains('#define MyAppName "Mind Bubble"'));
      expect(installer, contains('#define MyAppVersion "0.4.5"'));
      expect(installer, contains('#define MyAppExeName "mind_bubble.exe"'));
      expect(installer, contains('OutputBaseFilename=mind_bubble-'));
    });
  });
}
