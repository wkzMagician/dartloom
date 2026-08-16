import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'packet_contracts.dart';

/// Sends an already encrypted generic [Packet].
abstract interface class PacketConnection {
  Future<void> send(Packet packet);
}

class RetryPolicy {
  const RetryPolicy({
    this.maxAttempts = 3,
    this.timeout = const Duration(seconds: 10),
  }) : assert(maxAttempts > 0);

  final int maxAttempts;
  final Duration timeout;
}

abstract interface class RelayPublisher {
  Future<void> publish(String topic, String body, {String? authorization});
}

class RelayPublishException implements Exception {
  const RelayPublishException(this.message, {this.statusCode, this.retryAfter});

  final String message;
  final int? statusCode;
  final Duration? retryAfter;

  bool get isRetryable =>
      statusCode == null ||
      statusCode == 408 ||
      statusCode == 429 ||
      statusCode! >= 500;

  @override
  String toString() =>
      'Relay publish failed${statusCode == null ? '' : ' ($statusCode)'}: $message';
}

class NtfyRelayPublisher implements RelayPublisher {
  NtfyRelayPublisher(this.server, {http.Client? client})
    : _client = client ?? http.Client();

  final Uri server;
  final http.Client _client;

  @override
  Future<void> publish(
    String topic,
    String body, {
    String? authorization,
  }) async {
    final basePath = server.path.endsWith('/')
        ? server.path
        : '${server.path}/';
    final uri = server.replace(path: '$basePath${Uri.encodeComponent(topic)}');
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      ...?(authorization == null
          ? null
          : <String, String>{'Authorization': authorization}),
    };
    final response = await _client
        .post(uri, headers: headers, body: body)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final retryAfterHeader = response.headers['retry-after'];
      final seconds = retryAfterHeader == null
          ? null
          : int.tryParse(retryAfterHeader);
      throw RelayPublishException(
        response.body.isEmpty ? 'HTTP ${response.statusCode}' : response.body,
        statusCode: response.statusCode,
        retryAfter: seconds == null ? null : Duration(seconds: seconds),
      );
    }
  }
}

abstract interface class LanPacketSender implements PacketConnection {}

class LanPacketFrame {
  const LanPacketFrame._();

  static Uint8List encode(Packet packet) {
    final body = utf8.encode(packet.encode());
    if (body.length > 0xffffffff) {
      throw ArgumentError('packet is too large for a LAN frame');
    }
    final bytes = Uint8List(4 + body.length)
      ..buffer.asByteData().setUint32(0, body.length, Endian.big);
    bytes.setRange(4, bytes.length, body);
    return bytes;
  }

  static Packet decode(List<int> frame) {
    if (frame.length < 4) {
      throw const PacketValidationException('short LAN frame');
    }
    final bytes = Uint8List.fromList(frame);
    final length = bytes.buffer.asByteData().getUint32(0, Endian.big);
    if (length != bytes.length - 4) {
      throw const PacketValidationException('LAN frame length mismatch');
    }
    return Packet.decode(utf8.decode(bytes.sublist(4)));
  }
}

/// Sends one length-prefixed encrypted Packet over a pinned TLS connection.
class LanTlsPacketConnection implements LanPacketSender {
  LanTlsPacketConnection({
    required this.host,
    required this.port,
    this.timeout = const Duration(seconds: 3),
    this.certificateSha256,
    Future<SecureSocket> Function(
      String host,
      int port, {
      Duration? timeout,
      bool Function(X509Certificate certificate)? onBadCertificate,
    })?
    connect,
  }) : _connect = connect ?? _connectSecure;

  final String host;
  final int port;
  final Duration timeout;
  final String? certificateSha256;
  final Future<SecureSocket> Function(
    String host,
    int port, {
    Duration? timeout,
    bool Function(X509Certificate certificate)? onBadCertificate,
  })
  _connect;

  @override
  Future<void> send(Packet packet) async {
    final socket = await _connect(
      host,
      port,
      timeout: timeout,
      onBadCertificate: certificateSha256 == null
          ? null
          : (certificate) => _matches(certificate),
    ).timeout(timeout);
    try {
      if (certificateSha256 != null &&
          (socket.peerCertificate == null ||
              !_matches(socket.peerCertificate!))) {
        throw const SocketException('LAN TLS certificate pin mismatch');
      }
      socket.add(LanPacketFrame.encode(packet));
      await socket.flush().timeout(timeout);
    } finally {
      await socket.close();
    }
  }

  bool _matches(X509Certificate certificate) =>
      sha256.convert(certificate.der).toString().toLowerCase() ==
      certificateSha256!.replaceAll(':', '').toLowerCase();
}

/// Minimal TLS listener counterpart for desktop LAN delivery.
class LanTlsPacketServer {
  LanTlsPacketServer({
    required this.securityContext,
    required this.onPacket,
    this.host,
    this.port = 0,
  });

  final SecurityContext securityContext;
  final Future<void> Function(Packet packet) onPacket;
  final InternetAddress? host;
  final int port;
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
    final bytes = BytesBuilder(copy: false);
    try {
      await for (final chunk in socket) {
        bytes.add(chunk);
        final current = bytes.takeBytes();
        if (current.length < 4) {
          bytes.add(current);
          continue;
        }
        final length = Uint8List.fromList(current).buffer
            .asByteData()
            .getUint32(0, Endian.big);
        if (current.length < length + 4) {
          bytes.add(current);
          continue;
        }
        if (current.length != length + 4) {
          throw const PacketValidationException('LAN frame length mismatch');
        }
        await onPacket(LanPacketFrame.decode(current));
        break;
      }
    } on Object {
      // A malformed or disconnected peer must not stop the listener.
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

Future<SecureSocket> _connectSecure(
  String host,
  int port, {
  Duration? timeout,
  bool Function(X509Certificate certificate)? onBadCertificate,
}) => SecureSocket.connect(
  host,
  port,
  timeout: timeout,
  onBadCertificate: onBadCertificate,
);

class RoutedPacketSender implements PacketConnection {
  RoutedPacketSender({
    required this.lan,
    required this.relay,
    required this.relayTopic,
    this.relayAuthorization,
    this.policy = const RetryPolicy(),
    Future<void> Function(Duration)? wait,
  }) : _wait = wait ?? _defaultWait;

  final PacketConnection lan;
  final RelayPublisher relay;
  final String relayTopic;
  final String? relayAuthorization;
  final RetryPolicy policy;
  final Future<void> Function(Duration) _wait;

  @override
  Future<void> send(Packet packet) async {
    try {
      await lan.send(packet).timeout(const Duration(seconds: 3));
      return;
    } on Object {
      // LAN is an optimization. Any connection failure falls back to relay.
    }
    RelayPublishException? lastError;
    for (var attempt = 0; attempt < policy.maxAttempts; attempt++) {
      try {
        await relay
            .publish(
              relayTopic,
              packet.encode(),
              authorization: relayAuthorization,
            )
            .timeout(policy.timeout);
        return;
      } on RelayPublishException catch (error) {
        lastError = error;
        if (!error.isRetryable || attempt == policy.maxAttempts - 1) rethrow;
        await _wait(error.retryAfter ?? Duration(seconds: 2 << attempt));
      } on TimeoutException catch (error) {
        lastError = RelayPublishException(error.toString());
        if (attempt == policy.maxAttempts - 1) rethrow;
        await _wait(Duration(seconds: 2 << attempt));
      }
    }
    throw lastError ?? const RelayPublishException('relay delivery failed');
  }
}

class NtfyPacketSubscription {
  NtfyPacketSubscription(
    this.server,
    this.topic, {
    this.authorization,
    WebSocketConnector? connect,
  }) : _connect = connect ?? _connectWebSocket;

  final Uri server;
  final String topic;
  final String? authorization;
  final WebSocketConnector _connect;

  Stream<Packet> listen() {
    final scheme = server.scheme == 'https' ? 'wss' : 'ws';
    final basePath = server.path.endsWith('/')
        ? server.path
        : '${server.path}/';
    final uri = server.replace(
      scheme: scheme,
      path: '$basePath${Uri.encodeComponent(topic)}/ws',
    );
    final channel = _connect(
      uri,
      headers: authorization == null
          ? null
          : <String, String>{'Authorization': authorization!},
    );
    return channel.stream
        .where((value) => value is String)
        .cast<String>()
        .map(_decodeNtfyEvent);
  }
}

/// JSON-only relay stream for short-lived control envelopes.
class NtfyJsonSubscription {
  NtfyJsonSubscription(
    this.server,
    this.topic, {
    this.authorization,
    WebSocketConnector? connect,
  }) : _connect = connect ?? _connectWebSocket;

  final Uri server;
  final String topic;
  final String? authorization;
  final WebSocketConnector _connect;

  Stream<Map<String, Object?>> listen() {
    final scheme = server.scheme == 'https' ? 'wss' : 'ws';
    final basePath = server.path.endsWith('/')
        ? server.path
        : '${server.path}/';
    final uri = server.replace(
      scheme: scheme,
      path: '$basePath${Uri.encodeComponent(topic)}/ws',
    );
    final channel = _connect(
      uri,
      headers: authorization == null
          ? null
          : <String, String>{'Authorization': authorization!},
    );
    return channel.stream
        .where((value) => value is String)
        .cast<String>()
        .map(_decodeJsonEvent);
  }
}

typedef WebSocketConnector = WebSocketChannel Function(
  Uri uri, {
  Map<String, String>? headers,
});

WebSocketChannel _connectWebSocket(Uri uri, {Map<String, String>? headers}) =>
    IOWebSocketChannel.connect(uri, headers: headers);

class MemoryPacketConnection implements PacketConnection {
  final List<Packet> sent = [];

  @override
  Future<void> send(Packet packet) async => sent.add(packet);
}

Future<void> _defaultWait(Duration duration) => Future<void>.delayed(duration);

Packet _decodeNtfyEvent(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map && decoded['message'] is String) {
      return Packet.decode(decoded['message'] as String);
    }
  } on FormatException {
    // Fall through and report the packet-level JSON error below.
  }
  return Packet.decode(value);
}

Map<String, Object?> _decodeJsonEvent(String value) {
  final decoded = jsonDecode(value);
  final body = decoded is Map && decoded['message'] is String
      ? jsonDecode(decoded['message'] as String)
      : decoded;
  if (body is! Map) throw const FormatException('relay event is not an object');
  return Map<String, Object?>.from(body);
}
