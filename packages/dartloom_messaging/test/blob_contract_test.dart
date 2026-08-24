import 'dart:typed_data';

import 'package:dartloom_messaging/dartloom_messaging.dart';
import 'package:test/test.dart';

void main() {
  test('blob reference JSON round trips without transport knowledge', () {
    final reference = BlobReference(
      provider: 'ntfy',
      uri: Uri.parse('https://relay.example/file/random-id'),
      byteLength: 123,
      expiresAt: DateTime.utc(2026, 9, 1),
    );
    final decoded = BlobReference.fromJson(reference.toJson());
    expect(decoded.provider, 'ntfy');
    expect(decoded.uri, reference.uri);
    expect(decoded.byteLength, 123);
    expect(decoded.expiresAt, DateTime.utc(2026, 9, 1));
  });

  test('encrypted attachment chunk has a versioned binary round trip', () {
    final chunk = AttachmentChunk(
      messageId: 'message-1',
      attachmentId: 'attachment-1',
      index: 2,
      total: 4,
      nonce: Uint8List.fromList(List<int>.generate(12, (index) => index)),
      authenticationTag: Uint8List.fromList(
        List<int>.generate(16, (index) => 16 - index),
      ),
      ciphertext: Uint8List.fromList([9, 8, 7, 6]),
    );
    const codec = AttachmentChunkBinaryCodec();
    final bytes = codec.encode(chunk);
    final decoded = codec.decode(
      bytes,
      messageId: chunk.messageId,
      attachmentId: chunk.attachmentId,
    );
    expect(decoded.index, chunk.index);
    expect(decoded.total, chunk.total);
    expect(decoded.nonce, chunk.nonce);
    expect(decoded.authenticationTag, chunk.authenticationTag);
    expect(decoded.ciphertext, chunk.ciphertext);
  });

  test('binary chunk decoder rejects truncation and tampering', () {
    final chunk = AttachmentChunk(
      messageId: 'message-1',
      attachmentId: 'attachment-1',
      index: 0,
      total: 1,
      nonce: Uint8List(12),
      authenticationTag: Uint8List(16),
      ciphertext: Uint8List.fromList([1, 2, 3]),
    );
    const codec = AttachmentChunkBinaryCodec();
    final bytes = codec.encode(chunk);
    expect(
      () => codec.decode(
        bytes.sublist(0, bytes.length - 1),
        messageId: chunk.messageId,
        attachmentId: chunk.attachmentId,
      ),
      throwsFormatException,
    );
    bytes[0] = 0;
    expect(
      () => codec.decode(
        bytes,
        messageId: chunk.messageId,
        attachmentId: chunk.attachmentId,
      ),
      throwsFormatException,
    );
  });
}
