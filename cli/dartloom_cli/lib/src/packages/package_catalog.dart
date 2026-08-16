import 'dart:io';

import 'package:yaml/yaml.dart';

import '../commands/command_support.dart';
import '../config/dartloom_config.dart';

class DartloomExport {
  const DartloomExport(
      {required this.symbol, required this.kind, required this.description});
  final String symbol;
  final String kind;
  final String description;
}

class DartloomPackage {
  const DartloomPackage(
      {required this.name,
      required this.displayName,
      required this.description,
      required this.platforms,
      required this.exports});
  final String name;
  final String displayName;
  final String description;
  final Set<TargetPlatform> platforms;
  final List<DartloomExport> exports;
}

class PackageCatalog {
  const PackageCatalog();

  Future<List<DartloomPackage>> load(Directory project) async {
    final root = localPackagesDirectory(project);
    if (root == null) return const [];
    final packages = <DartloomPackage>[];
    for (final directory in root.listSync().whereType<Directory>()) {
      final metadata = File(
          '${directory.path}${Platform.pathSeparator}tool${Platform.pathSeparator}dartloom-package.yaml');
      if (!await metadata.exists()) continue;
      packages.add(_parse(await metadata.readAsString(), metadata.path));
    }
    packages.sort((a, b) => a.name.compareTo(b.name));
    return packages;
  }

  DartloomPackage _parse(String source, String path) {
    final root = loadYaml(source);
    if (root is! YamlMap) {
      throw CommandFailure('$path must contain a YAML map.');
    }
    String required(String key) {
      final value = root[key];
      if (value is! String || value.trim().isEmpty) {
        throw CommandFailure('$path requires $key.');
      }
      return value;
    }

    final platformValues = root['platforms'];
    if (platformValues is! YamlList) {
      throw CommandFailure('$path requires platforms.');
    }
    final platforms = <TargetPlatform>{};
    for (final value in platformValues) {
      if (value is! String) {
        throw CommandFailure('$path has an invalid platform.');
      }
      try {
        platforms.add(TargetPlatformName.parse(value));
      } on StateError {
        throw CommandFailure('$path has an unknown platform: $value.');
      }
    }
    final rawExports = root['exports'];
    if (rawExports is! YamlList) {
      throw CommandFailure('$path requires exports.');
    }
    final exports = <DartloomExport>[];
    for (final item in rawExports) {
      if (item is! YamlMap ||
          item['symbol'] is! String ||
          item['kind'] is! String ||
          item['description'] is! String) {
        throw CommandFailure('$path has an invalid export entry.');
      }
      exports.add(DartloomExport(
          symbol: item['symbol'] as String,
          kind: item['kind'] as String,
          description: item['description'] as String));
    }
    return DartloomPackage(
        name: required('package'),
        displayName: required('display_name'),
        description: required('description'),
        platforms: platforms,
        exports: exports);
  }
}
