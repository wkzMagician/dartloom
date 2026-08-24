import 'package:dartloom_messaging/dartloom_messaging.dart';
import 'package:test/test.dart';

void main() {
  final manifest = AttachmentManifest(
    messageId: 'message-1',
    attachmentId: 'attachment-1',
    byteLength: 9,
    chunkSize: 4,
    sha256: 'hash',
    name: 'secret.txt',
    mimeType: 'text/plain',
  );

  test('offer round trips through generic protocol decoder', () {
    final offer = AttachmentOffer(
      transferId: 'transfer-1',
      manifests: [manifest],
    );
    final decoded = AttachmentProtocolMessage.fromJson(offer.toJson());
    expect(decoded, isA<AttachmentOffer>());
    expect((decoded as AttachmentOffer).manifests.single.name, 'secret.txt');
  });

  test('resume preserves compact missing ranges', () {
    final resume = AttachmentResume(
      transferId: 'transfer-1',
      missing: {
        'attachment-1': const [
          ChunkRange(start: 0, count: 2),
          ChunkRange(start: 4, count: 1),
        ],
      },
    );
    final decoded =
        AttachmentProtocolMessage.fromJson(resume.toJson()) as AttachmentResume;
    expect(decoded.missing['attachment-1']!.first.endExclusive, 2);
  });

  test('chunk reference and commit round trip', () {
    final reference = AttachmentChunkReference(
      transferId: 'transfer-1',
      attachmentId: 'attachment-1',
      index: 2,
      blob: BlobReference(
        provider: 'ntfy',
        uri: Uri.parse('https://relay.example/file/random'),
        byteLength: 100,
      ),
    );
    expect(
      AttachmentProtocolMessage.fromJson(reference.toJson()),
      isA<AttachmentChunkReference>(),
    );
    expect(
      AttachmentProtocolMessage.fromJson(
        AttachmentCommit(transferId: 'transfer-1').toJson(),
      ),
      isA<AttachmentCommit>(),
    );
  });

  test('protocol rejects unknown versions and fields', () {
    expect(
      () => AttachmentProtocolMessage.fromJson({
        ...AttachmentCommit(transferId: 'transfer-1').toJson(),
        'version': 1,
      }),
      throwsFormatException,
    );
    expect(
      () => AttachmentProtocolMessage.fromJson({
        ...AttachmentCommit(transferId: 'transfer-1').toJson(),
        'extra': true,
      }),
      throwsFormatException,
    );
  });
}
