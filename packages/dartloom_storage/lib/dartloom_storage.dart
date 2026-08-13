import 'dart:async';
import 'dart:typed_data';

abstract interface class TextStore {
  Future<List<String>> list({String prefix = ''});
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

enum StoreMutationOrigin {
  application,
  migration,
  conflictResolution,
  remote,
  recovery,
  external;

  bool get isAuthorizedIntent => switch (this) {
        application || migration || conflictResolution => true,
        remote || recovery || external => false,
      };
}

enum StoreChangeKind {
  mutation,
  untrustedLocalChange,
  unexpectedMissing,
  unregisteredLocalObject,
  rootMissing,
}

final class StoreChange {
  const StoreChange(
    this.key,
    this.origin, {
    this.kind = StoreChangeKind.mutation,
    this.deleted = false,
  });

  final String key;
  final StoreMutationOrigin origin;
  final StoreChangeKind kind;
  final bool deleted;
}

enum StoreIntentKind { create, update, delete }

final class StoreIntent {
  const StoreIntent({
    required this.operationId,
    required this.key,
    required this.kind,
    required this.origin,
    required this.createdAt,
    this.contentHash,
  });

  final String operationId;
  final String key;
  final StoreIntentKind kind;
  final StoreMutationOrigin origin;
  final DateTime createdAt;
  final String? contentHash;
}

enum ReplicaObservation {
  trusted,
  untrustedLocalChange,
  unexpectedMissing,
  unregisteredLocalObject,
}

final class ReplicaObjectMetadata {
  const ReplicaObjectMetadata({
    required this.key,
    required this.size,
    this.modifiedAt,
    this.contentHash,
    this.exists = true,
    this.observation = ReplicaObservation.trusted,
  });

  final String key;
  final int size;
  final DateTime? modifiedAt;
  final String? contentHash;
  final bool exists;
  final ReplicaObservation observation;
}

/// Raw-byte storage contract for isomorphic local replicas.
///
/// Implementations must treat keys as relative paths inside the store root.
/// External filesystem changes are reported as [StoreMutationOrigin.external]
/// changes and never imply an authorized local intent.
abstract interface class ReplicaStore {
  String get identity;
  Stream<StoreChange> get changes;
  bool acceptsKey(String key);
  Future<List<ReplicaObjectMetadata>> scan();
  Future<Uint8List?> readBytes(String key);
  Future<void> writeBytes(
    String key,
    Uint8List data, {
    StoreMutationOrigin origin,
  });
  Future<void> delete(
    String key, {
    StoreMutationOrigin origin,
  });
  Future<List<StoreIntent>> explicitIntents();
  Future<void> forgetExplicitIntent(String operationId);
  Future<Set<String>> explicitDeletedKeys();
  Future<void> forgetExplicitDelete(String key);
  Future<void> close();
}

abstract interface class JsonStore {
  Future<List<String>> list({String prefix = ''});
  Future<Object?> read(String key);
  Future<void> write(String key, Object? value);
  Future<void> delete(String key);
}

abstract interface class DatabaseStore {
  Future<List<String>> collections();
  Future<List<String>> list(String collection);
  Future<Map<String, Object?>?> read(String collection, String id);
  Future<void> write(
    String collection,
    String id,
    Map<String, Object?> document,
  );
  Future<void> deleteDocument(String collection, String id);
  Future<void> close();
}

bool isJsonValue(Object? value) {
  if (value == null || value is bool || value is num || value is String) {
    return true;
  }
  if (value is List<Object?>) return value.every(isJsonValue);
  if (value is Map<String, Object?>) return value.values.every(isJsonValue);
  return false;
}

class MemoryTextStore implements TextStore {
  final Map<String, String> _values = {};

  @override
  Future<void> delete(String key) async => _values.remove(key);
  @override
  Future<List<String>> list({String prefix = ''}) async =>
      (_values.keys.where((key) => key.startsWith(prefix)).toList()..sort());
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

final class MemoryReplicaStore implements ReplicaStore {
  final Map<String, Uint8List> _values = {};
  final StreamController<StoreChange> _changes =
      StreamController<StoreChange>.broadcast();
  final List<StoreIntent> _intents = [];

  @override
  String get identity => 'memory-replica';
  @override
  Stream<StoreChange> get changes => _changes.stream;
  @override
  bool acceptsKey(String key) =>
      key.isNotEmpty &&
      !key.startsWith('/') &&
      !key
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..');
  @override
  Future<List<ReplicaObjectMetadata>> scan() async => [
        for (final entry in _values.entries)
          ReplicaObjectMetadata(key: entry.key, size: entry.value.length),
      ];
  @override
  Future<Uint8List?> readBytes(String key) async =>
      _values[key] == null ? null : Uint8List.fromList(_values[key]!);
  @override
  Future<void> writeBytes(String key, Uint8List data,
      {StoreMutationOrigin origin = StoreMutationOrigin.application}) async {
    if (!acceptsKey(key)) {
      throw ArgumentError.value(key, 'key', 'Invalid replica key.');
    }
    final kind = _values.containsKey(key)
        ? StoreIntentKind.update
        : StoreIntentKind.create;
    _values[key] = Uint8List.fromList(data);
    if (origin.isAuthorizedIntent) {
      _intents.add(_intent(key, kind, origin));
    }
    _changes.add(StoreChange(key, origin));
  }

  @override
  Future<void> delete(String key,
      {StoreMutationOrigin origin = StoreMutationOrigin.application}) async {
    if (!acceptsKey(key)) {
      throw ArgumentError.value(key, 'key', 'Invalid replica key.');
    }
    _values.remove(key);
    if (origin.isAuthorizedIntent) {
      _intents.add(_intent(key, StoreIntentKind.delete, origin));
    }
    _changes.add(StoreChange(key, origin, deleted: true));
  }

  @override
  Future<void> close() => _changes.close();

  @override
  Future<List<StoreIntent>> explicitIntents() async => List.of(_intents);

  @override
  Future<void> forgetExplicitIntent(String operationId) async =>
      _intents.removeWhere((intent) => intent.operationId == operationId);

  @override
  Future<Set<String>> explicitDeletedKeys() async => _intents
      .where((intent) => intent.kind == StoreIntentKind.delete)
      .map((intent) => intent.key)
      .toSet();

  @override
  Future<void> forgetExplicitDelete(String key) async => _intents.removeWhere(
        (intent) => intent.key == key && intent.kind == StoreIntentKind.delete,
      );

  StoreIntent _intent(
    String key,
    StoreIntentKind kind,
    StoreMutationOrigin origin,
  ) {
    final now = DateTime.now().toUtc();
    return StoreIntent(
      operationId: '${now.microsecondsSinceEpoch}::$key',
      key: key,
      kind: kind,
      origin: origin,
      createdAt: now,
    );
  }
}

class MemoryJsonStore implements JsonStore {
  final Map<String, Object?> _values = {};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<List<String>> list({String prefix = ''}) async =>
      (_values.keys.where((key) => key.startsWith(prefix)).toList()..sort());
  @override
  Future<Object?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, Object? value) async {
    if (!isJsonValue(value)) {
      throw ArgumentError.value(value, 'value', 'Value must be valid JSON.');
    }
    _values[key] = value;
  }
}

class MemoryDatabaseStore implements DatabaseStore {
  final Map<String, Map<String, Map<String, Object?>>> _collections = {};

  @override
  Future<void> close() async {}
  @override
  Future<List<String>> collections() async =>
      (_collections.keys.toList()..sort());
  @override
  Future<void> deleteDocument(String collection, String id) async =>
      _collections[collection]?.remove(id);
  @override
  Future<List<String>> list(String collection) async =>
      (_collections[collection]?.keys.toList() ?? <String>[])..sort();
  @override
  Future<Map<String, Object?>?> read(String collection, String id) async {
    final value = _collections[collection]?[id];
    return value == null ? null : Map.of(value);
  }

  @override
  Future<void> write(
    String collection,
    String id,
    Map<String, Object?> document,
  ) async {
    if (!isJsonValue(document)) {
      throw ArgumentError.value(document, 'document', 'Document must be JSON.');
    }
    (_collections[collection] ??= {})[id] = Map.of(document);
  }
}
