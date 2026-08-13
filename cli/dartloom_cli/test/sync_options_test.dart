import 'package:dartloom/dartloom.dart';
import 'package:test/test.dart';

void main() {
  test('duration and percentage fields use human-readable values', () {
    expect(tryParseDuration('250ms'), const Duration(milliseconds: 250));
    expect(tryParseDuration('2h'), const Duration(hours: 2));
    expect(tryParsePercentage('20%'), closeTo(.2, .0001));
  });

  test('platform overrides deep merge without replacing global groups', () {
    final defaults = SyncOptionSchemas.policy.defaults();
    final resolved = deepMerge(defaults, {
      'discovery': {'poll_interval': '30s'},
    });
    expect(readPath(resolved, 'discovery.poll_interval'), '30s');
    expect(readPath(resolved, 'discovery.remote_changes'), 'auto');
  });

  test('rejects WebDAV push and unsupported desktop background', () {
    final policy = SyncOptionSchemas.policy.defaults();
    setPath(policy, 'discovery.remote_changes', 'push');
    policy['platforms'] = {
      'windows': {
        'background': {'enabled': true},
      },
    };
    final instance = CapabilityInstanceConfig(
      implementation: 'etag',
      replica: 'storage.json',
      backend: const AdapterConfig(
        implementation: 'webdav',
        options: {
          'root_path': 'Dartloom',
          'connect_timeout': '10s',
          'request_timeout': '30s',
          'max_parallel_requests': 4,
          'create_missing_collections': true,
        },
      ),
      policy: policy,
    );
    final errors = SyncOptionSchemas.validateSync(
      instance,
      {TargetPlatform.windows},
      context: 'sync.default',
    );
    expect(
        errors.join(' '), contains('cannot use discovery.remote_changes=push'));
    expect(errors.join(' '), contains('background is unsupported'));
  });

  test('rejects Android background intervals below fifteen minutes', () {
    final instance = CapabilityInstanceConfig(
      implementation: 'etag',
      replica: 'storage.json',
      backend: AdapterConfig(
        implementation: 'webdav',
        options: SyncOptionSchemas.webDav.defaults(),
      ),
      policy: deepMerge(SyncOptionSchemas.policy.defaults(), {
        'platforms': {
          'android': {
            'background': {
              ...SyncOptionSchemas.background.defaults(),
              'enabled': true,
              'periodic_interval': '5m',
            },
          },
        },
      }),
    );
    final errors = SyncOptionSchemas.validateSync(
      instance,
      {TargetPlatform.android},
      context: 'sync.default',
    );
    expect(errors.join(' '), contains('periodic_interval'));
  });
}
