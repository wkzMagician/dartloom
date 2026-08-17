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
  });
}
