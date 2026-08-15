import 'package:dartloom/src/capabilities/capability_registry.dart';
import 'package:dartloom/src/config/dartloom_config.dart';
import 'package:dartloom/src/templates/managed_templates.dart';
import 'package:test/test.dart';

void main() {
  test('singleton generation emits the filelock factory and service type', () {
    final config = DartloomConfig(
      app: const AppConfig(
        name: 'custom_singleton',
        organization: 'dev.example',
        description: '',
      ),
      platforms: {TargetPlatform.windows},
      capabilities: {
        Capability.singleton: const {
          'default': CapabilityInstanceConfig(implementation: 'filelock'),
        },
      },
    );

    expect(CapabilityRegistry.validationErrors(config), isEmpty);
    final generated = capabilityGlue(config);
    expect(generated, contains('DartloomRegistration<SingleInstanceService>'));
    expect(generated, contains("'filelock': (context)"));
    expect(generated, contains('FileLockSingleInstanceService'));
    expect(generated, contains('context.maybeGet<ResidentService>()'));
  });

  test('custom file replica generation delegates paths to an app factory', () {
    final config = DartloomConfig(
      app: const AppConfig(
        name: 'custom_replica',
        organization: 'dev.example',
        description: '',
      ),
      platforms: {TargetPlatform.windows},
      capabilities: {
        Capability.storage: const {
          'files': CapabilityInstanceConfig(
            implementation: 'app_file_replica',
            factory: 'createFileReplica',
          ),
        },
      },
    );

    expect(CapabilityRegistry.validationErrors(config), isEmpty);
    final generated = capabilityGlue(config);
    expect(generated, contains('DartloomRegistration<ReplicaStore>'));
    expect(generated, contains('factory: "createFileReplica"'));
    expect(generated, isNot(contains('FileDirectoryStore.open')));
    expect(generated, isNot(contains("options['path']")));
  });

  test('sync generation consumes the generic replica contract', () {
    final config = DartloomConfig(
      app: const AppConfig(
        name: 'custom_replica',
        organization: 'dev.example',
        description: '',
      ),
      platforms: {
        TargetPlatform.android,
        TargetPlatform.ios,
        TargetPlatform.windows,
      },
      capabilities: {
        Capability.settings: const {
          'default': CapabilityInstanceConfig(
            implementation: 'shared_preferences',
          ),
          'sync_secrets': CapabilityInstanceConfig(
            implementation: 'secure_storage',
          ),
        },
        Capability.storage: const {
          'files': CapabilityInstanceConfig(
            implementation: 'app_file_replica',
            factory: 'createFileReplica',
          ),
        },
        Capability.sync: {
          'default': CapabilityInstanceConfig(
            implementation: 'etag',
            replica: 'storage.files',
            backend: const AdapterConfig(
              implementation: 'webdav',
              options: {
                'root_path': 'CustomReplica',
                'connect_timeout': '10s',
                'request_timeout': '30s',
                'max_parallel_requests': 4,
                'create_missing_collections': true,
              },
            ),
            policy: CapabilityDefaults.forCapability(Capability.sync)
                .values
                .single
                .policy,
          ),
        },
      },
    );

    expect(CapabilityRegistry.validationErrors(config), isEmpty);
    final generated = capabilityGlue(config);
    expect(generated, contains('context.get<ReplicaStore>(name: replicaName)'));
    expect(generated, contains('ReplicaStoreLocalReplicaFactory(localStore)'));
    expect(
        generated, contains('if (scope != DartloomStartupScope.background)'));
    expect(generated,
        contains('final profileScope = context.get<SyncProfileScope>'));
    expect(generated, isNot(contains('ReplicaJsonStore')));
    expect(generated, isNot(contains('JsonLocalReplicaFactory')));
  });

  test('app file replicas require an explicit factory symbol', () {
    final config = DartloomConfig(
      app: const AppConfig(
        name: 'custom_replica',
        organization: 'dev.example',
        description: '',
      ),
      platforms: {TargetPlatform.windows},
      capabilities: {
        Capability.storage: const {
          'files': CapabilityInstanceConfig(
            implementation: 'app_file_replica',
          ),
        },
      },
    );

    expect(
      CapabilityRegistry.validationErrors(config),
      contains(contains('requires factory')),
    );
  });
}
