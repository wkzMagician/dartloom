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
          !RegExp(r'^dartloom(?:_[a-z0-9_]+)?$').hasMatch(value)) {
        throw ConfigException('Package names must be Dartloom package names.');
      }
      if (!packages.contains(value)) packages.add(value);
    }
    return DartloomConfig(
      platforms: platforms,
      packages: packages,
      build: _build(document['build'], platforms),
    );
  }

  Map<TargetPlatform, BuildPlatformConfig> _build(
    Object? raw,
    Set<TargetPlatform> platforms,
  ) {
    if (raw == null) return const {};
    if (raw is! YamlMap) {
      throw ConfigException('build must be a map when provided.');
    }
    final result = <TargetPlatform, BuildPlatformConfig>{};
    for (final entry in raw.entries) {
      if (entry.key is! String || entry.value is! YamlMap) {
        throw ConfigException('build platform entries must be maps.');
      }
      final platform = _platform(entry.key as String);
      if (!platforms.contains(platform)) {
        throw ConfigException(
            'build.${platform.name} is not an enabled platform.');
      }
      final values = entry.value as YamlMap;
      final postBuild = _stringList(
          values['post_build'], 'build.${platform.name}.post_build');
      final nativeTargets = _stringList(
        values['native_targets'],
        'build.${platform.name}.native_targets',
      );
      if (postBuild.isEmpty && nativeTargets.isNotEmpty) {
        throw ConfigException(
          'build.${platform.name}.native_targets requires post_build.',
        );
      }
      if (postBuild.isNotEmpty || nativeTargets.isNotEmpty) {
        result[platform] = BuildPlatformConfig(
          postBuild: postBuild,
          nativeTargets: nativeTargets,
        );
      }
    }
    return result;
  }

  TargetPlatform _platform(String value) {
    try {
      return TargetPlatformName.parse(value);
    } on StateError {
      throw ConfigException('Unknown Flutter platform: $value.');
    }
  }

  List<String> _stringList(Object? value, String field) {
    if (value == null) return const [];
    if (value is! YamlList ||
        value.any((item) => item is! String || item.isEmpty)) {
      throw ConfigException('$field must be a list of non-empty strings.');
    }
    return List<String>.unmodifiable(value.cast<String>());
  }

  Future<void> save(Directory project, DartloomConfig config) async {
    final configFile = file(project);
    await configFile.parent.create(recursive: true);
    await configFile.writeAsString(config.toYaml());
  }
}
