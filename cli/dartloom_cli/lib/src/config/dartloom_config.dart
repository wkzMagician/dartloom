import 'dart:collection';

enum TargetPlatform { android, ios, windows, macos, linux, web }

extension TargetPlatformName on TargetPlatform {
  static TargetPlatform parse(String value) => TargetPlatform.values
      .firstWhere((platform) => platform.name == value.toLowerCase());
}

class DartloomConfig {
  DartloomConfig({
    required Set<TargetPlatform> platforms,
    required List<String> packages,
    Map<TargetPlatform, BuildPlatformConfig> build = const {},
  })  : platforms = UnmodifiableSetView({...platforms}),
        packages = UnmodifiableListView([...packages]),
        build = UnmodifiableMapView({...build});

  final Set<TargetPlatform> platforms;
  final List<String> packages;
  final Map<TargetPlatform, BuildPlatformConfig> build;

  String toYaml() {
    final out = StringBuffer('platforms:\n');
    for (final platform in TargetPlatform.values.where(platforms.contains)) {
      out.writeln('  - ${platform.name}');
    }
    out.writeln('\npackages:');
    for (final package in packages) {
      out.writeln('  - $package');
    }
    if (build.isNotEmpty) {
      out.writeln('\nbuild:');
      for (final platform in TargetPlatform.values.where(build.containsKey)) {
        final config = build[platform]!;
        out.writeln('  ${platform.name}:');
        if (config.postBuild.isNotEmpty) {
          out.writeln('    post_build:');
          for (final hook in config.postBuild) {
            out.writeln('      - $hook');
          }
        }
        if (config.nativeTargets.isNotEmpty) {
          out.writeln('    native_targets:');
          for (final target in config.nativeTargets) {
            out.writeln('      - $target');
          }
        }
      }
    }
    return out.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is DartloomConfig &&
      other.platforms.length == platforms.length &&
      other.platforms.containsAll(platforms) &&
      _listEquals(other.packages, packages) &&
      _mapEquals(other.build, build);

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(platforms),
        Object.hashAll(packages),
        Object.hashAll(
            build.entries.map((entry) => Object.hash(entry.key, entry.value))),
      );
}

class BuildPlatformConfig {
  const BuildPlatformConfig({
    this.postBuild = const [],
    this.nativeTargets = const [],
  });

  final List<String> postBuild;
  final List<String> nativeTargets;

  @override
  bool operator ==(Object other) =>
      other is BuildPlatformConfig &&
      _listEquals(other.postBuild, postBuild) &&
      _listEquals(other.nativeTargets, nativeTargets);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(postBuild),
        Object.hashAll(nativeTargets),
      );
}

bool _listEquals(List<String> a, List<String> b) =>
    a.length == b.length &&
    a.asMap().entries.every((entry) => entry.value == b[entry.key]);

bool _mapEquals(
  Map<TargetPlatform, BuildPlatformConfig> a,
  Map<TargetPlatform, BuildPlatformConfig> b,
) =>
    a.length == b.length &&
    a.entries.every((entry) => b[entry.key] == entry.value);
