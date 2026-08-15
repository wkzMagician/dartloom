import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartloom_messaging/dartloom_messaging.dart';
import 'package:test/test.dart';

void main() {
  test('frames a generic Packet with an exact length prefix', () {
    final packet = Packet(
      packetId: 'packet-1',
      senderId: 'sender',
      recipientId: 'recipient',
      createdAt: DateTime.utc(2026),
      ciphertext: Uint8List.fromList([1, 2, 3]),
      nonce: Uint8List(12),
      mac: Uint8List(16),
    );
    final frame = LanPacketFrame.encode(packet);
    expect(LanPacketFrame.decode(frame).packetId, 'packet-1');
    expect(
      () => LanPacketFrame.decode(frame.sublist(0, frame.length - 1)),
      throwsA(isA<PacketValidationException>()),
    );
  });

  test('falls back from LAN and retries retryable relay errors', () async {
    final lan = _FailingConnection();
    final relay = _RetryingRelay(2);
    final packet = Packet(
      packetId: 'packet-2',
      senderId: 'sender',
      recipientId: 'recipient',
      createdAt: DateTime.utc(2026),
      ciphertext: Uint8List.fromList([1]),
      nonce: Uint8List(12),
      mac: Uint8List(16),
    );
    await RoutedPacketSender(
      lan: lan,
      relay: relay,
      relayTopic: 'topic',
      policy: const RetryPolicy(maxAttempts: 3),
      wait: (_) async {},
    ).send(packet);
    expect(lan.attempts, 1);
    expect(relay.attempts, 3);
  });

  test('deduplicates packet IDs for the configured retention window', () {
    var now = DateTime.utc(2026, 1, 1);
    final store = SeenPacketStore(
      retention: const Duration(days: 7),
      clock: () => now,
    );
    expect(store.remember('packet-1'), isTrue);
    expect(store.remember('packet-1'), isFalse);
    now = now.add(const Duration(days: 8));
    expect(store.remember('packet-1'), isTrue);
  });

  test(
    'sends and receives a Packet over a pinned loopback TLS socket',
    () async {
      final received = Completer<Packet>();
      final securityContext = SecurityContext()
        ..useCertificateChainBytes(utf8.encode(_testCertificate))
        ..usePrivateKeyBytes(utf8.encode(_testPrivateKey));
      final server = LanTlsPacketServer(
        securityContext: securityContext,
        host: InternetAddress.loopbackIPv4,
        onPacket: (packet) async {
          if (!received.isCompleted) received.complete(packet);
        },
      );
      await server.start();
      try {
        final packet = Packet(
          packetId: 'loopback-packet',
          senderId: 'sender',
          recipientId: 'recipient',
          createdAt: DateTime.now().toUtc(),
          ciphertext: Uint8List.fromList([4, 5, 6]),
          nonce: Uint8List(12),
          mac: Uint8List(16),
        );
        await LanTlsPacketConnection(
          host: InternetAddress.loopbackIPv4.address,
          port: server.boundPort!,
          certificateSha256: sha256
              .convert(base64.decode(_pemBody(_testCertificate)))
              .toString(),
        ).send(packet);
        expect(
          (await received.future.timeout(const Duration(seconds: 3))).packetId,
          'loopback-packet',
        );
      } finally {
        await server.close();
      }
    },
  );
}

class _FailingConnection implements PacketConnection {
  var attempts = 0;

  @override
  Future<void> send(Packet packet) async {
    attempts++;
    throw StateError('LAN unavailable');
  }
}

class _RetryingRelay implements RelayPublisher {
  _RetryingRelay(this.failuresBeforeSuccess);

  final int failuresBeforeSuccess;
  var attempts = 0;

  @override
  Future<void> publish(
    String topic,
    String body, {
    String? authorization,
  }) async {
    attempts++;
    if (attempts <= failuresBeforeSuccess) {
      throw const RelayPublishException('temporary', statusCode: 500);
    }
  }
}

String _pemBody(String value) =>
    value.split('\n').where((line) => !line.startsWith('---')).join().trim();

const _testCertificate = '''-----BEGIN CERTIFICATE-----
MIIBfTCCASOgAwIBAgIUJToC57cKV79/sKSJGjA/JfPVltswCgYIKoZIzj0EAwIw
FDESMBAGA1UEAwwJbG9jYWxob3N0MB4XDTI2MDgxNTA4MTYzNVoXDTM2MDgxMjA4
MTYzNVowFDESMBAGA1UEAwwJbG9jYWxob3N0MFkwEwYHKoZIzj0CAQYIKoZIzj0D
AQcDQgAEYoyyoAIlxgHWJI6TmimIkoF8+8jbdPXQ9V0ET2hdXzAf6+crrcUTTzZp
LhvKJzQiE+8JWTKhjetp70i4MHA5SqNTMFEwHQYDVR0OBBYEFAidUWnckkaJRnvv
h01g965QOvVNMB8GA1UdIwQYMBaAFAidUWnckkaJRnvvh01g965QOvVNMA8GA1Ud
EwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDSAAwRQIhANCYaybduOPi0JFhr7UPq/gU
MxFouw2Xx89uEszM6djdAiAEWB2adLZEOfmdi06ciYWjNjEX369Ll3yNUY68en3T
5Q==
-----END CERTIFICATE-----
''';

const _testPrivateKey = '''-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIMYEJVP5wTV47KxSDG3cwgIQJEj3J1YxTIJ5ckc0xRpmoAoGCCqGSM49
AwEHoUQDQgAEYoyyoAIlxgHWJI6TmimIkoF8+8jbdPXQ9V0ET2hdXzAf6+crrcUT
TzZpLhvKJzQiE+8JWTKhjetp70i4MHA5Sg==
-----END EC PRIVATE KEY-----
''';
