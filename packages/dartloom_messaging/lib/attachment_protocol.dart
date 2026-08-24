import 'attachment_chunks.dart';
import 'blob_contracts.dart';

const attachmentProtocolVersion = 2;

sealed class AttachmentProtocolMessage {
  const AttachmentProtocolMessage({required this.transferId});

  final String transferId;
  String get type;

  Map<String, Object?> toJson();

  static AttachmentProtocolMessage fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('attachment protocol message must be object');
    }
    final json = Map<String, Object?>.from(value);
    if (json['version'] != attachmentProtocolVersion) {
      throw const FormatException('unsupported attachment protocol version');
    }
    return switch (json['type']) {
      'offer' => AttachmentOffer.fromJson(json),
      'resume' => AttachmentResume.fromJson(json),
      'chunkRef' => AttachmentChunkReference.fromJson(json),
      'commit' => AttachmentCommit.fromJson(json),
      _ => throw const FormatException('unknown attachment protocol type'),
    };
  }
}

class AttachmentOffer extends AttachmentProtocolMessage {
  AttachmentOffer({
    required super.transferId,
    required List<AttachmentManifest> manifests,
  }) : manifests = List.unmodifiable(manifests) {
    _requiredId(transferId, 'transferId');
    if (manifests.isEmpty) {
      throw ArgumentError('attachment offer must include a manifest');
    }
    final ids = manifests.map((manifest) => manifest.attachmentId).toSet();
    if (ids.length != manifests.length) {
      throw ArgumentError('attachment offer IDs must be unique');
    }
  }

  final List<AttachmentManifest> manifests;

  @override
  String get type => 'offer';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'version': attachmentProtocolVersion,
    'type': type,
    'transferId': transferId,
    'manifests': manifests.map((manifest) => manifest.toJson()).toList(),
  };

  factory AttachmentOffer.fromJson(Map<String, Object?> json) {
    _expectFields(json, const {'version', 'type', 'transferId', 'manifests'});
    final manifests = json['manifests'];
    if (manifests is! List) {
      throw const FormatException('offer manifests must be a list');
    }
    try {
      return AttachmentOffer(
        transferId: _requiredId(json['transferId'], 'transferId'),
        manifests: manifests.map(AttachmentManifest.fromJson).toList(),
      );
    } on ArgumentError catch (error) {
      throw FormatException(error.message?.toString() ?? error.toString());
    }
  }
}

class ChunkRange {
  const ChunkRange({required this.start, required this.count})
    : assert(start >= 0),
      assert(count > 0);

  final int start;
  final int count;
  int get endExclusive => start + count;

  Map<String, Object?> toJson() => <String, Object?>{
    'start': start,
    'count': count,
  };

  factory ChunkRange.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('chunk range must be object');
    }
    final json = Map<String, Object?>.from(value);
    _expectFields(json, const {'start', 'count'});
    final start = json['start'];
    final count = json['count'];
    if (start is! int || start < 0 || count is! int || count <= 0) {
      throw const FormatException('chunk range is invalid');
    }
    return ChunkRange(start: start, count: count);
  }
}

class AttachmentResume extends AttachmentProtocolMessage {
  AttachmentResume({
    required super.transferId,
    required Map<String, List<ChunkRange>> missing,
  }) : missing = Map.unmodifiable({
         for (final entry in missing.entries)
           entry.key: List<ChunkRange>.unmodifiable(entry.value),
       }) {
    _requiredId(transferId, 'transferId');
    for (final entry in missing.entries) {
      _requiredId(entry.key, 'attachmentId');
    }
  }

  final Map<String, List<ChunkRange>> missing;

  @override
  String get type => 'resume';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'version': attachmentProtocolVersion,
    'type': type,
    'transferId': transferId,
    'missing': {
      for (final entry in missing.entries)
        entry.key: entry.value.map((range) => range.toJson()).toList(),
    },
  };

  factory AttachmentResume.fromJson(Map<String, Object?> json) {
    _expectFields(json, const {'version', 'type', 'transferId', 'missing'});
    final missing = json['missing'];
    if (missing is! Map) {
      throw const FormatException('resume missing ranges must be an object');
    }
    try {
      return AttachmentResume(
        transferId: _requiredId(json['transferId'], 'transferId'),
        missing: {
          for (final entry in missing.entries)
            _requiredId(entry.key, 'attachmentId'): _ranges(entry.value),
        },
      );
    } on ArgumentError catch (error) {
      throw FormatException(error.message?.toString() ?? error.toString());
    }
  }
}

class AttachmentChunkReference extends AttachmentProtocolMessage {
  AttachmentChunkReference({
    required super.transferId,
    required this.attachmentId,
    required this.index,
    required this.blob,
  }) {
    _requiredId(transferId, 'transferId');
    _requiredId(attachmentId, 'attachmentId');
    if (index < 0) throw ArgumentError.value(index, 'index');
  }

  final String attachmentId;
  final int index;
  final BlobReference blob;

  @override
  String get type => 'chunkRef';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'version': attachmentProtocolVersion,
    'type': type,
    'transferId': transferId,
    'attachmentId': attachmentId,
    'index': index,
    'blob': blob.toJson(),
  };

  factory AttachmentChunkReference.fromJson(Map<String, Object?> json) {
    _expectFields(json, const {
      'version',
      'type',
      'transferId',
      'attachmentId',
      'index',
      'blob',
    });
    final index = json['index'];
    if (index is! int || index < 0) {
      throw const FormatException('chunkRef index is invalid');
    }
    try {
      return AttachmentChunkReference(
        transferId: _requiredId(json['transferId'], 'transferId'),
        attachmentId: _requiredId(json['attachmentId'], 'attachmentId'),
        index: index,
        blob: BlobReference.fromJson(json['blob']),
      );
    } on ArgumentError catch (error) {
      throw FormatException(error.message?.toString() ?? error.toString());
    }
  }
}

class AttachmentCommit extends AttachmentProtocolMessage {
  AttachmentCommit({required super.transferId}) {
    _requiredId(transferId, 'transferId');
  }

  @override
  String get type => 'commit';

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'version': attachmentProtocolVersion,
    'type': type,
    'transferId': transferId,
  };

  factory AttachmentCommit.fromJson(Map<String, Object?> json) {
    _expectFields(json, const {'version', 'type', 'transferId'});
    try {
      return AttachmentCommit(
        transferId: _requiredId(json['transferId'], 'transferId'),
      );
    } on ArgumentError catch (error) {
      throw FormatException(error.message?.toString() ?? error.toString());
    }
  }
}

List<ChunkRange> _ranges(Object? value) {
  if (value is! List) {
    throw const FormatException('chunk ranges must be a list');
  }
  return value.map(ChunkRange.fromJson).toList();
}

String _requiredId(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw ArgumentError('$field must be a non-empty string');
  }
  return value;
}

void _expectFields(Map<String, Object?> json, Set<String> allowed) {
  final unknown = json.keys.where((key) => !allowed.contains(key));
  if (unknown.isNotEmpty) {
    throw FormatException('unknown protocol fields: ${unknown.join(', ')}');
  }
}
