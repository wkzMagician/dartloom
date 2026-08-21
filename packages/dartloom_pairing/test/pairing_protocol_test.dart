import 'dart:convert';
import 'dart:math';

import 'package:dartloom_pairing/dartloom_pairing.dart';
import 'package:test/test.dart';

void main() {
  test('portable invitations round-trip without private material', () {
    final coordinator = PairingCoordinator(random: Random(1));
    final session = coordinator.createInvite(
      uriScheme: 'actent',
      issuerDeviceId: 'desktop',
      issuerPublicKey: 'public-key',
      relayUrl: 'https://ntfy.example',
      temporaryTopic: 'temporary-topic',
      issuerLanHost: '192.168.1.10',
      issuerLanPort: 43100,
      issuerPairingLanPort: 43101,
      issuerCertificateSha256: 'certificate-fingerprint',
    );

    final decoded = PairingInvite.fromUri(
      session.invite.toUri(),
      uriScheme: 'actent',
    );
    expect(decoded.nonce, session.invite.nonce);
    expect(decoded.issuerLanPort, 43100);
    expect(decoded.issuerPairingLanPort, 43101);
    expect(decoded.toUri(), isNot(contains('private')));
    expect(session.invite.toUri(), startsWith('actent://pair/v1/'));
  });

  test('rejects unknown invitation fields', () {
    final session = PairingCoordinator(random: Random(4)).createInvite(
      uriScheme: 'actent',
      issuerDeviceId: 'desktop',
      issuerPublicKey: 'public-key',
      relayUrl: 'https://ntfy.example',
      temporaryTopic: 'temporary-topic',
    );
    final payload = {...session.invite.toJson(), 'unexpected': true};
    final token = base64UrlEncode(utf8.encode(jsonEncode(payload)))
        .replaceAll('=', '');
    expect(
      () =>
          PairingInvite.fromUri('actent://pair/v1/$token', uriScheme: 'actent'),
      throwsA(isA<PairingValidationException>()),
    );
  });

  test('requires acceptance and the matching short code', () {
    final session = PairingCoordinator(random: Random(2)).createInvite(
      uriScheme: 'actent',
      issuerDeviceId: 'desktop',
      issuerPublicKey: 'public-key',
      relayUrl: 'https://ntfy.example',
      temporaryTopic: 'temporary-topic',
    );
    session.accept(remoteDeviceId: 'phone', remotePublicKey: 'phone-key');
    expect(
      () => session.confirm('000000'),
      throwsA(isA<PairingValidationException>()),
    );
    session.confirm(session.invite.shortCode);
    expect(session.status, PairingStatus.confirmed);
  });

  test('LAN handler verifies acceptance proof before confirmation', () async {
    final session = PairingCoordinator(random: Random(3)).createInvite(
      uriScheme: 'actent',
      issuerDeviceId: 'desktop',
      issuerPublicKey: 'desktop-key',
      relayUrl: 'https://ntfy.example',
      temporaryTopic: 'temporary-topic',
    );
    PairingAcceptance? accepted;
    final handler = LanPairingRequestHandler(
      invite: session.invite,
      issuerDeviceId: 'desktop',
      onAccepted: (value) async {
        accepted = value;
        return true;
      },
    );
    final response = await handler.handle(const {
      'type': 'pairingHello',
      'version': 1,
    });
    expect(
      PairingInvite.fromUri(
        response['inviteUri'] as String,
        uriScheme: 'actent',
      ).nonce,
      session.invite.nonce,
    );
    final acceptance = PairingAcceptance(
      nonce: session.invite.nonce,
      shortCode: session.invite.shortCode,
      deviceId: 'phone',
      publicKey: 'phone-key',
      displayName: 'Phone',
      platform: 'android',
      relayUrl: 'https://ntfy.example',
      relayTopic: 'phone-topic',
      proof: pairingProof(
        nonce: session.invite.nonce,
        shortCode: session.invite.shortCode,
        deviceId: 'phone',
        publicKey: 'phone-key',
      ),
      createdAt: DateTime.now().toUtc(),
    );
    final confirmation = PairingConfirmation.fromJson(
      await handler.handle(acceptance.toJson()),
    );
    expect(accepted?.deviceId, 'phone');
    expect(confirmation.acceptorDeviceId, 'phone');
    expect(
      () => PairingAcceptance.fromJson({
        ...acceptance.toJson(),
        'unexpected': true,
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => PairingConfirmation.fromJson({
        ...confirmation.toJson(),
        'unexpected': true,
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => handler.handle({...acceptance.toJson(), 'shortCode': '000000'}),
      throwsA(isA<PairingValidationException>()),
    );
    final rejectingHandler = LanPairingRequestHandler(
      invite: session.invite,
      issuerDeviceId: 'desktop',
      onAccepted: (_) async => false,
    );
    await expectLater(
      rejectingHandler.handle(acceptance.toJson()),
      throwsA(isA<PairingValidationException>()),
    );
  });
}
