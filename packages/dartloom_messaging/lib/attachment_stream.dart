import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'attachment_chunks.dart';

/// A re-openable byte source used by resumable attachment transfers.
///
/// [read] must return exactly [length] bytes unless the requested range ends
/// at [byteLength]. Implementations may read from a file, an object store, or
/// another platform-specific source without exposing that detail to the
/// messaging capability.
abstract interface class AttachmentSource {
  int get byteLength;

  Future<Uint8List> read(int offset, int length);
}

Future<AttachmentManifest> manifestForSource({
  required String messageId,
  required String attachmentId,
  required AttachmentSource source,
  int chunkSize = 256 * 1024,
  String name = '',
  String mimeType = '',
}) async {
  if (chunkSize <= 0) throw ArgumentError.value(chunkSize, 'chunkSize');
  final hashSink = Sha256().newHashSink();
  for (var offset = 0; offset < source.byteLength; offset += chunkSize) {
    final length = math.min(chunkSize, source.byteLength - offset);
    final bytes = await source.read(offset, length);
    if (bytes.length != length) {
      throw StateError('attachment source returned an invalid chunk length');
    }
    hashSink.add(bytes);
  }
  hashSink.close();
  final digest = await hashSink.hash();
  return AttachmentManifest(
    messageId: messageId,
    attachmentId: attachmentId,
    byteLength: source.byteLength,
    chunkSize: chunkSize,
    sha256: digest.bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join(),
    name: name,
    mimeType: mimeType,
  );
}

class MemoryAttachmentSource implements AttachmentSource {
  MemoryAttachmentSource(List<int> bytes) : _bytes = Uint8List.fromList(bytes);

  final Uint8List _bytes;

  @override
  int get byteLength => _bytes.length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    if (offset < 0 || length < 0 || offset + length > _bytes.length) {
      throw RangeError('attachment source range is outside the source');
    }
    return Uint8List.fromList(_bytes.sublist(offset, offset + length));
  }
}

/// A random-access sink. Implementations are expected to persist chunks so a
/// process restart can resume from [receivedChunkIndexes].
abstract interface class AttachmentSink {
  Future<void> begin(AttachmentManifest manifest);

  Future<Set<int>> receivedChunkIndexes(AttachmentManifest manifest);

  Future<void> writeChunk(
    AttachmentManifest manifest,
    int index,
    Uint8List plaintext,
  );

  Future<Uint8List> readChunk(AttachmentManifest manifest, int index);

  Future<void> commit(AttachmentManifest manifest);

  Future<void> abort(AttachmentManifest manifest);
}

class MemoryAttachmentSink implements AttachmentSink {
  final Map<String, Map<int, Uint8List>> _chunks = {};
  final Set<String> _committed = {};

  @override
  Future<void> begin(AttachmentManifest manifest) async {
    _chunks.putIfAbsent(_key(manifest), () => <int, Uint8List>{});
  }

  @override
  Future<Set<int>> receivedChunkIndexes(AttachmentManifest manifest) async =>
      Set<int>.of(_chunks[_key(manifest)]?.keys ?? const <int>{});

  @override
  Future<void> writeChunk(
    AttachmentManifest manifest,
    int index,
    Uint8List plaintext,
  ) async {
    _validateChunk(manifest, index, plaintext.length);
    final chunks = _chunks[_key(manifest)];
    if (chunks == null) throw StateError('attachment sink was not started');
    chunks[index] = Uint8List.fromList(plaintext);
  }

  @override
  Future<Uint8List> readChunk(AttachmentManifest manifest, int index) async {
    final value = _chunks[_key(manifest)]?[index];
    if (value == null) throw StateError('attachment chunk is not available');
    return Uint8List.fromList(value);
  }

  @override
  Future<void> commit(AttachmentManifest manifest) async {
    final chunks = _chunks[_key(manifest)];
    if (chunks == null || chunks.length != manifest.totalChunks) {
      throw StateError('attachment is incomplete');
    }
    _committed.add(_key(manifest));
  }

  @override
  Future<void> abort(AttachmentManifest manifest) async {
    _chunks.remove(_key(manifest));
    _committed.remove(_key(manifest));
  }

  bool isCommitted(AttachmentManifest manifest) =>
      _committed.contains(_key(manifest));
}

class AttachmentTransferReport {
  const AttachmentTransferReport({
    required this.totalChunks,
    required this.sentChunks,
    required this.skippedChunks,
  });

  final int totalChunks;
  final int sentChunks;
  final int skippedChunks;
}

typedef AttachmentMissingChunks = Future<Set<int>> Function(
  AttachmentManifest manifest,
);
typedef AttachmentChunkSender = Future<void> Function(AttachmentChunk chunk);

/// Sends only chunks missing at the receiver. The source is read one chunk at
/// a time and can therefore represent files much larger than memory.
class ResumableAttachmentSender {
  ResumableAttachmentSender({this.chunker = const AttachmentChunker()});

  final AttachmentChunker chunker;

  Future<AttachmentTransferReport> send({
    required AttachmentManifest manifest,
    required AttachmentSource source,
    required SecretKey key,
    required AttachmentMissingChunks missingChunks,
    required AttachmentChunkSender sendChunk,
  }) async {
    if (source.byteLength != manifest.byteLength) {
      throw ArgumentError('source length does not match manifest');
    }
    final missing = await missingChunks(manifest);
    final validMissing = missing
        .where((index) => index >= 0 && index < manifest.totalChunks)
        .toSet();
    var sent = 0;
    for (final index in validMissing.toList()..sort()) {
      final offset = index * manifest.chunkSize;
      final length = math.min(manifest.chunkSize, manifest.byteLength - offset);
      final plaintext = await source.read(offset, length);
      if (plaintext.length != length) {
        throw StateError('attachment source returned an invalid chunk length');
      }
      final chunk = await chunker.encryptChunk(
        manifest: manifest,
        plaintext: plaintext,
        index: index,
        key: key,
      );
      await sendChunk(chunk);
      sent++;
    }
    return AttachmentTransferReport(
      totalChunks: manifest.totalChunks,
      sentChunks: sent,
      skippedChunks: manifest.totalChunks - sent,
    );
  }
}

/// Receives encrypted chunks into a random-access sink and commits only after
/// all chunks and the final SHA-256 digest have been verified.
class ResumableAttachmentReceiver {
  ResumableAttachmentReceiver({
    required this.manifest,
    required this.sink,
    required this.key,
  });

  final AttachmentManifest manifest;
  final AttachmentSink sink;
  final SecretKey key;
  final AttachmentChunker chunker = const AttachmentChunker();

  Future<void> begin() => sink.begin(manifest);

  Future<Set<int>> receivedChunkIndexes() =>
      sink.receivedChunkIndexes(manifest);

  Future<bool> add(AttachmentChunk chunk) async {
    if (await sink
        .receivedChunkIndexes(manifest)
        .then((indexes) => indexes.contains(chunk.index))) {
      return false;
    }
    final plaintext = await chunker.decryptChunk(
      manifest: manifest,
      chunk: chunk,
      key: key,
    );
    await sink.writeChunk(manifest, chunk.index, plaintext);
    return true;
  }

  Future<void> commit() async {
    final indexes = await sink.receivedChunkIndexes(manifest);
    if (indexes.length != manifest.totalChunks ||
        indexes.any((index) => index < 0 || index >= manifest.totalChunks)) {
      throw StateError('attachment transfer is incomplete');
    }
    final digestSink = Sha256().newHashSink();
    for (var index = 0; index < manifest.totalChunks; index++) {
      digestSink.add(await sink.readChunk(manifest, index));
    }
    digestSink.close();
    final digest = await digestSink.hash();
    if (digest.bytes
            .map((value) => value.toRadixString(16).padLeft(2, '0'))
            .join() !=
        manifest.sha256) {
      throw StateError('attachment integrity check failed');
    }
    await sink.commit(manifest);
  }

  Future<void> abort() => sink.abort(manifest);
}

String _key(AttachmentManifest manifest) =>
    '${manifest.messageId}\u0000${manifest.attachmentId}';

void _validateChunk(AttachmentManifest manifest, int index, int length) {
  if (index < 0 || index >= manifest.totalChunks) {
    throw RangeError('attachment chunk index is outside the manifest');
  }
  final expected = math.min(
    manifest.chunkSize,
    manifest.byteLength - index * manifest.chunkSize,
  );
  if (length != expected) throw StateError('attachment chunk length mismatch');
}
