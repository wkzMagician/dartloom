import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartloom_messaging/dartloom_messaging.dart';
import 'package:dartloom_messaging_lan/dartloom_messaging_lan.dart';
import 'package:test/test.dart';

void main() {
  test('frames a generic Packet with an exact length prefix', () {
    final packet = _packet('packet-1');
    final frame = LanPacketFrame.encode(packet);
    expect(LanPacketFrame.decode(frame).packetId, 'packet-1');
    expect(
      () => LanPacketFrame.decode(frame.sublist(0, frame.length - 1)),
      throwsA(isA<PacketValidationException>()),
    );
  });

  test('pushes an encrypted blob over the pinned TLS listener', () async {
    final context = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(_testCertificate))
      ..usePrivateKeyBytes(utf8.encode(_testPrivateKey));
    final localStore = MemoryLanBlobStore();
    final server = LanTlsPacketServer(
      securityContext: context,
      host: InternetAddress.loopbackIPv4,
      onPacket: (_) async => fail('blob frame decoded as Packet'),
      blobStore: localStore,
    );
    await server.start();
    try {
      final store = LanTlsBlobStore(
        host: InternetAddress.loopbackIPv4.address,
        port: server.boundPort!,
        localStore: localStore,
        certificateSha256: sha256
            .convert(base64.decode(_pemBody(_testCertificate)))
            .toString(),
      );
      final reference = await store.put(
        channel: 'actent-blob',
        objectId: 'chunk-1',
        bytes: Uint8List.fromList(<int>[4, 5, 6]),
      );

      expect(reference.provider, 'lan');
      expect(await localStore.get(reference), <int>[4, 5, 6]);
    } finally {
      await server.close();
    }
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
        await LanTlsPacketConnection(
          host: InternetAddress.loopbackIPv4.address,
          port: server.boundPort!,
          certificateSha256: sha256
              .convert(base64.decode(_pemBody(_testCertificate)))
              .toString(),
        ).send(_packet('loopback-packet'));
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

Packet _packet(String id) => Packet(
  packetId: id,
  senderId: 'sender',
  recipientId: 'recipient',
  createdAt: DateTime.now().toUtc(),
  ciphertext: Uint8List.fromList([4, 5, 6]),
  nonce: Uint8List(12),
  mac: Uint8List(16),
);

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
