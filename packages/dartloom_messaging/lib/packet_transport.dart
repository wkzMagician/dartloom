import 'dart:async';

import 'packet_contracts.dart';

/// Sends an already encrypted generic [Packet].
abstract interface class PacketConnection {
  Future<void> send(Packet packet);
}

class RetryPolicy {
  const RetryPolicy({
    this.maxAttempts = 3,
    this.timeout = const Duration(seconds: 10),
    this.lanTimeout = const Duration(seconds: 3),
  }) : assert(maxAttempts > 0);

  final int maxAttempts;
  final Duration timeout;
  final Duration lanTimeout;
}

/// Transport-neutral text relay used for already encrypted Packet JSON.
///
/// Authentication belongs to the adapter instance and is intentionally not
/// supplied on individual calls.
abstract interface class RelayPublisher {
  Future<void> publish(String channel, String body);
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
      'Relay publish failed${statusCode == null ? '' : ' ($statusCode)'}: '
      '$message';
}

/// Tries the LAN connection first, then publishes the same encrypted Packet
/// through the configured relay with bounded retries.
class RoutedPacketSender implements PacketConnection {
  RoutedPacketSender({
    required this.lan,
    required this.relay,
    required this.relayChannel,
    this.policy = const RetryPolicy(),
    Future<void> Function(Duration)? wait,
  }) : _wait = wait ?? _defaultWait;

  final PacketConnection lan;
  final RelayPublisher relay;
  final String relayChannel;
  final RetryPolicy policy;
  final Future<void> Function(Duration) _wait;

  @override
  Future<void> send(Packet packet) async {
    try {
      await lan.send(packet).timeout(policy.lanTimeout);
      return;
    } on Object {
      // LAN is an optimization. Any connection failure falls back to relay.
    }

    RelayPublishException? lastError;
    for (var attempt = 0; attempt < policy.maxAttempts; attempt++) {
      try {
        await relay
            .publish(relayChannel, packet.encode())
            .timeout(policy.timeout);
        return;
      } on RelayPublishException catch (error) {
        lastError = error;
        if (!error.isRetryable || attempt == policy.maxAttempts - 1) rethrow;
        await _wait(error.retryAfter ?? Duration(seconds: 2 << attempt));
      } on TimeoutException catch (error) {
        lastError = RelayPublishException(error.toString());
        if (attempt == policy.maxAttempts - 1) throw lastError;
        await _wait(Duration(seconds: 2 << attempt));
      }
    }
    throw lastError ?? const RelayPublishException('relay delivery failed');
  }
}

class MemoryPacketConnection implements PacketConnection {
  final List<Packet> sent = [];

  @override
  Future<void> send(Packet packet) async => sent.add(packet);
}

Future<void> _defaultWait(Duration duration) => Future<void>.delayed(duration);
