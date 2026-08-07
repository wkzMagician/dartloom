enum TargetPlatform { android, ios, windows, macos, linux, web }

/// Where an application's Dartloom capability dependencies are resolved.
enum CapabilitySource { github, pub }

enum Capability {
  settings,
  storage,
  logging,
  autostart,
  sync,
  localization,
  resident,
}

extension TargetPlatformName on TargetPlatform {
  String get configName => name;

  static TargetPlatform parse(String value) =>
      TargetPlatform.values.byName(value);
}

class AppConfig {
  const AppConfig(
      {required this.name,
      required this.organization,
      required this.description});

  final String name;
  final String organization;
  final String description;
}

class DartloomConfig {
  const DartloomConfig({
    required this.app,
    required this.platforms,
    required this.capabilities,
    this.capabilitySource = CapabilitySource.github,
    this.githubRelease = true,
  });

  final AppConfig app;
  final Set<TargetPlatform> platforms;
  final Set<Capability> capabilities;
  final CapabilitySource capabilitySource;
  final bool githubRelease;

  DartloomConfig copyWith({
    Set<Capability>? capabilities,
    CapabilitySource? capabilitySource,
  }) =>
      DartloomConfig(
        app: app,
        platforms: platforms,
        capabilities: capabilities ?? this.capabilities,
        capabilitySource: capabilitySource ?? this.capabilitySource,
        githubRelease: githubRelease,
      );

  String toYaml() {
    String flags<T>(Iterable<T> values, Iterable<T> all) => all
        .map((item) =>
            '  ${item is TargetPlatform ? item.name : (item as Capability).name}: ${values.contains(item)}')
        .join('\n');
    return '''schema_version: 1

app:
  name: ${app.name}
  organization: ${app.organization}
  description: ${app.description}

platforms:
${flags(platforms, TargetPlatform.values)}

capabilities:
${flags(capabilities, Capability.values)}

sources:
  capabilities: ${capabilitySource.name}

release:
  github: $githubRelease
  android:
    apk: true
    appbundle: true
  windows:
    zip: true
  macos:
    zip: true
  linux:
    archive: true
  web:
    archive: true
''';
  }
}
