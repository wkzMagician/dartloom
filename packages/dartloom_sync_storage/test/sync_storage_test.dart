import 'package:dartloom_settings/dartloom_settings.dart';
import 'package:dartloom_sync/dartloom_sync.dart';
import 'package:dartloom_sync_storage/dartloom_sync_storage.dart';
import 'package:test/test.dart';

void main() {
  test('profiles select remotes without creating local storage namespaces',
      () async {
    final metadata = MemorySettingsStore();
    final secure = MemorySettingsStore();
    final scope = await SyncProfileScope.open(metadata, 'default');
    final profiles = SettingsSyncProfileRepository(
      instanceName: 'default',
      metadata: metadata,
      secretsStore: secure,
      scope: scope,
    );
    final second = await profiles.save(const SyncProfileDraft(
      label: 'Second',
      backend: 'webdav',
      secrets: {'password': 'secret'},
    ));
    await profiles.activate(second.id);
    expect(scope.activeProfileId, second.id);
    expect((await profiles.list()).toString(), isNot(contains('secret')));
    expect(await profiles.secrets(second.id), {'password': 'secret'});
  });

  test('reconciliation state is stored outside the replica', () async {
    final settings = MemorySettingsStore();
    final state = SettingsReconciliationStateRepository(
      settings,
      instanceName: 'default',
    );
    await state.save('profile', {
      'fingerprint': 'v4',
      'records': {
        'todo-1': {'baseHash': 'hash'}
      },
    });

    expect((await state.load('profile'))['fingerprint'], 'v4');
    expect(await settings.read('sync.default.v4.state.profile'), isA<String>());
  });
}
