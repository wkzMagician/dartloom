import 'dart:typed_data';

import 'package:dartloom_messaging/dartloom_messaging.dart';
import 'package:test/test.dart';

void main() {
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
      relayChannel: 'topic',
      policy: const RetryPolicy(maxAttempts: 3),
      wait: (_) async {},
    ).send(packet);
    expect(lan.attempts, 1);
    expect(relay.attempts, 3);
  });

  test('does not retry a permanent relay failure', () async {
    final relay = _PermanentFailureRelay();
    await expectLater(
      RoutedPacketSender(
        lan: _FailingConnection(),
        relay: relay,
        relayChannel: 'topic',
        wait: (_) async {},
      ).send(_packet()),
      throwsA(
        isA<RelayPublishException>().having(
          (error) => error.statusCode,
          'statusCode',
          403,
        ),
      ),
    );
    expect(relay.attempts, 1);
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
}

Packet _packet() => Packet(
  packetId: 'packet',
  senderId: 'sender',
  recipientId: 'recipient',
  createdAt: DateTime.utc(2026),
  ciphertext: Uint8List.fromList([1]),
  nonce: Uint8List(12),
  mac: Uint8List(16),
);

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
  Future<void> publish(String channel, String body) async {
    attempts++;
    if (attempts <= failuresBeforeSuccess) {
      throw const RelayPublishException('temporary', statusCode: 500);
    }
  }
}

class _PermanentFailureRelay implements RelayPublisher {
  var attempts = 0;

  @override
  Future<void> publish(String channel, String body) async {
    attempts++;
    throw const RelayPublishException('denied', statusCode: 403);
  }
}
