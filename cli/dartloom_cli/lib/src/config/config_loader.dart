import 'dart:io';

import 'package:yaml/yaml.dart';

import 'dartloom_config.dart';

class ConfigException implements Exception {
  ConfigException(this.message);
  final String message;
  @override
  String toString() => 'Dartloom configuration error: $message';
}

class ConfigLoader {
  const ConfigLoader();

  File file(Directory project) => File(
      '${project.path}${Platform.pathSeparator}.dartloom${Platform.pathSeparator}project.yaml');

  Future<DartloomConfig> load(Directory project) async {
    final configFile = file(project);
    if (!await configFile.exists()) {
      throw ConfigException('${configFile.path} was not found.');
    }
    return parse(await configFile.readAsString());
  }

  DartloomConfig parse(String source) {
    final document = loadYaml(source);
    if (document is! YamlMap) {
      throw ConfigException('project.yaml must be a map.');
    }
    final rawPlatforms = document['platforms'];
    final rawPackages = document['packages'];
    if (rawPlatforms is! YamlList || rawPackages is! YamlList) {
      throw ConfigException('platforms and packages must be lists.');
    }
    final platforms = <TargetPlatform>{};
    for (final value in rawPlatforms) {
      if (value is! String) {
        throw ConfigException('platform names must be strings.');
      }
      try {
        platforms.add(TargetPlatformName.parse(value));
      } on StateError {
        throw ConfigException('Unknown Flutter platform: $value.');
      }
    }
    final packages = <String>[];
    for (final value in rawPackages) {
      if (value is! String ||
          !RegExp(r'^dartloom_[a-z0-9_]+$').hasMatch(value)) {
        throw ConfigException('Package names must be Dartloom package names.');
      }
      if (!packages.contains(value)) packages.add(value);
    }
    return DartloomConfig(platforms: platforms, packages: packages);
  }

  Future<void> save(Directory project, DartloomConfig config) async {
    final configFile = file(project);
    await configFile.parent.create(recursive: true);
    await configFile.writeAsString(config.toYaml());
  }
}
