import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dartloom_messaging/dartloom_messaging.dart';
import 'package:test/test.dart';

void main() {
  test('resumable sender reads and sends only missing chunks', () async {
    final bytes = Uint8List.fromList(List<int>.generate(11, (index) => index));
    final source = _TrackingSource(bytes);
    final manifest = AttachmentChunker(chunkSize: 4).manifest(
      messageId: 'message-1',
      attachmentId: 'attachment-1',
      name: 'data.bin',
      mimeType: 'application/octet-stream',
      plaintext: bytes,
    );
    final chunks = <AttachmentChunk>[];
    final report =
        await ResumableAttachmentSender(
          chunker: const AttachmentChunker(chunkSize: 4),
        ).send(
          manifest: manifest,
          source: source,
          key: await AesGcm.with256bits().newSecretKey(),
          missingChunks: (_) async => {0, 2},
          sendChunk: (chunk) async => chunks.add(chunk),
        );

    expect(report.totalChunks, 3);
    expect(report.sentChunks, 2);
    expect(report.skippedChunks, 1);
    expect(chunks.map((chunk) => chunk.index), [0, 2]);
    expect(source.readRanges, [(0, 4), (8, 3)]);
    expect(source.maxReadLength, 4);
  });

  test('receiver accepts chunks out of order and commits atomically', () async {
    final bytes = Uint8List.fromList(List<int>.generate(10, (index) => index));
    final chunker = const AttachmentChunker(chunkSize: 4);
    final manifest = AttachmentChunker(chunkSize: 4).manifest(
      messageId: 'message-2',
      attachmentId: 'attachment-2',
      plaintext: bytes,
    );
    final key = await AesGcm.with256bits().newSecretKey();
    final encrypted = await chunker.encryptAndSplit(
      manifest: manifest,
      plaintext: bytes,
      key: key,
    );
    final sink = MemoryAttachmentSink();
    final receiver = ResumableAttachmentReceiver(
      manifest: manifest,
      sink: sink,
      key: key,
    );
    await receiver.begin();
    expect(await receiver.add(encrypted[2]), isTrue);
    expect(await receiver.add(encrypted[0]), isTrue);
    expect(await receiver.add(encrypted[1]), isTrue);
    expect(await receiver.add(encrypted[1]), isFalse);
    expect(await receiver.receivedChunkIndexes(), {0, 1, 2});
    await receiver.commit();
    expect(sink.isCommitted(manifest), isTrue);
  });

  test('receiver refuses incomplete or tampered transfers', () async {
    final bytes = Uint8List.fromList(List<int>.generate(9, (index) => index));
    final manifest = const AttachmentChunker(chunkSize: 4).manifest(
      messageId: 'message-3',
      attachmentId: 'attachment-3',
      plaintext: bytes,
    );
    final key = await AesGcm.with256bits().newSecretKey();
    final chunks = await const AttachmentChunker(chunkSize: 4)
        .encryptAndSplit(manifest: manifest, plaintext: bytes, key: key);
    final sink = MemoryAttachmentSink();
    final receiver = ResumableAttachmentReceiver(
      manifest: manifest,
      sink: sink,
      key: key,
    );
    await receiver.begin();
    await receiver.add(chunks.first);
    await expectLater(receiver.commit(), throwsStateError);
    await receiver.abort();
    expect(await receiver.receivedChunkIndexes(), isEmpty);
  });
}

class _TrackingSource implements AttachmentSource {
  _TrackingSource(this.bytes);

  final Uint8List bytes;
  final List<(int, int)> readRanges = [];
  int maxReadLength = 0;

  @override
  int get byteLength => bytes.length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    readRanges.add((offset, length));
    if (length > maxReadLength) maxReadLength = length;
    return Uint8List.fromList(bytes.sublist(offset, offset + length));
  }
}
