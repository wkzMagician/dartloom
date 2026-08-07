import '../config/dartloom_config.dart';

class ImplementationMetadata {
  const ImplementationMetadata({
    required this.id,
    required this.packageName,
    this.instanceNames,
    this.options = const {},
  });
  final String id;
  final String packageName;
  final Set<String>? instanceNames;
  final Map<String, String> options;
}

class CapabilityMetadata {
  const CapabilityMetadata({
    required this.capability,
    required this.contractPackage,
    required this.platforms,
    required this.implementations,
  });
  final Capability capability;
  final String contractPackage;
  final Set<TargetPlatform> platforms;
  final List<ImplementationMetadata> implementations;
}

class PackageMetadata {
  const PackageMetadata(this.name, this.version, this.path);
  final String name;
  final String version;
  final String path;
}

abstract final class CapabilityRegistry {
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
      contractPackage: 'dartloom_settings',
      platforms: _allPlatforms,
      implementations: [
        ImplementationMetadata(
          id: 'shared_preferences',
          packageName: 'dartloom_settings_shared_preferences',
        ),
        ImplementationMetadata(
          id: 'secure_storage',
          packageName: 'dartloom_settings_secure_storage',
        ),
      ],
    ),
    Capability.storage: CapabilityMetadata(
      capability: Capability.storage,
      contractPackage: 'dartloom_storage',
      platforms: _allPlatforms,
      implementations: [
        ImplementationMetadata(
          id: 'text_file',
          packageName: 'dartloom_storage_text_file',
          instanceNames: {'text'},
          options: {'path': 'dartloom/text'},
        ),
        ImplementationMetadata(
          id: 'json_file',
          packageName: 'dartloom_storage_json_file',
          instanceNames: {'json'},
          options: {'path': 'dartloom/data.json'},
        ),
        ImplementationMetadata(
          id: 'drift',
          packageName: 'dartloom_storage_drift',
          instanceNames: {'database'},
          options: {'name': 'dartloom'},
        ),
      ],
    ),
    Capability.logging: CapabilityMetadata(
      capability: Capability.logging,
      contractPackage: 'dartloom_logging',
      platforms: _allPlatforms,
      implementations: [
        ImplementationMetadata(
          id: 'logger',
          packageName: 'dartloom_logging_logger',
        ),
      ],
    ),
    Capability.autostart: CapabilityMetadata(
      capability: Capability.autostart,
      contractPackage: 'dartloom_autostart',
      platforms: {
        TargetPlatform.windows,
        TargetPlatform.macos,
        TargetPlatform.linux,
      },
      implementations: [
        ImplementationMetadata(
          id: 'launch_at_startup',
          packageName: 'dartloom_autostart_launch_at_startup',
        ),
      ],
    ),
    Capability.sync: CapabilityMetadata(
      capability: Capability.sync,
      contractPackage: 'dartloom_sync',
      platforms: _allPlatforms,
      implementations: [
        ImplementationMetadata(
          id: 'etag_object',
          packageName: 'dartloom_sync_etag',
        ),
      ],
    ),
    Capability.localization: CapabilityMetadata(
      capability: Capability.localization,
      contractPackage: 'dartloom_localization',
      platforms: _allPlatforms,
      implementations: [
        ImplementationMetadata(
          id: 'gen_l10n',
          packageName: 'dartloom_localization_gen_l10n',
        ),
      ],
    ),
    Capability.resident: CapabilityMetadata(
      capability: Capability.resident,
      contractPackage: 'dartloom_resident',
      platforms: {
        TargetPlatform.windows,
        TargetPlatform.macos,
        TargetPlatform.linux,
      },
      implementations: [
        ImplementationMetadata(
          id: 'tray',
          packageName: 'dartloom_resident_tray',
          options: {
            'icon_path': r'${RESIDENT_ICON_PATH}',
            'tooltip': 'Dartloom application',
          },
        ),
      ],
    ),
  };

  static const webDav = ImplementationMetadata(
    id: 'webdav',
    packageName: 'dartloom_sync_webdav',
    options: {
      'base_url': r'${WEBDAV_URL}',
      'root_path': 'Dartloom',
      'username': r'${WEBDAV_USERNAME}',
      'password': r'${WEBDAV_PASSWORD}',
    },
  );

  static Capability parse(String name) {
    try {
      return Capability.values.byName(name.toLowerCase());
    } on ArgumentError {
      throw ArgumentError.value(
        name,
        'capability',
        'Supported capabilities: ${Capability.values.map((e) => e.name).join(', ')}',
      );
    }
  }

  static ImplementationMetadata? implementation(
    Capability capability,
    String id,
  ) =>
      all[capability]!
          .implementations
          .where((implementation) => implementation.id == id)
          .firstOrNull;

  static List<PackageMetadata> packagesFor(DartloomConfig config) {
    final names = <String>{'dartloom_runtime'};
    for (final entry in config.capabilities.entries) {
      if (entry.value.isEmpty) continue;
      final metadata = all[entry.key]!;
      names.add(metadata.contractPackage);
      for (final instance in entry.value.values) {
        final adapter = implementation(entry.key, instance.implementation);
        if (adapter != null) names.add(adapter.packageName);
        if (entry.key == Capability.sync &&
            instance.backend?.implementation == 'webdav') {
          names.add(webDav.packageName);
        }
      }
    }
    return names.map(package).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  static PackageMetadata package(String name) {
    final version = name == 'dartloom_runtime'
        ? '^0.1.0'
        : all.values.any((value) => value.contractPackage == name)
            ? '^0.2.0'
            : '^0.1.0';
    return PackageMetadata(name, version, 'packages/$name');
  }

  static Set<String> get allPackageNames => {
        'dartloom_runtime',
        for (final capability in all.values) capability.contractPackage,
        for (final capability in all.values)
          for (final implementation in capability.implementations)
            implementation.packageName,
        webDav.packageName,
      };

  static List<String> validationErrors(DartloomConfig config) {
    final errors = <String>[];
    for (final capabilityEntry in config.capabilities.entries) {
      final metadata = all[capabilityEntry.key]!;
      if (config.platforms.intersection(metadata.platforms).isEmpty) {
        errors.add(
          '${capabilityEntry.key.name} does not support any enabled platform.',
        );
      }
      for (final instanceEntry in capabilityEntry.value.entries) {
        final instance = instanceEntry.value;
        if (instance.implementation == 'custom') {
          if (instance.factory == null || instance.factory!.isEmpty) {
            errors.add(
              '${capabilityEntry.key.name}.${instanceEntry.key} custom implementation requires factory.',
            );
          }
          continue;
        }
        final adapter = implementation(
          capabilityEntry.key,
          instance.implementation,
        );
        if (adapter == null) {
          errors.add(
            '${capabilityEntry.key.name}.${instanceEntry.key} has unknown implementation ${instance.implementation}.',
          );
          continue;
        }
        if (adapter.instanceNames != null &&
            !adapter.instanceNames!.contains(instanceEntry.key)) {
          errors.add(
            '${adapter.id} cannot implement ${capabilityEntry.key.name}.${instanceEntry.key}.',
          );
        }
        if (capabilityEntry.key == Capability.sync &&
            instance.backend?.implementation != 'webdav' &&
            instance.backend?.implementation != 'custom') {
          errors.add(
            'sync.${instanceEntry.key} has unknown backend ${instance.backend?.implementation}.',
          );
        }
      }
    }
    if (config.capabilities.containsKey(Capability.sync) &&
        !(config.capabilities[Capability.storage]?.containsKey('json') ??
            false)) {
      errors.add('sync requires storage.json for durable sync state.');
    }
    return errors;
  }
}
