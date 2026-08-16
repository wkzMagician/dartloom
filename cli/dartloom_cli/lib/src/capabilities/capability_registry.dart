import '../config/dartloom_config.dart';
import '../config/option_schema.dart';

class ImplementationMetadata {
  const ImplementationMetadata({
    required this.id,
    required this.packageName,
    this.instanceNames,
    this.platforms,
    this.options = const {},
    this.optionSchema,
  });
  final String id;
  final String packageName;
  final Set<String>? instanceNames;
  final Set<TargetPlatform>? platforms;
  final Map<String, String> options;
  final OptionSchema? optionSchema;
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
          platforms: {
            TargetPlatform.android,
            TargetPlatform.ios,
            TargetPlatform.windows,
            TargetPlatform.macos,
            TargetPlatform.linux,
          },
          options: {'path': 'dartloom/text'},
        ),
        ImplementationMetadata(
          id: 'json_file',
          packageName: 'dartloom_storage_json_file',
          instanceNames: {'json'},
          platforms: {
            TargetPlatform.android,
            TargetPlatform.ios,
            TargetPlatform.windows,
            TargetPlatform.macos,
            TargetPlatform.linux,
          },
          options: {'path': 'dartloom/data.json'},
        ),
        ImplementationMetadata(
          id: 'json_directory',
          packageName: 'dartloom_storage_json_file',
          instanceNames: {'json'},
          platforms: {
            TargetPlatform.android,
            TargetPlatform.ios,
            TargetPlatform.windows,
            TargetPlatform.macos,
            TargetPlatform.linux,
          },
          options: {'path': 'Dartloom'},
        ),
        ImplementationMetadata(
          id: 'app_file_replica',
          packageName: 'dartloom_storage_file',
          platforms: {
            TargetPlatform.android,
            TargetPlatform.ios,
            TargetPlatform.windows,
            TargetPlatform.macos,
            TargetPlatform.linux,
          },
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
          platforms: {
            TargetPlatform.windows,
            TargetPlatform.macos,
            TargetPlatform.linux,
          },
        ),
      ],
    ),
    Capability.sync: CapabilityMetadata(
      capability: Capability.sync,
      contractPackage: 'dartloom_sync',
      platforms: _allPlatforms,
      implementations: [
        ImplementationMetadata(
          id: 'etag',
          packageName: 'dartloom_sync_etag',
          optionSchema: SyncOptionSchemas.policy,
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
          platforms: {
            TargetPlatform.windows,
            TargetPlatform.macos,
            TargetPlatform.linux,
          },
          options: {
            'icon_path': r'${RESIDENT_ICON_PATH}',
            'tooltip': 'Dartloom application',
          },
        ),
      ],
    ),
    Capability.messaging: CapabilityMetadata(
      capability: Capability.messaging,
      contractPackage: 'dartloom_messaging',
      platforms: {
        TargetPlatform.android,
        TargetPlatform.windows,
        TargetPlatform.macos,
        TargetPlatform.linux,
      },
      implementations: [
        ImplementationMetadata(
          id: 'memory_messaging',
          packageName: 'dartloom_messaging',
        ),
      ],
    ),
    Capability.pairing: CapabilityMetadata(
      capability: Capability.pairing,
      contractPackage: 'dartloom_pairing',
      platforms: {
        TargetPlatform.android,
        TargetPlatform.windows,
        TargetPlatform.macos,
        TargetPlatform.linux,
        TargetPlatform.web,
      },
      implementations: [
        ImplementationMetadata(
          id: 'memory_pairing',
          packageName: 'dartloom_pairing',
          platforms: {
            TargetPlatform.android,
            TargetPlatform.windows,
            TargetPlatform.macos,
            TargetPlatform.linux,
          },
        ),
        ImplementationMetadata(
          id: 'relay_pairing',
          packageName: 'dartloom_pairing',
          platforms: {TargetPlatform.web},
        ),
      ],
    ),
    Capability.singleton: CapabilityMetadata(
      capability: Capability.singleton,
      contractPackage: 'dartloom_singleton',
      platforms: {
        TargetPlatform.windows,
        TargetPlatform.macos,
        TargetPlatform.linux,
      },
      implementations: [
        ImplementationMetadata(
          id: 'socket',
          packageName: 'dartloom_singleton_socket',
          platforms: {
            TargetPlatform.windows,
            TargetPlatform.macos,
            TargetPlatform.linux,
          },
        ),
      ],
    ),
  };

  static const webDav = ImplementationMetadata(
    id: 'webdav',
    packageName: 'dartloom_sync_webdav',
    options: {'root_path': 'Dartloom'},
    optionSchema: SyncOptionSchemas.webDav,
  );

  static const syncBackends = <ImplementationMetadata>[webDav];

  static ImplementationMetadata? syncBackend(String id) =>
      syncBackends.where((backend) => backend.id == id).firstOrNull;

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
        if (entry.key == Capability.storage &&
            instance.implementation == 'app_file_replica') {
          names.add('dartloom_storage_json_file');
        }
        if (entry.key == Capability.sync &&
            instance.backend?.implementation == 'webdav') {
          names
            ..add(webDav.packageName)
            ..add('dartloom_sync_storage')
            ..add('dartloom_sync_flutter')
            ..add('dartloom_sync_workmanager');
        }
      }
    }
    return names.map(package).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  static PackageMetadata package(String name) {
    const versions = <String, String>{
      'dartloom_runtime': '^0.1.0',
      'dartloom_resident': '^0.3.0',
      'dartloom_resident_tray': '^0.2.1',
      'dartloom_sync': '^0.3.0',
      'dartloom_sync_etag': '^0.2.0',
      'dartloom_sync_webdav': '^0.2.0',
      'dartloom_messaging': '^0.1.0',
      'dartloom_pairing': '^0.1.0',
      'dartloom_singleton': '^0.1.0',
      'dartloom_singleton_socket': '^0.1.0',
    };
    final version = versions[name] ??
        (all.values.any((value) => value.contractPackage == name)
            ? '^0.2.0'
            : '^0.1.0');
    return PackageMetadata(name, version, 'packages/$name');
  }

  static Set<String> get allPackageNames => {
        'dartloom_runtime',
        for (final capability in all.values) capability.contractPackage,
        for (final capability in all.values)
          for (final implementation in capability.implementations)
            implementation.packageName,
        for (final backend in syncBackends) backend.packageName,
        'dartloom_sync_storage',
        'dartloom_sync_flutter',
        'dartloom_sync_workmanager',
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
        final configuredPlatforms = instance.platforms;
        if (configuredPlatforms != null) {
          final outsideApp = configuredPlatforms.difference(config.platforms);
          if (outsideApp.isNotEmpty) {
            errors.add(
              '${capabilityEntry.key.name}.${instanceEntry.key} configures disabled app platforms: '
              '${outsideApp.map((platform) => platform.name).join(', ')}.',
            );
          }
        }
        if (instance.implementation == 'custom' ||
            instance.implementation == 'app_file_replica') {
          if (instance.factory == null || instance.factory!.isEmpty) {
            errors.add(
              '${capabilityEntry.key.name}.${instanceEntry.key} '
              '${instance.implementation} implementation requires factory.',
            );
          }
          if (instance.implementation == 'custom') continue;
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
        if (configuredPlatforms != null) {
          final unsupported = configuredPlatforms.difference(
            adapter.platforms ?? metadata.platforms,
          );
          if (unsupported.isNotEmpty) {
            errors.add(
              '${capabilityEntry.key.name}.${instanceEntry.key} implementation '
              '${instance.implementation} does not support: '
              '${unsupported.map((platform) => platform.name).join(', ')}.',
            );
          }
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
        if (capabilityEntry.key == Capability.sync) {
          errors.addAll(SyncOptionSchemas.validateSync(
            instance,
            config.platforms,
            context: 'sync.${instanceEntry.key}',
          ));
        }
      }
    }
    if (config.capabilities.containsKey(Capability.sync) &&
        !(config.capabilities[Capability.settings]
                ?.containsKey('sync_secrets') ??
            false)) {
      errors.add('sync requires settings.sync_secrets using secure_storage.');
    }
    final secretsSettings =
        config.capabilities[Capability.settings]?['sync_secrets'];
    if (config.capabilities.containsKey(Capability.sync) &&
        secretsSettings != null &&
        secretsSettings.implementation != 'secure_storage') {
      errors.add('settings.sync_secrets must use secure_storage.');
    }
    final storeOwners = <String, String>{};
    for (final instance in config.capabilities[Capability.sync]?.entries ??
        const <MapEntry<String, CapabilityInstanceConfig>>[]) {
      final store = instance.value.replica;
      if (store == null) continue;
      final previous = storeOwners[store];
      if (previous != null) {
        errors.add(
            '$store is assigned to both sync.$previous and sync.${instance.key}.');
      } else {
        storeOwners[store] = instance.key;
      }
    }
    return errors;
  }
}
