import 'dart:typed_data';

/// Opaque reference to encrypted bytes stored by a transport adapter.
///
/// Applications must carry this value inside an encrypted [Packet] payload.
/// The generic messaging layer deliberately does not interpret the URI.
class BlobReference {
  const BlobReference({
    required this.provider,
    required this.uri,
    required this.byteLength,
    this.expiresAt,
  });

  final String provider;
  final Uri uri;
  final int byteLength;
  final DateTime? expiresAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'provider': provider,
    'uri': uri.toString(),
    'byteLength': byteLength,
    if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
  };

  factory BlobReference.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('blob reference must be an object');
    }
    final json = Map<String, Object?>.from(value);
    final provider = json['provider'];
    final uriText = json['uri'];
    final byteLength = json['byteLength'];
    final expiresAtText = json['expiresAt'];
    final uri = uriText is String ? Uri.tryParse(uriText) : null;
    final expiresAt = expiresAtText is String
        ? DateTime.tryParse(expiresAtText)?.toUtc()
        : null;
    if (provider is! String || provider.isEmpty) {
      throw const FormatException('blob provider is required');
    }
    if (uri == null || !uri.hasScheme) {
      throw const FormatException('blob URI is invalid');
    }
    if (byteLength is! int || byteLength < 0) {
      throw const FormatException('blob byteLength must be non-negative');
    }
    if (expiresAtText != null && expiresAt == null) {
      throw const FormatException('blob expiresAt must be ISO-8601');
    }
    final unknown = json.keys.where(
      (key) =>
          !const {'provider', 'uri', 'byteLength', 'expiresAt'}.contains(key),
    );
    if (unknown.isNotEmpty) {
      throw FormatException('unknown blob fields: ${unknown.join(', ')}');
    }
    return BlobReference(
      provider: provider,
      uri: uri,
      byteLength: byteLength,
      expiresAt: expiresAt,
    );
  }
}

/// Transport-owned storage for already encrypted binary objects.
///
/// Credentials and server configuration belong to the implementation. The
/// caller supplies only the logical channel, a random object identifier and
/// encrypted bytes.
abstract interface class BlobStore {
  Future<BlobReference> put({
    required String channel,
    required String objectId,
    required Uint8List bytes,
  });

  Future<Uint8List> get(BlobReference reference);
}

class BlobStoreException implements Exception {
  const BlobStoreException(this.message, {this.statusCode, this.retryAfter});

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
      'Blob store failed${statusCode == null ? '' : ' ($statusCode)'}: '
      '$message';
}
