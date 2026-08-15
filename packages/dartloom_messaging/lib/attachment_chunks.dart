import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

class AttachmentManifest {
  const AttachmentManifest({
    required this.messageId,
    required this.attachmentId,
    required this.byteLength,
    required this.chunkSize,
    required this.sha256,
    this.name = '',
    this.mimeType = '',
  });

  final String messageId;
  final String attachmentId;
  final int byteLength;
  final int chunkSize;
  final String sha256;

  /// Optional descriptive metadata; the capability does not interpret it.
  final String name;
  final String mimeType;

  int get totalChunks => max(1, (byteLength + chunkSize - 1) ~/ chunkSize);

  Map<String, Object?> toJson() => <String, Object?>{
        'messageId': messageId,
        'attachmentId': attachmentId,
        'byteLength': byteLength,
        'chunkSize': chunkSize,
        'sha256': sha256,
        if (name.isNotEmpty) 'name': name,
        if (mimeType.isNotEmpty) 'mimeType': mimeType,
      };

  factory AttachmentManifest.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('manifest must be an object');
    }
    final json = Map<String, Object?>.from(value);
    return AttachmentManifest(
      messageId: _requiredText(json['messageId'], 'messageId'),
      attachmentId: _requiredText(json['attachmentId'], 'attachmentId'),
      byteLength: _nonNegative(json['byteLength'], 'byteLength'),
      chunkSize: _positive(json['chunkSize'], 'chunkSize'),
      sha256: _requiredText(json['sha256'], 'sha256'),
      name: _optionalText(json['name'], 'name'),
      mimeType: _optionalText(json['mimeType'], 'mimeType'),
    );
  }
}

class AttachmentChunk {
  const AttachmentChunk({
    required this.messageId,
    required this.attachmentId,
    required this.index,
    required this.total,
    required this.ciphertext,
    required this.nonce,
    required this.authenticationTag,
  });

  final String messageId;
  final String attachmentId;
  final int index;
  final int total;
  final Uint8List ciphertext;
  final Uint8List nonce;
  final Uint8List authenticationTag;

  Map<String, Object?> toJson() => <String, Object?>{
        'messageId': messageId,
        'attachmentId': attachmentId,
        'index': index,
        'total': total,
        'ciphertext': base64UrlEncode(ciphertext),
        'nonce': base64UrlEncode(nonce),
        'authenticationTag': base64UrlEncode(authenticationTag),
      };

  factory AttachmentChunk.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('chunk must be an object');
    final json = Map<String, Object?>.from(value);
    return AttachmentChunk(
      messageId: _requiredText(json['messageId'], 'messageId'),
      attachmentId: _requiredText(json['attachmentId'], 'attachmentId'),
      index: _nonNegative(json['index'], 'index'),
      total: _positive(json['total'], 'total'),
      ciphertext: _bytes(json['ciphertext'], 'ciphertext'),
      nonce: _bytes(json['nonce'], 'nonce'),
      authenticationTag: _bytes(json['authenticationTag'], 'authenticationTag'),
    );
  }
}

class AttachmentChunker {
  const AttachmentChunker({this.chunkSize = 256 * 1024});

  final int chunkSize;

  AttachmentManifest manifest({
    required String messageId,
    required String attachmentId,
    String name = '',
    String mimeType = '',
    required Uint8List plaintext,
  }) {
    if (chunkSize <= 0) throw ArgumentError.value(chunkSize, 'chunkSize');
    return AttachmentManifest(
      messageId: messageId,
      attachmentId: attachmentId,
      byteLength: plaintext.length,
      chunkSize: chunkSize,
      sha256: sha256.convert(plaintext).toString(),
      name: name,
      mimeType: mimeType,
    );
  }

  /// Splits an already-authenticated byte stream for compatibility with
  /// callers that perform authentication at a higher protocol layer.
  List<AttachmentChunk> split({
    required AttachmentManifest manifest,
    required Uint8List encryptedBytes,
  }) {
    if (encryptedBytes.length != manifest.byteLength) {
      throw ArgumentError(
        'encrypted attachment length does not match manifest',
      );
    }
    return [
      for (var index = 0; index < manifest.totalChunks; index++)
        AttachmentChunk(
          messageId: manifest.messageId,
          attachmentId: manifest.attachmentId,
          index: index,
          total: manifest.totalChunks,
          ciphertext: Uint8List.fromList(
            encryptedBytes.sublist(
              index * manifest.chunkSize,
              min((index + 1) * manifest.chunkSize, encryptedBytes.length),
            ),
          ),
          nonce: Uint8List(0),
          authenticationTag: Uint8List(16),
        ),
    ];
  }

  Future<List<AttachmentChunk>> encryptAndSplit({
    required AttachmentManifest manifest,
    required Uint8List plaintext,
    required SecretKey key,
  }) async {
    if (plaintext.length != manifest.byteLength) {
      throw ArgumentError('plaintext length does not match manifest');
    }
    final cipher = AesGcm.with256bits();
    final random = Random.secure();
    return [
      for (var index = 0; index < manifest.totalChunks; index++)
        await _encryptChunk(
          cipher: cipher,
          random: random,
          manifest: manifest,
          plaintext: plaintext.sublist(
            index * manifest.chunkSize,
            min((index + 1) * manifest.chunkSize, plaintext.length),
          ),
          index: index,
          key: key,
        ),
    ];
  }

  Future<AttachmentChunk> _encryptChunk({
    required AesGcm cipher,
    required Random random,
    required AttachmentManifest manifest,
    required List<int> plaintext,
    required int index,
    required SecretKey key,
  }) async {
    final nonce = Uint8List.fromList(
      List<int>.generate(12, (_) => random.nextInt(256)),
    );
    final box = await cipher.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
      aad: _aad(manifest, index),
    );
    return AttachmentChunk(
      messageId: manifest.messageId,
      attachmentId: manifest.attachmentId,
      index: index,
      total: manifest.totalChunks,
      ciphertext: Uint8List.fromList(box.cipherText),
      nonce: Uint8List.fromList(box.nonce),
      authenticationTag: Uint8List.fromList(box.mac.bytes),
    );
  }
}

class AttachmentReassembler {
  AttachmentReassembler(this.manifest);

  final AttachmentManifest manifest;
  final Map<int, AttachmentChunk> _chunks = {};

  bool get isComplete => _chunks.length == manifest.totalChunks;

  void add(AttachmentChunk chunk) {
    if (chunk.messageId != manifest.messageId ||
        chunk.attachmentId != manifest.attachmentId ||
        chunk.total != manifest.totalChunks ||
        chunk.index < 0 ||
        chunk.index >= manifest.totalChunks ||
        chunk.nonce.length != 12 ||
        chunk.authenticationTag.length != 16) {
      if (chunk.nonce.isEmpty && chunk.authenticationTag.length == 16) {
        if (chunk.messageId != manifest.messageId ||
            chunk.attachmentId != manifest.attachmentId ||
            chunk.total != manifest.totalChunks ||
            chunk.index < 0 ||
            chunk.index >= manifest.totalChunks) {
          throw ArgumentError('attachment chunk does not match manifest');
        }
        _chunks[chunk.index] = chunk;
        return;
      }
      throw ArgumentError('attachment chunk does not match manifest');
    }
    _chunks[chunk.index] = chunk;
  }

  Uint8List assemble() {
    if (!isComplete) throw StateError('attachment transfer is incomplete');
    if (_chunks.values.any((chunk) => chunk.nonce.isNotEmpty)) {
      throw StateError('encrypted chunks require decryptAndAssemble');
    }
    return _assemble([
      for (var index = 0; index < manifest.totalChunks; index++)
        _chunks[index]!.ciphertext,
    ]);
  }

  Future<Uint8List> decryptAndAssemble({required SecretKey key}) async {
    if (!isComplete) {
      throw StateError('attachment transfer is incomplete');
    }
    final cipher = AesGcm.with256bits();
    final bytes = <int>[];
    for (var index = 0; index < manifest.totalChunks; index++) {
      final chunk = _chunks[index]!;
      try {
        bytes.addAll(
          await cipher.decrypt(
            SecretBox(
              chunk.ciphertext,
              nonce: chunk.nonce,
              mac: Mac(chunk.authenticationTag),
            ),
            secretKey: key,
            aad: _aad(manifest, index),
          ),
        );
      } on SecretBoxAuthenticationError {
        throw StateError('attachment chunk authentication failed');
      }
    }
    final result = Uint8List.fromList(bytes);
    return _assemble([result]);
  }

  Uint8List _assemble(Iterable<Iterable<int>> parts) {
    if (!isComplete) throw StateError('attachment transfer is incomplete');
    final result = Uint8List.fromList([for (final part in parts) ...part]);
    if (result.length != manifest.byteLength ||
        sha256.convert(result).toString() != manifest.sha256) {
      throw StateError('attachment integrity check failed');
    }
    return result;
  }
}

List<int> _aad(AttachmentManifest manifest, int index) =>
    utf8.encode('${manifest.messageId}/${manifest.attachmentId}/$index');

String _requiredText(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$field must be a non-empty string');
  }
  return value;
}

String _optionalText(Object? value, String field) {
  if (value == null) return '';
  if (value is! String) throw FormatException('$field must be a string');
  return value;
}

int _positive(Object? value, String field) {
  if (value is! int || value <= 0) {
    throw FormatException('$field must be positive');
  }
  return value;
}

int _nonNegative(Object? value, String field) {
  if (value is! int || value < 0) {
    throw FormatException('$field must not be negative');
  }
  return value;
}

Uint8List _bytes(Object? value, String field) {
  if (value is! String) throw FormatException('$field must be base64url');
  try {
    return Uint8List.fromList(base64Url.decode(value));
  } on FormatException {
    throw FormatException('$field must be base64url');
  }
}
