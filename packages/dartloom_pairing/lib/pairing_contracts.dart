import 'dart:async';

class PairingInvitation {
  const PairingInvitation({
    required this.nonce,
    required this.issuerDeviceId,
    required this.issuerPublicKey,
    required this.relayUrl,
    required this.temporaryTopic,
    required this.expiresAt,
    this.shortCode = '123456',
    this.lanHost,
    this.lanPort,
    this.certificateSha256,
  });

  final String nonce;
  final String issuerDeviceId;
  final String issuerPublicKey;
  final String relayUrl;
  final String temporaryTopic;
  final DateTime expiresAt;
  final String shortCode;
  final String? lanHost;
  final int? lanPort;
  final String? certificateSha256;

  Map<String, Object?> toJson() => <String, Object?>{
    'nonce': nonce,
    'issuerDeviceId': issuerDeviceId,
    'issuerPublicKey': issuerPublicKey,
    'relayUrl': relayUrl,
    'temporaryTopic': temporaryTopic,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'shortCode': shortCode,
    if (lanHost != null) 'lanHost': lanHost,
    if (lanPort != null) 'lanPort': lanPort,
    if (certificateSha256 != null) 'certificateSha256': certificateSha256,
  };
}

enum PairingState { created, accepted, confirmed, rejected, cancelled, expired }

abstract interface class PairingCapability {
  Future<PairingInvitation> createInvitation();
  Future<void> accept(
    PairingInvitation invitation,
    String deviceId,
    String publicKey,
  );
  Future<void> confirm(String nonce, String shortCode);
  Stream<PairingAdvertisement> discover();
}

class PairingAdvertisement {
  const PairingAdvertisement({
    required this.deviceId,
    required this.displayName,
    required this.platform,
    required this.fingerprint,
    this.host,
    this.port,
  });

  final String deviceId;
  final String displayName;
  final String platform;
  final String fingerprint;
  final String? host;
  final int? port;
}

abstract interface class QrPresenter {
  Future<void> show(String invitation);
}

abstract interface class QrScanner {
  Future<String?> scan();
}

class MemoryPairingCapability implements PairingCapability {
  final StreamController<PairingAdvertisement> _advertisements =
      StreamController<PairingAdvertisement>.broadcast();
  final Map<String, PairingState> states = {};

  @override
  Future<PairingInvitation> createInvitation() async {
    final now = DateTime.now().toUtc();
    final invitation = PairingInvitation(
      nonce: 'memory-${now.microsecondsSinceEpoch}',
      issuerDeviceId: 'memory-device',
      issuerPublicKey: 'memory-public-key',
      relayUrl: 'memory://relay',
      temporaryTopic: 'memory-topic',
      expiresAt: now.add(const Duration(minutes: 10)),
      shortCode: '123456',
    );
    states[invitation.nonce] = PairingState.created;
    return invitation;
  }

  @override
  Future<void> accept(
    PairingInvitation invitation,
    String deviceId,
    String publicKey,
  ) async {
    if (invitation.expiresAt.isBefore(DateTime.now().toUtc())) {
      states[invitation.nonce] = PairingState.expired;
      throw StateError('invitation expired');
    }
    states[invitation.nonce] = PairingState.accepted;
  }

  @override
  Future<void> confirm(String nonce, String shortCode) async {
    final invitationState = states[nonce];
    if (invitationState != PairingState.accepted || shortCode != '123456') {
      throw ArgumentError.value(shortCode, 'shortCode');
    }
    states[nonce] = PairingState.confirmed;
  }

  @override
  Stream<PairingAdvertisement> discover() => _advertisements.stream;

  void advertise(PairingAdvertisement advertisement) =>
      _advertisements.add(advertisement);

  Future<void> close() => _advertisements.close();
}
