import 'package:dartloom_pairing/dartloom_pairing.dart';
import 'package:test/test.dart';

void main() {
  test('memory pairing capability progresses through confirmation', () async {
    final capability = MemoryPairingCapability();
    final invitation = await capability.createInvitation();
    await capability.accept(invitation, 'phone', 'phone-public-key');
    await capability.confirm(invitation.nonce, invitation.shortCode);
    expect(capability.states[invitation.nonce], PairingState.confirmed);
    await capability.close();
  });
}
