import 'dart:async';
import 'dart:convert';

import 'package:dartloom_messaging/dartloom_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'ntfy_auth.dart';
import 'ntfy_uri.dart';
import 'ntfy_websocket_connector_stub.dart'
    if (dart.library.io) 'ntfy_websocket_connector_io.dart'
    as platform;

class NtfyRelayPublisher implements RelayPublisher {
  NtfyRelayPublisher({
    required this.server,
    this.credentials,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
    this.maxAttempts = 1,
    this.retryDelay = const Duration(seconds: 1),
  }) : assert(maxAttempts > 0),
       _client = client ?? http.Client();

  final Uri server;
  final NtfyCredentials? credentials;
  final Duration timeout;
  final int maxAttempts;
  final Duration retryDelay;
  final http.Client _client;

  @override
  Future<void> publish(String channel, String body) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final response = await _client
            .post(
              ntfyTopicUri(server, channel),
              headers: <String, String>{
                if (credentials != null)
                  'Authorization': credentials!.authorizationHeader,
                'Content-Type': 'text/plain; charset=utf-8',
              },
              body: body,
            )
            .timeout(timeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final seconds = int.tryParse(response.headers['retry-after'] ?? '');
          final error = RelayPublishException(
            response.body.isEmpty
                ? 'HTTP ${response.statusCode}'
                : response.body,
            statusCode: response.statusCode,
            retryAfter: seconds == null ? null : Duration(seconds: seconds),
          );
          if (!error.isRetryable || attempt == maxAttempts - 1) throw error;
          await Future<void>.delayed(error.retryAfter ?? retryDelay);
          continue;
        }
        return;
      } on TimeoutException catch (error) {
        if (attempt == maxAttempts - 1) {
          throw RelayPublishException(
            'ntfy did not respond within ${timeout.inSeconds} seconds: $error',
          );
        }
        await Future<void>.delayed(retryDelay * (attempt + 1));
      } on http.ClientException catch (error) {
        if (attempt == maxAttempts - 1) {
          throw RelayPublishException('ntfy connection failed: $error');
        }
        await Future<void>.delayed(retryDelay * (attempt + 1));
      }
    }
  }
}

/// Pulls cached Packet events before a live WebSocket subscription starts.
///
/// ntfy returns newline-delimited JSON from its polling endpoint. The adapter
/// deliberately exposes decoded Packets only; keepalive and non-message events
/// are ignored in the same way as the live subscription.
class NtfyPacketPoller {
  NtfyPacketPoller({
    required this.server,
    required this.channel,
    this.credentials,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  final Uri server;
  final String channel;
  final NtfyCredentials? credentials;
  final Duration timeout;
  final http.Client _client;

  Future<List<Packet>> poll({required DateTime since}) async {
    final sinceSeconds = since.toUtc().millisecondsSinceEpoch ~/ 1000;
    final uri = ntfyTopicUri(server, channel, suffix: '/json').replace(
      queryParameters: <String, String>{'poll': '1', 'since': '$sinceSeconds'},
    );
    final response = await _client
        .get(
          uri,
          headers: <String, String>{
            if (credentials != null)
              'Authorization': credentials!.authorizationHeader,
            'Accept': 'application/x-ndjson, application/json',
          },
        )
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NtfyPollException(
        response.body.isEmpty ? 'HTTP ${response.statusCode}' : response.body,
        statusCode: response.statusCode,
      );
    }
    final packets = <Packet>[];
    for (final line in const LineSplitter().convert(response.body)) {
      if (line.trim().isEmpty) continue;
      final packet = decodeNtfyPacketEvent(line);
      if (packet != null) packets.add(packet);
    }
    return packets;
  }
}

class NtfyPollException implements Exception {
  const NtfyPollException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      'ntfy poll failed${statusCode == null ? '' : ' ($statusCode)'}: $message';
}

class NtfyPacketSubscription {
  NtfyPacketSubscription({
    required this.server,
    required this.channel,
    this.credentials,
    WebSocketConnector? connect,
  }) : _connect = connect ?? platform.connectNtfyWebSocket;

  final Uri server;
  final String channel;
  final NtfyCredentials? credentials;
  final WebSocketConnector _connect;

  Stream<Packet> listen() async* {
    final uri = ntfyTopicUri(
      server.replace(scheme: server.scheme == 'https' ? 'wss' : 'ws'),
      channel,
      suffix: '/ws',
    );
    final socket = _connect(
      uri,
      headers: <String, String>{
        if (credentials != null)
          'Authorization': credentials!.authorizationHeader,
      },
    );
    await for (final value in socket.stream) {
      if (value is! String) continue;
      final packet = decodeNtfyPacketEvent(value);
      if (packet != null) yield packet;
    }
  }
}

class NtfyJsonSubscription {
  NtfyJsonSubscription({
    required this.server,
    required this.channel,
    this.credentials,
    WebSocketConnector? connect,
  }) : _connect = connect ?? platform.connectNtfyWebSocket;

  final Uri server;
  final String channel;
  final NtfyCredentials? credentials;
  final WebSocketConnector _connect;

  Stream<Map<String, Object?>> listen() async* {
    final uri = ntfyTopicUri(
      server.replace(scheme: server.scheme == 'https' ? 'wss' : 'ws'),
      channel,
      suffix: '/ws',
    );
    final socket = _connect(
      uri,
      headers: <String, String>{
        if (credentials != null)
          'Authorization': credentials!.authorizationHeader,
      },
    );
    await for (final value in socket.stream) {
      if (value is! String) continue;
      final body = decodeNtfyMessageEvent(value);
      if (body == null) continue;
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException('relay message is not an object');
      }
      yield Map<String, Object?>.from(decoded);
    }
  }
}

typedef WebSocketConnector = WebSocketChannel Function(
  Uri uri, {
  Map<String, String>? headers,
});

Packet? decodeNtfyPacketEvent(String value) {
  final body = decodeNtfyMessageEvent(value);
  return body == null ? null : Packet.decode(body);
}

String? decodeNtfyMessageEvent(String value) {
  final decoded = jsonDecode(value);
  if (decoded is! Map) {
    throw const FormatException('ntfy event must be an object');
  }
  if (decoded['event'] != 'message') return null;
  final message = decoded['message'];
  if (message is! String) {
    throw const FormatException('ntfy message event has no body');
  }
  return message;
}
