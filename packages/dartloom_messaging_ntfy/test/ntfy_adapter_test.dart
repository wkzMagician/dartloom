import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartloom_messaging/dartloom_messaging.dart';
import 'package:dartloom_messaging_ntfy/dartloom_messaging_ntfy.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('accepts only a raw ntfy token', () {
    expect(
      NtfyCredentials('tk_example').authorizationHeader,
      'Bearer tk_example',
    );
    expect(() => NtfyCredentials('Bearer tk_example'), throwsFormatException);
    expect(() => NtfyCredentials('basic value'), throwsFormatException);
  });

  test('publishes exact Packet text with internal Bearer header', () async {
    late http.Request captured;
    final publisher = NtfyRelayPublisher(
      server: Uri.parse('https://relay.example'),
      credentials: NtfyCredentials('tk_example'),
      client: MockClient((request) async {
        captured = request;
        return http.Response('{}', 200);
      }),
    );
    await publisher.publish('actent-control', '{"encrypted":true}');
    expect(captured.url.path, '/actent-control');
    expect(captured.headers['Authorization'], 'Bearer tk_example');
    expect(captured.headers['Content-Type'], 'text/plain; charset=utf-8');
    expect(captured.body, '{"encrypted":true}');
  });

  test('retries transient ntfy publish timeouts', () async {
    var attempts = 0;
    final publisher = NtfyRelayPublisher(
      server: Uri.parse('https://relay.example'),
      credentials: NtfyCredentials('tk_example'),
      client: MockClient((request) async {
        attempts++;
        if (attempts < 3) throw TimeoutException('transient');
        return http.Response('{}', 200);
      }),
      timeout: const Duration(milliseconds: 20),
      maxAttempts: 3,
      retryDelay: Duration.zero,
    );

    await publisher.publish('actent-control', '{}');

    expect(attempts, 3);
  });

  test('uploads and downloads native encrypted blobs', () async {
    final requests = <http.Request>[];
    final store = NtfyBlobStore(
      server: Uri.parse('https://relay.example'),
      credentials: NtfyCredentials('tk_example'),
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'attachment': {
                'url': 'https://relay.example/file/random',
                'size': 3,
                'expires': 1788134400,
              },
            }),
            200,
          );
        }
        return http.Response.bytes([1, 2, 3], 200);
      }),
    );
    final reference = await store.put(
      channel: 'actent-blob',
      objectId: 'random-id',
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    expect(reference.provider, 'ntfy');
    expect(reference.byteLength, 3);
    expect(requests.first.headers['Filename'], 'random-id.dlmb');
    expect(requests.first.headers['Content-Type'], 'application/octet-stream');
    expect(await store.get(reference), [1, 2, 3]);
    expect(requests.last.headers['Authorization'], 'Bearer tk_example');
  });

  test('filters ntfy keepalive events and decodes message events', () {
    expect(decodeNtfyPacketEvent('{"event":"keepalive"}'), isNull);
    final packet = Packet(
      packetId: 'packet-1',
      senderId: 'sender',
      recipientId: 'recipient',
      ciphertext: Uint8List.fromList([1]),
      createdAt: DateTime.utc(2026),
      nonce: Uint8List(12),
      mac: Uint8List(16),
    );
    expect(
      decodeNtfyPacketEvent(
        jsonEncode({'event': 'message', 'message': packet.encode()}),
      )?.packetId,
      'packet-1',
    );
  });

  test('polls cached packets from a UTC cutoff with Bearer auth', () async {
    final packet = Packet(
      packetId: 'cached-packet',
      senderId: 'sender',
      recipientId: 'recipient',
      ciphertext: Uint8List.fromList([1]),
      createdAt: DateTime.utc(2026),
      nonce: Uint8List(12),
      mac: Uint8List(16),
    );
    late http.Request captured;
    final poller = NtfyPacketPoller(
      server: Uri.parse('https://relay.example'),
      channel: 'actent-control',
      credentials: NtfyCredentials('tk_example'),
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          '${jsonEncode({'event': 'keepalive'})}\n'
          '${jsonEncode({'event': 'message', 'message': packet.encode()})}\n',
          200,
        );
      }),
    );

    final packets = await poller.poll(since: DateTime.utc(2026, 8, 17));

    expect(captured.url.path, '/actent-control/json');
    expect(captured.url.queryParameters['poll'], '1');
    expect(captured.url.queryParameters['since'], '1786924800');
    expect(captured.headers['Authorization'], 'Bearer tk_example');
    expect(packets.single.packetId, 'cached-packet');
  });

  test('rejects attachment URLs on another origin', () async {
    final store = NtfyBlobStore(
      server: Uri.parse('https://relay.example'),
      credentials: NtfyCredentials('tk_example'),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'attachment': {'url': 'https://attacker.example/file/id'},
          }),
          200,
        ),
      ),
    );
    await expectLater(
      store.put(
        channel: 'actent-blob',
        objectId: 'random-id',
        bytes: Uint8List(1),
      ),
      throwsA(isA<BlobStoreException>()),
    );
  });
}
