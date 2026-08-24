import 'dart:io';

import 'package:dartloom_cli/dartloom_cli.dart';
import 'package:dartloom_cli/src/commands/documentation.dart';
import 'package:test/test.dart';

void main() {
  test('documents the Dartloom link and library in generated project guidance',
      () async {
    final directory = await Directory.systemTemp.createTemp('dartloom-docs-');
    addTearDown(() => directory.delete(recursive: true));
    final agents = File('${directory.path}${Platform.pathSeparator}AGENTS.md');
    final result = await updateAgents(
      agents,
      DartloomConfig(
        platforms: {TargetPlatform.windows},
        packages: [],
      ),
      const PackageCatalog(),
    );

    expect(result, contains('https://github.com/wkzMagician/dartloom'));
    expect(result, contains('Each subproject README.md'));
    expect(result, contains('which Dartloom library it uses'));
  });
}
