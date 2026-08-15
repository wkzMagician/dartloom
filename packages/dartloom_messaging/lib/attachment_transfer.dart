import 'attachment_chunks.dart';

class AttachmentTransferException implements Exception {
  const AttachmentTransferException(this.message);

  final String message;

  @override
  String toString() => 'Attachment transfer error: $message';
}

class PendingAttachmentTransfer {
  PendingAttachmentTransfer({required this.manifest, required this.createdAt})
      : reassembler = AttachmentReassembler(manifest);

  final AttachmentManifest manifest;
  final DateTime createdAt;
  final AttachmentReassembler reassembler;
}

/// Keeps incoming chunks until the manifest, authentication and hash checks
/// all succeed. Incomplete transfers expire after the configured duration.
class MemoryAttachmentTransferStore {
  MemoryAttachmentTransferStore({
    this.clock = _now,
    this.expiry = const Duration(hours: 24),
  });

  final DateTime Function() clock;
  final Duration expiry;
  final Map<String, PendingAttachmentTransfer> _pending = {};

  void begin(AttachmentManifest manifest) {
    if (manifest.messageId.isEmpty || manifest.attachmentId.isEmpty) {
      throw const AttachmentTransferException('manifest identity is required');
    }
    _pending[_manifestKey(manifest)] = PendingAttachmentTransfer(
      manifest: manifest,
      createdAt: clock().toUtc(),
    );
  }

  void add(AttachmentChunk chunk) {
    final transfer = _pending[_chunkKey(chunk)];
    if (transfer == null) {
      throw const AttachmentTransferException('manifest is not registered');
    }
    try {
      transfer.reassembler.add(chunk);
    } on Object catch (error) {
      throw AttachmentTransferException(error.toString());
    }
  }

  bool isComplete(String messageId, String attachmentId) =>
      _pending[_keyValues(messageId, attachmentId)]?.reassembler.isComplete ??
      false;

  List<int> assemble(String messageId, String attachmentId) {
    final transfer = _pending[_keyValues(messageId, attachmentId)];
    if (transfer == null) {
      throw const AttachmentTransferException('manifest is not registered');
    }
    try {
      final bytes = transfer.reassembler.assemble();
      _pending.remove(_manifestKey(transfer.manifest));
      return bytes;
    } on Object catch (error) {
      throw AttachmentTransferException(error.toString());
    }
  }

  int purgeExpired() {
    final cutoff = clock().toUtc().subtract(expiry);
    final expired = _pending.entries
        .where((entry) => entry.value.createdAt.isBefore(cutoff))
        .map((entry) => entry.key)
        .toList();
    for (final key in expired) {
      _pending.remove(key);
    }
    return expired.length;
  }

  int get pendingCount => _pending.length;
}

String _manifestKey(AttachmentManifest manifest) =>
    _keyValues(manifest.messageId, manifest.attachmentId);

String _chunkKey(AttachmentChunk chunk) =>
    _keyValues(chunk.messageId, chunk.attachmentId);

String _keyValues(String messageId, String attachmentId) =>
    '$messageId\u0000$attachmentId';

DateTime _now() => DateTime.now().toUtc();
