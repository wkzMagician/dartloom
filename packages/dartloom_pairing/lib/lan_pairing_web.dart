import 'pairing_handshake.dart';
import 'pairing_protocol.dart';

class LanPairingServer {
  LanPairingServer({required this.onRequest});
  final Future<Map<String, Object?>> Function(Map<String, Object?> request)
  onRequest;
  int? get boundPort => null;
  Future<void> start() => _unsupported();
  Future<void> close() async {}
}

class LanPairingService {
  LanPairingService({required this.server, required this.createAdvertiser});
  final LanPairingServer server;
  final Object Function(int port) createAdvertiser;
  Future<void> start() => _unsupported();
  Future<void> close() async {}
}

class LanPairingClient {
  Future<Map<String, Object?>> request({
    required String host,
    required int port,
    required Map<String, Object?> payload,
    String? certificateSha256,
  }) => _unsupported();

  Future<PairingInvite> fetchInvite({
    required String host,
    required int port,
    String? certificateSha256,
  }) => _unsupported();
}

class LanPairingRequestHandler {
  LanPairingRequestHandler({
    required this.invite,
    required this.issuerDeviceId,
    this.onAccepted,
  });
  final PairingInvite invite;
  final String issuerDeviceId;
  final Future<bool> Function(PairingAcceptance acceptance)? onAccepted;
  Future<Map<String, Object?>> handle(Map<String, Object?> request) =>
      _unsupported();
}

Future<T> _unsupported<T>() => Future<T>.error(
  UnsupportedError('LAN socket pairing is unavailable in browser builds.'),
);
