import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

abstract interface class TextStore {
  Future<List<String>> list({String prefix = ''});
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

enum StoreMutationOrigin { local, replica }

final class StoreChange {
  const StoreChange(this.key, this.origin, {this.deleted = false});

  final String key;
  final StoreMutationOrigin origin;
  final bool deleted;
}

final class ReplicaObjectMetadata {
  const ReplicaObjectMetadata({
    required this.key,
    required this.size,
    this.modifiedAt,
  });

  final String key;
  final int size;
  final DateTime? modifiedAt;
}

/// Raw-byte storage contract for isomorphic local replicas.
///
/// Implementations must treat keys as relative paths inside the store root.
/// External filesystem changes are reported as [StoreMutationOrigin.replica]
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
  Future<void> close();
}

abstract interface class JsonStore {
  Future<List<String>> list({String prefix = ''});
  Future<Object?> read(String key);
  Future<void> write(String key, Object? value);
  Future<void> delete(String key);
}

enum JsonStoreMutationOrigin { local, replica }

final class JsonStoreChange {
  const JsonStoreChange(this.key, this.origin);

  final String key;
  final JsonStoreMutationOrigin origin;
}

/// A JSON store whose keys are also the stable relative paths of a replica.
///
/// Implementations must keep sync metadata, including deletion journals,
/// outside the directory returned by [replicaIdentity].
abstract interface class ReplicaJsonStore implements JsonStore {
  String get replicaIdentity;
  bool acceptsReplicaKey(String key);
  Stream<JsonStoreChange> get changes;
  Future<Set<String>> deletedKeys();
  Future<void> forgetDeletedKey(String key);
  Future<Uint8List?> readReplicaBytes(String key);
  Future<void> writeReplicaBytes(String key, Uint8List data);
  Future<void> writeFromReplica(String key, Object? value);
  Future<void> deleteFromReplica(String key);
  Future<void> close();
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
      {StoreMutationOrigin origin = StoreMutationOrigin.local}) async {
    if (!acceptsKey(key)) {
      throw ArgumentError.value(key, 'key', 'Invalid replica key.');
    }
    _values[key] = Uint8List.fromList(data);
    _changes.add(StoreChange(key, origin));
  }

  @override
  Future<void> delete(String key,
      {StoreMutationOrigin origin = StoreMutationOrigin.local}) async {
    if (!acceptsKey(key)) {
      throw ArgumentError.value(key, 'key', 'Invalid replica key.');
    }
    _values.remove(key);
    _changes.add(StoreChange(key, origin, deleted: true));
  }

  @override
  Future<void> close() => _changes.close();
}

class MemoryJsonStore implements ReplicaJsonStore {
  final Map<String, Object?> _values = {};
  final Set<String> _deletedKeys = {};
  final StreamController<JsonStoreChange> _changes =
      StreamController<JsonStoreChange>.broadcast();

  @override
  String get replicaIdentity => 'memory-json-store';

  @override
  bool acceptsReplicaKey(String key) => true;

  @override
  Stream<JsonStoreChange> get changes => _changes.stream;

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
    _deletedKeys.add(key);
    _changes.add(JsonStoreChange(key, JsonStoreMutationOrigin.local));
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
    _deletedKeys.remove(key);
    _changes.add(JsonStoreChange(key, JsonStoreMutationOrigin.local));
  }

  @override
  Future<Set<String>> deletedKeys() async => Set.unmodifiable(_deletedKeys);

  @override
  Future<void> forgetDeletedKey(String key) async => _deletedKeys.remove(key);

  @override
  Future<Uint8List?> readReplicaBytes(String key) async {
    if (!_values.containsKey(key)) return null;
    return Uint8List.fromList(utf8.encode(jsonEncode(_values[key])));
  }

  @override
  Future<void> writeReplicaBytes(String key, Uint8List data) =>
      writeFromReplica(key, jsonDecode(utf8.decode(data)));

  @override
  Future<void> writeFromReplica(String key, Object? value) async {
    if (!isJsonValue(value)) {
      throw ArgumentError.value(value, 'value', 'Value must be valid JSON.');
    }
    _values[key] = value;
    _deletedKeys.remove(key);
    _changes.add(JsonStoreChange(key, JsonStoreMutationOrigin.replica));
  }

  @override
  Future<void> deleteFromReplica(String key) async {
    _values.remove(key);
    _deletedKeys.remove(key);
    _changes.add(JsonStoreChange(key, JsonStoreMutationOrigin.replica));
  }

  @override
  Future<void> close() => _changes.close();
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
