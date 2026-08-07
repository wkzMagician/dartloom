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

  Future<DartloomConfig> load(Directory project) async {
    final file = File('${project.path}${Platform.pathSeparator}dartloom.yaml');
    if (!await file.exists()) {
      throw ConfigException('dartloom.yaml was not found in ${project.path}.');
    }
    final root = loadYaml(await file.readAsString());
    if (root is! YamlMap || root['schema_version'] != 1) {
      throw ConfigException('schema_version: 1 is required.');
    }
    final app = root['app'];
    if (app is! YamlMap ||
        app['name'] is! String ||
        app['organization'] is! String) {
      throw ConfigException(
          'app.name and app.organization are required strings.');
    }
    Set<T> enabled<T extends Enum>(Object? section, List<T> values) {
      if (section is! YamlMap) {
        throw ConfigException('A configuration section is missing.');
      }
      return values.where((value) => section[value.name] == true).toSet();
    }

    return DartloomConfig(
      app: AppConfig(
          name: app['name'] as String,
          organization: app['organization'] as String,
          description: app['description'] as String? ?? ''),
      platforms: enabled(root['platforms'], TargetPlatform.values),
      capabilities: enabled(root['capabilities'], Capability.values),
      capabilitySource: _capabilitySource(root['sources']),
      githubRelease: (root['release'] as YamlMap?)?['github'] != false,
    );
  }

  CapabilitySource _capabilitySource(Object? sources) {
    final raw = (sources as YamlMap?)?['capabilities'];
    if (raw == null) return CapabilitySource.github;
    if (raw is! String) {
      throw ConfigException('sources.capabilities must be github or pub.');
    }
    try {
      return CapabilitySource.values.byName(raw);
    } on ArgumentError {
      throw ConfigException('sources.capabilities must be github or pub.');
    }
  }

  Future<void> save(Directory project, DartloomConfig config) =>
      File('${project.path}${Platform.pathSeparator}dartloom.yaml')
          .writeAsString(config.toYaml());
}
