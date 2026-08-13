import 'package:dartloom_settings/dartloom_settings.dart';
import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:dartloom_sync/dartloom_sync.dart';
import 'package:dartloom_sync_storage/dartloom_sync_storage.dart';
import 'package:test/test.dart';

void main() {
  test('profiles isolate JSON keys and redact secrets', () async {
    final metadata = MemorySettingsStore();
    final secure = MemorySettingsStore();
    final scope = await SyncProfileScope.open(metadata, 'default');
    final raw = MemoryJsonStore();
    final store = await ProfileScopedJsonStore.open(raw, scope);
    final profiles = SettingsSyncProfileRepository(
      instanceName: 'default',
      metadata: metadata,
      secretsStore: secure,
      scope: scope,
    );
    await store.write('todo', {'title': 'local'});
    final second = await profiles.save(const SyncProfileDraft(
      label: 'Second',
      backend: 'webdav',
      secrets: {'password': 'secret'},
    ));
    await profiles.activate(second.id);
    expect(await store.read('todo'), isNull);
    await store.write('todo', {'title': 'second'});
    await profiles.activate('default');
    expect(await store.read('todo'), {'title': 'local'});
    expect((await profiles.list()).toString(), isNot(contains('secret')));
    expect(await profiles.secrets(second.id), {'password': 'secret'});
  });
}
