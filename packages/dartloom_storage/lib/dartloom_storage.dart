import 'dart:async';
import 'dart:typed_data';

final class StoredObject {
  const StoredObject(
      {required this.key,
      required this.size,
      this.modifiedAt,
      this.contentHash});
  final String key;
  final int size;
  final DateTime? modifiedAt;
  final String? contentHash;
}

enum StorageChangeKind { created, updated, deleted, external }

final class StorageChange {
  const StorageChange(this.key, this.kind, {this.deleted = false});
  final String key;
  final StorageChangeKind kind;
  final bool deleted;
}

abstract interface class ObjectStore {
  String get identity;
  bool acceptsKey(String key);
  Future<List<StoredObject>> scan();
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List data);
  Future<void> delete(String key);
  Stream<StorageChange> get changes;
  Future<void> close();
}

final class MemoryObjectStore implements ObjectStore {
  MemoryObjectStore({this.identity = 'memory'});
  @override
  final String identity;
  final Map<String, Uint8List> _values = {};
  final StreamController<StorageChange> _changes =
      StreamController<StorageChange>.broadcast();

  @override
  bool acceptsKey(String key) =>
      key.isNotEmpty &&
      !key.startsWith('/') &&
      !key
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..');
  @override
  Future<List<StoredObject>> scan() async => [
        for (final entry
            in (_values.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key))))
          StoredObject(key: entry.key, size: entry.value.length),
      ];
  @override
  Future<Uint8List?> read(String key) async =>
      _values[key] == null ? null : Uint8List.fromList(_values[key]!);
  @override
  Future<void> write(String key, Uint8List data) async {
    _checkKey(key);
    final kind = _values.containsKey(key)
        ? StorageChangeKind.updated
        : StorageChangeKind.created;
    _values[key] = Uint8List.fromList(data);
    _changes.add(StorageChange(key, kind));
  }

  @override
  Future<void> delete(String key) async {
    _checkKey(key);
    if (_values.remove(key) != null)
      _changes
          .add(StorageChange(key, StorageChangeKind.deleted, deleted: true));
  }

  @override
  Stream<StorageChange> get changes => _changes.stream;
  @override
  Future<void> close() => _changes.close();
  void _checkKey(String key) {
    if (!acceptsKey(key))
      throw ArgumentError.value(key, 'key', 'Invalid object key.');
  }
}
