import '../config/dartloom_config.dart';

class CapabilityMetadata {
  const CapabilityMetadata(
      {required this.capability,
      required this.packageName,
      required this.brick,
      required this.platforms});
  final Capability capability;
  final String packageName;
  final String brick;
  final Set<TargetPlatform> platforms;
}

class CapabilityRegistry {
  static const _allPlatforms = {
    TargetPlatform.android,
    TargetPlatform.ios,
    TargetPlatform.windows,
    TargetPlatform.macos,
    TargetPlatform.linux,
    TargetPlatform.web,
  };

  static const all = <Capability, CapabilityMetadata>{
    Capability.settings: CapabilityMetadata(
        capability: Capability.settings,
        packageName: 'dartloom_settings',
        brick: 'capability_settings',
        platforms: _allPlatforms),
    Capability.storage: CapabilityMetadata(
        capability: Capability.storage,
        packageName: 'dartloom_storage',
        brick: 'capability_storage',
        platforms: _allPlatforms),
    Capability.logging: CapabilityMetadata(
        capability: Capability.logging,
        packageName: 'dartloom_logging',
        brick: 'capability_logging',
        platforms: _allPlatforms),
    Capability.autostart: CapabilityMetadata(
        capability: Capability.autostart,
        packageName: 'dartloom_autostart',
        brick: 'capability_autostart',
        platforms: {
          TargetPlatform.windows,
          TargetPlatform.macos,
          TargetPlatform.linux
        }),
    Capability.sync: CapabilityMetadata(
        capability: Capability.sync,
        packageName: 'dartloom_sync',
        brick: 'capability_sync',
        platforms: _allPlatforms),
  };

  static Capability parse(String name) {
    try {
      return Capability.values.byName(name.toLowerCase());
    } on ArgumentError {
      throw ArgumentError.value(name, 'capability',
          'Supported capabilities: ${Capability.values.map((e) => e.name).join(', ')}');
    }
  }
}
