import 'dart:collection';

enum TargetPlatform { android, ios, windows, macos, linux, web }

extension TargetPlatformName on TargetPlatform {
  static TargetPlatform parse(String value) => TargetPlatform.values
      .firstWhere((platform) => platform.name == value.toLowerCase());
}

class DartloomConfig {
  DartloomConfig(
      {required Set<TargetPlatform> platforms, required List<String> packages})
      : platforms = UnmodifiableSetView({...platforms}),
        packages = UnmodifiableListView([...packages]);

  final Set<TargetPlatform> platforms;
  final List<String> packages;

  String toYaml() {
    final out = StringBuffer('platforms:\n');
    for (final platform in TargetPlatform.values.where(platforms.contains)) {
      out.writeln('  - ${platform.name}');
    }
    out.writeln('\npackages:');
    for (final package in packages) {
      out.writeln('  - $package');
    }
    return out.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is DartloomConfig &&
      other.platforms.length == platforms.length &&
      other.platforms.containsAll(platforms) &&
      _listEquals(other.packages, packages);

  @override
  int get hashCode =>
      Object.hash(Object.hashAllUnordered(platforms), Object.hashAll(packages));
}

bool _listEquals(List<String> a, List<String> b) =>
    a.length == b.length &&
    a.asMap().entries.every((entry) => entry.value == b[entry.key]);
