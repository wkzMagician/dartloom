import 'dart:convert';
import 'dart:typed_data';

import 'package:dartloom_settings/dartloom_settings.dart';
import 'package:dartloom_storage/dartloom_storage.dart';
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

  test('reads secret keys after a secure-storage JSON round trip', () async {
    final metadata = _JsonRoundTripSettingsStore();
    final secure = _JsonRoundTripSettingsStore();
    final scope = await SyncProfileScope.open(metadata, 'default');
    final profiles = SettingsSyncProfileRepository(
      instanceName: 'default',
      metadata: metadata,
      secretsStore: secure,
      scope: scope,
    );

    final profile = await profiles.save(const SyncProfileDraft(
      label: 'WebDAV',
      backend: 'webdav',
      secrets: {'password': 'secret'},
    ));

    expect(await profiles.secrets(profile.id), {'password': 'secret'});

    // Updating profile options without supplying secrets must preserve existing secrets.
    final updated = await profiles.save(SyncProfileDraft(
      id: profile.id,
      label: 'WebDAV Updated',
      backend: 'webdav',
      options: {'base_url': 'https://example.com'},
    ));
    expect(await profiles.secrets(updated.id), {'password': 'secret'});
  });

  test('reconciliation state is stored outside the replica', () async {
    final settings = MemorySettingsStore();
    final state = SettingsReconciliationStateRepository(
      settings,
      instanceName: 'default',
    );
    await state.save(
      'profile',
      const SyncState(
        fingerprint: 'v5',
        records: {'todo-1': SyncRecord(baseHash: 'hash')},
      ),
    );

    expect((await state.load('profile')).fingerprint, 'v5');
    expect(await settings.read('sync.default.v5.state.profile'), isA<String>());
  });

  test('corrupt and unknown state fail safely', () async {
    final settings = MemorySettingsStore();
    final state = SettingsReconciliationStateRepository(
      settings,
      instanceName: 'default',
    );
    await settings.write('sync.default.v5.state.profile', '{');
    await expectLater(state.load('profile'), throwsFormatException);
    await settings.write(
      'sync.default.v5.state.profile',
      '{"version":99}',
    );
    await expectLater(state.load('profile'), throwsFormatException);
  });

  test(
      'journal records local intent, excludes remote recovery, and acknowledges',
      () async {
    final objects = MemoryObjectStore(identity: 'objects');
    final metadata = MemoryObjectStore(identity: 'metadata');
    final journal = await JournaledObjectStore.open(
      objects: objects,
      metadata: metadata,
    );
    await journal.write('todo-1', Uint8List.fromList([1, 2, 3]));
    expect((await journal.intents()).single.key, 'todo-1');

    await journal.writeRemote('todo-1', Uint8List.fromList([4, 5]));
    expect((await journal.intents()).single.key, 'todo-1');
    await journal.forgetIntent((await journal.intents()).single.operationId);
    expect(await journal.intents(), isEmpty);
    await journal.close();
  });

  test('journal requires separate object and metadata stores', () async {
    final store = MemoryObjectStore();
    await expectLater(
      JournaledObjectStore.open(objects: store, metadata: store),
      throwsArgumentError,
    );
    await store.close();
  });
}

/// Models SecureSettingsStore: values are encoded before persistence and
/// decoded again, which turns `List<String>` into `List<dynamic>` at runtime.
final class _JsonRoundTripSettingsStore implements SettingsStore {
  final Map<String, String> _values = {};

  @override
  Future<Object?> read(String key) async {
    final value = _values[key];
    return value == null ? null : jsonDecode(value);
  }

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> write(String key, Object value) async {
    _values[key] = jsonEncode(value);
  }
}
