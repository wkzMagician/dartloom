import 'dart:convert';

import 'pairing_handshake.dart';
import 'pairing_protocol.dart';

abstract interface class PairingRelayPublisher {
  Future<void> publish(String topic, String body, {String? authorization});
}

abstract interface class PairingRelaySubscription {
  Stream<Map<String, Object?>> listen();
}

typedef PairingRelaySubscriptionFactory = PairingRelaySubscription Function(
  Uri server,
  String topic,
  String? authorization,
);

/// Generic relay fallback. The capability only sees a short-lived JSON
/// control envelope; the concrete relay (for example ntfy) is injected.
class PairingRelayHandshake {
  PairingRelayHandshake({
    required this.server,
    this.authorization,
    required this.publisher,
    required this.subscriptionFactory,
  });

  final Uri server;
  final String? authorization;
  final PairingRelayPublisher publisher;
  final PairingRelaySubscriptionFactory subscriptionFactory;

  Future<PairingAcceptance> sendAcceptance({
    required PairingInvite invite,
    required String deviceId,
    required String publicKey,
    required String displayName,
    required String platform,
    required String relayUrl,
    required String relayTopic,
    String? lanHost,
    int? lanPort,
    String? certificateSha256,
  }) async {
    final acceptance = PairingAcceptance(
      nonce: invite.nonce,
      shortCode: invite.shortCode,
      deviceId: deviceId,
      publicKey: publicKey,
      displayName: displayName,
      platform: platform,
      relayUrl: relayUrl,
      relayTopic: relayTopic,
      lanHost: lanHost,
      lanPort: lanPort,
      certificateSha256: certificateSha256,
      proof: pairingProof(
        nonce: invite.nonce,
        shortCode: invite.shortCode,
        deviceId: deviceId,
        publicKey: publicKey,
      ),
      createdAt: DateTime.now().toUtc(),
    );
    await publisher.publish(
      invite.temporaryTopic,
      jsonEncode(acceptance.toJson()),
      authorization: authorization,
    );
    return acceptance;
  }

  Stream<PairingAcceptance> listenForAcceptance(PairingInvite invite) =>
      subscriptionFactory(server, invite.temporaryTopic, authorization)
          .listen()
          .where((value) => value['type'] == 'pairingAccepted')
          .map(PairingAcceptance.fromJson)
          .where((value) => value.nonce == invite.nonce);

  Future<void> sendConfirmation({
    required PairingAcceptance acceptance,
    required String issuerDeviceId,
  }) => publisher.publish(
    acceptance.relayTopic,
    jsonEncode(
      PairingConfirmation(
        nonce: acceptance.nonce,
        shortCode: acceptance.shortCode,
        issuerDeviceId: issuerDeviceId,
        acceptorDeviceId: acceptance.deviceId,
        proof: pairingProof(
          nonce: acceptance.nonce,
          shortCode: acceptance.shortCode,
          deviceId: issuerDeviceId,
          publicKey: acceptance.publicKey,
        ),
      ).toJson(),
    ),
    authorization: authorization,
  );

  Stream<PairingConfirmation> listenForConfirmation(
    PairingInvite invite, {
    required String localRelayTopic,
  }) => subscriptionFactory(server, localRelayTopic, authorization)
      .listen()
      .where((value) => value['type'] == 'pairingConfirmed')
      .map(PairingConfirmation.fromJson)
      .where((value) => value.nonce == invite.nonce);
}
