import 'dart:io';

import 'package:dartloom_cli/dartloom_cli.dart';
import 'package:dartloom_cli/src/commands/documentation.dart';
import 'package:test/test.dart';

void main() {
  test('adds the Dartloom badge once without changing README content',
      () async {
    final directory = await Directory.systemTemp.createTemp('dartloom-readme-');
    addTearDown(() => directory.delete(recursive: true));
    final readme = File('${directory.path}${Platform.pathSeparator}README.md');
    const content = '# My App\n\nA Flutter application.\n';
    await readme.writeAsString(content);

    await addDartloomReadmeAttribution(readme);
    final first = await readme.readAsString();
    expect(first, startsWith('$dartloomReadmeBadge\n\n'));
    expect(first, endsWith(content));

    await addDartloomReadmeAttribution(readme);
    expect(await readme.readAsString(), first);
  });

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
