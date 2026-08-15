import 'package:dartloom_pairing/dartloom_pairing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'persists a stable X25519 identity through the store contract',
    () async {
      final store = MemoryPairingIdentityStore();
      final first = await PairingIdentityRepository(store).loadOrCreate();
      final second = await PairingIdentityRepository(store).loadOrCreate();

      expect(second.deviceId, first.deviceId);
      expect(second.privateKeyBytes, first.privateKeyBytes);
      expect(second.publicKeyBytes, first.publicKeyBytes);
    },
  );

  test('repairs a missing public-key cache from the private key', () async {
    final store = MemoryPairingIdentityStore();
    final first = await PairingIdentityRepository(store).loadOrCreate();
    store.values.remove('device.x25519.public');

    final restored = await PairingIdentityRepository(store).loadOrCreate();

    expect(restored.deviceId, first.deviceId);
    expect(restored.publicKeyBytes, first.publicKeyBytes);
    expect(store.values['device.x25519.public'], isNotNull);
  });
}
