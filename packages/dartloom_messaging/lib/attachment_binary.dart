import 'dart:typed_data';

import 'attachment_chunks.dart';

/// Versioned binary wire format for one independently encrypted attachment
/// chunk. It avoids the Base64 expansion of [AttachmentChunk.toJson].
class AttachmentChunkBinaryCodec {
  const AttachmentChunkBinaryCodec({
    this.maxCiphertextLength = 15 * 1024 * 1024,
  });

  static const int version = 1;
  static const int _fixedHeaderLength = 20;
  static const List<int> _magic = <int>[0x44, 0x4c, 0x4d, 0x42]; // DLMB

  final int maxCiphertextLength;

  Uint8List encode(AttachmentChunk chunk) {
    _validateLengths(chunk);
    final result = Uint8List(
      _fixedHeaderLength +
          chunk.nonce.length +
          chunk.authenticationTag.length +
          chunk.ciphertext.length,
    );
    result.setRange(0, _magic.length, _magic);
    final data = result.buffer.asByteData();
    data.setUint8(4, version);
    data.setUint8(5, chunk.nonce.length);
    data.setUint8(6, chunk.authenticationTag.length);
    data.setUint8(7, 0);
    data.setUint32(8, chunk.index, Endian.big);
    data.setUint32(12, chunk.total, Endian.big);
    data.setUint32(16, chunk.ciphertext.length, Endian.big);
    var offset = _fixedHeaderLength;
    result.setRange(offset, offset + chunk.nonce.length, chunk.nonce);
    offset += chunk.nonce.length;
    result.setRange(
      offset,
      offset + chunk.authenticationTag.length,
      chunk.authenticationTag,
    );
    offset += chunk.authenticationTag.length;
    result.setRange(offset, result.length, chunk.ciphertext);
    return result;
  }

  AttachmentChunk decode(
    List<int> value, {
    required String messageId,
    required String attachmentId,
  }) {
    if (messageId.isEmpty || attachmentId.isEmpty) {
      throw const FormatException('chunk identity is required');
    }
    final bytes = Uint8List.fromList(value);
    if (bytes.length < _fixedHeaderLength ||
        !_matchesMagic(bytes) ||
        bytes[4] != version) {
      throw const FormatException('unsupported attachment chunk format');
    }
    final data = bytes.buffer.asByteData();
    final nonceLength = data.getUint8(5);
    final tagLength = data.getUint8(6);
    if (data.getUint8(7) != 0) {
      throw const FormatException('attachment chunk flags are unsupported');
    }
    final index = data.getUint32(8, Endian.big);
    final total = data.getUint32(12, Endian.big);
    final ciphertextLength = data.getUint32(16, Endian.big);
    if (nonceLength != 12 || tagLength != 16) {
      throw const FormatException('attachment chunk crypto fields are invalid');
    }
    if (total == 0 || index >= total) {
      throw const FormatException('attachment chunk index is invalid');
    }
    if (ciphertextLength > maxCiphertextLength ||
        bytes.length !=
            _fixedHeaderLength + nonceLength + tagLength + ciphertextLength) {
      throw const FormatException('attachment chunk length is invalid');
    }
    var offset = _fixedHeaderLength;
    final nonce = Uint8List.fromList(
      bytes.sublist(offset, offset + nonceLength),
    );
    offset += nonceLength;
    final tag = Uint8List.fromList(bytes.sublist(offset, offset + tagLength));
    offset += tagLength;
    return AttachmentChunk(
      messageId: messageId,
      attachmentId: attachmentId,
      index: index,
      total: total,
      nonce: nonce,
      authenticationTag: tag,
      ciphertext: Uint8List.fromList(bytes.sublist(offset)),
    );
  }

  bool _matchesMagic(Uint8List bytes) {
    for (var index = 0; index < _magic.length; index++) {
      if (bytes[index] != _magic[index]) return false;
    }
    return true;
  }

  void _validateLengths(AttachmentChunk chunk) {
    if (chunk.index < 0 || chunk.total <= 0 || chunk.index >= chunk.total) {
      throw ArgumentError('attachment chunk index is invalid');
    }
    if (chunk.nonce.length != 12 || chunk.authenticationTag.length != 16) {
      throw ArgumentError('attachment chunk crypto fields are invalid');
    }
    if (chunk.ciphertext.length > maxCiphertextLength) {
      throw ArgumentError('attachment chunk is larger than the codec limit');
    }
  }
}
