import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'mdns.dart';
import 'pairing_handshake.dart';
import 'pairing_protocol.dart';

/// One request/response is carried per temporary TLS connection. mDNS only
/// locates this endpoint; the pairing proof and optional certificate pin
/// authenticate it before any endpoint is persisted.
class LanPairingServer {
  LanPairingServer({
    required this.securityContext,
    required this.onRequest,
    this.host,
    this.port = 0,
    this.requestTimeout = const Duration(seconds: 10),
  });

  final SecurityContext securityContext;
  final Future<Map<String, Object?>> Function(Map<String, Object?> request)
      onRequest;
  final InternetAddress? host;
  final int port;
  final Duration requestTimeout;
  SecureServerSocket? _server;

  int? get boundPort => _server?.port;

  Future<void> start() async {
    if (_server != null) return;
    _server = await SecureServerSocket.bind(
      host ?? InternetAddress.anyIPv4,
      port,
      securityContext,
    );
    _server!.listen(_accept, onError: (_) {});
  }

  Future<void> _accept(SecureSocket socket) async {
    try {
      final line = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(requestTimeout);
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        throw const FormatException('request is not an object');
      }
      final response = await onRequest(Map<String, Object?>.from(decoded));
      socket
        ..write(jsonEncode(response))
        ..write('\n');
      await socket.flush();
    } on Object catch (error) {
      try {
        socket
          ..write(
            jsonEncode(<String, Object?>{
              'ok': false,
              'error': 'invalid_pairing_request',
              'detail': '$error',
            }),
          )
          ..write('\n');
        await socket.flush();
      } on Object {
        // The peer may have already disconnected.
      }
    } finally {
      await socket.close();
    }
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    await server?.close();
  }
}

/// Couples the temporary TLS listener to a short-lived DNS-SD advertisement.
class LanPairingService {
  LanPairingService({required this.server, required this.createAdvertiser});

  final LanPairingServer server;
  final MdnsPairingAdvertiser Function(int port) createAdvertiser;
  MdnsPairingAdvertiser? _advertiser;

  Future<void> start() async {
    await server.start();
    final port = server.boundPort;
    if (port == null) {
      await server.close();
      throw StateError('LAN pairing server did not bind a port');
    }
    final advertiser = createAdvertiser(port);
    try {
      await advertiser.start();
      _advertiser = advertiser;
    } on Object {
      await server.close();
      rethrow;
    }
  }

  Future<void> close() async {
    await _advertiser?.stop();
    _advertiser = null;
    await server.close();
  }
}

class LanPairingClient {
  LanPairingClient({
    this.timeout = const Duration(seconds: 10),
    Future<SecureSocket> Function(
      String host,
      int port, {
      Duration? timeout,
      bool Function(X509Certificate certificate)? onBadCertificate,
    })? connect,
  }) : _connect = connect ?? _connectSecure;

  final Duration timeout;
  final Future<SecureSocket> Function(
    String host,
    int port, {
    Duration? timeout,
    bool Function(X509Certificate certificate)? onBadCertificate,
  }) _connect;

  Future<Map<String, Object?>> request({
    required String host,
    required int port,
    required Map<String, Object?> payload,
    String? certificateSha256,
  }) async {
    final socket = await _connect(
      host,
      port,
      timeout: timeout,
      onBadCertificate: certificateSha256 == null
          ? null
          : (certificate) => _matches(certificate, certificateSha256),
    ).timeout(timeout);
    try {
      socket
        ..write(jsonEncode(payload))
        ..write('\n');
      await socket.flush().timeout(timeout);
      final line = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(timeout);
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        throw const FormatException('response is not an object');
      }
      return Map<String, Object?>.from(decoded);
    } finally {
      await socket.close();
    }
  }

  Future<PairingInvite> fetchInvite({
    required String host,
    required int port,
    String? certificateSha256,
  }) async {
    final response = await request(
      host: host,
      port: port,
      certificateSha256: certificateSha256,
      payload: const <String, Object?>{'type': 'pairingHello', 'version': 1},
    );
    if (response['type'] != 'pairingInvite' ||
        response['version'] != 1 ||
        response['inviteUri'] is! String) {
      throw const PairingValidationException(
        'LAN pairing server returned an invalid invite',
      );
    }
    return PairingInvite.fromUri(response['inviteUri'] as String);
  }

  Future<PairingConfirmation> sendAcceptance({
    required PairingInvite invite,
    required String host,
    required int port,
    required String deviceId,
    required String publicKey,
    required String displayName,
    required String platform,
    required String relayUrl,
    required String relayTopic,
    String? lanHost,
    int? lanPort,
    String? serverCertificateSha256,
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
    final confirmation = PairingConfirmation.fromJson(
      await request(
        host: host,
        port: port,
        certificateSha256:
            serverCertificateSha256 ?? invite.issuerCertificateSha256,
        payload: acceptance.toJson(),
      ),
    );
    if (confirmation.nonce != invite.nonce ||
        confirmation.shortCode != invite.shortCode ||
        confirmation.acceptorDeviceId != deviceId ||
        confirmation.issuerDeviceId != invite.issuerDeviceId ||
        confirmation.proof !=
            pairingProof(
              nonce: invite.nonce,
              shortCode: invite.shortCode,
              deviceId: invite.issuerDeviceId,
              publicKey: publicKey,
            )) {
      throw const PairingValidationException(
        'LAN pairing confirmation does not match the invite',
      );
    }
    return confirmation;
  }
}

Future<SecureSocket> _connectSecure(
  String host,
  int port, {
  Duration? timeout,
  bool Function(X509Certificate certificate)? onBadCertificate,
}) =>
    SecureSocket.connect(
      host,
      port,
      timeout: timeout,
      onBadCertificate: onBadCertificate,
    );

bool _matches(X509Certificate certificate, String expected) =>
    sha256.convert(certificate.der).toString().toLowerCase() ==
    expected.replaceAll(':', '').toLowerCase();

/// Verifies the invite proof before returning a confirmation response.
class LanPairingRequestHandler {
  LanPairingRequestHandler({
    required this.invite,
    required this.issuerDeviceId,
    this.onAccepted,
  });

  final PairingInvite invite;
  final String issuerDeviceId;
  final Future<bool> Function(PairingAcceptance acceptance)? onAccepted;

  Future<Map<String, Object?>> handle(Map<String, Object?> request) async {
    if (request['type'] == 'pairingHello' && request['version'] == 1) {
      return <String, Object?>{
        'type': 'pairingInvite',
        'version': 1,
        'inviteUri': invite.toUri(),
      };
    }
    if (request['type'] != 'pairingAccepted') {
      throw const PairingValidationException('unsupported LAN pairing request');
    }
    final acceptance = PairingAcceptance.fromJson(request);
    if (!acceptance.verify(invite)) {
      throw const PairingValidationException(
        'LAN pairing acceptance proof failed',
      );
    }
    final accepted = await onAccepted?.call(acceptance) ?? true;
    if (!accepted) {
      throw const PairingValidationException(
        'pairing was rejected by the issuer',
      );
    }
    return PairingConfirmation(
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
    ).toJson();
  }
}
