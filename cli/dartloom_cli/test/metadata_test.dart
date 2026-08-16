import 'dart:io';

import 'package:dartloom_cli/dartloom_cli.dart';
import 'package:test/test.dart';

void main() {
  test('package metadata is complete and deterministic', () async {
    final catalog = await const PackageCatalog().load(Directory.current);
    expect(catalog, isNotEmpty);
    for (final package in catalog) {
      expect(package.name, startsWith('dartloom'));
      expect(package.description, isNotEmpty);
      expect(package.platforms, isNotEmpty);
    }
  });
}
