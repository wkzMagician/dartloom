import 'dart:convert';
import 'dart:typed_data';

import 'package:dartloom_messaging/dartloom_messaging.dart';
import 'package:http/http.dart' as http;

import 'ntfy_auth.dart';
import 'ntfy_uri.dart';

class NtfyBlobStore implements BlobStore {
  NtfyBlobStore({
    required this.server,
    required this.credentials,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  final Uri server;
  final NtfyCredentials credentials;
  final Duration timeout;
  final http.Client _client;

  @override
  Future<BlobReference> put({
    required String channel,
    required String objectId,
    required Uint8List bytes,
  }) async {
    if (objectId.isEmpty || objectId.contains(RegExp(r'[/\\\s]'))) {
      throw ArgumentError.value(objectId, 'objectId', 'must be an opaque ID');
    }
    final response = await _client
        .post(
          ntfyTopicUri(server, channel),
          headers: <String, String>{
            'Authorization': credentials.authorizationHeader,
            'Content-Type': 'application/octet-stream',
            'Filename': '$objectId.dlmb',
          },
          body: bytes,
        )
        .timeout(timeout);
    _throwForResponse(response);
    try {
      final body = jsonDecode(response.body);
      final attachment = body is Map ? attachmentMap(body['attachment']) : null;
      final urlText = attachment?['url'];
      final uri = urlText is String ? Uri.tryParse(urlText) : null;
      if (uri == null || !ntfyReferenceBelongsToServer(server, uri)) {
        throw const FormatException('attachment URL is outside the server');
      }
      final size = attachment?['size'];
      final expires = attachment?['expires'];
      return BlobReference(
        provider: 'ntfy',
        uri: uri,
        byteLength: size is int ? size : bytes.length,
        expiresAt: expires is int
            ? DateTime.fromMillisecondsSinceEpoch(expires * 1000, isUtc: true)
            : null,
      );
    } on BlobStoreException {
      rethrow;
    } on Object catch (error) {
      throw BlobStoreException('invalid ntfy upload response: $error');
    }
  }

  @override
  Future<Uint8List> get(BlobReference reference) async {
    if (reference.provider != 'ntfy' ||
        !ntfyReferenceBelongsToServer(server, reference.uri)) {
      throw const BlobStoreException(
        'blob reference is outside the configured ntfy server',
      );
    }
    final response = await _client
        .get(
          reference.uri,
          headers: <String, String>{
            'Authorization': credentials.authorizationHeader,
          },
        )
        .timeout(timeout);
    _throwForResponse(response);
    if (response.bodyBytes.length != reference.byteLength) {
      throw const BlobStoreException('downloaded blob length does not match');
    }
    return Uint8List.fromList(response.bodyBytes);
  }
}

Map<String, Object?>? attachmentMap(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : null;

void _throwForResponse(http.Response response) {
  if (response.statusCode >= 200 && response.statusCode < 300) return;
  final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
  throw BlobStoreException(
    response.body.isEmpty ? 'HTTP ${response.statusCode}' : response.body,
    statusCode: response.statusCode,
    retryAfter: retryAfter == null ? null : Duration(seconds: retryAfter),
  );
}
