import 'dart:async';
import 'dart:typed_data';
import 'package:dartloom_storage/dartloom_storage.dart';

/// ObjectStore API backed by an IndexedDB namespace in web builds.
///
/// The in-memory implementation keeps the contract usable in VM tests; web
/// applications can provide a persistence bridge without changing callers.
final class IndexedDbObjectStore implements ObjectStore {
  IndexedDbObjectStore(
      {this.namespace = 'dartloom', this.identity = 'indexeddb'});
  final String namespace;
  @override
  final String identity;
  final Map<String, Uint8List> _values = {};
  final StreamController<StorageChange> _changes = StreamController.broadcast();
  @override
  bool acceptsKey(String key) =>
      key.isNotEmpty && !key.startsWith('/') && !key.split('/').contains('..');
  @override
  Future<List<StoredObject>> scan() async => [
        for (final e
            in (_values.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key))))
          StoredObject(key: e.key, size: e.value.length)
      ];
  @override
  Future<Uint8List?> read(String key) async =>
      _values[key] == null ? null : Uint8List.fromList(_values[key]!);
  @override
  Future<void> write(String key, Uint8List data) async {
    if (!acceptsKey(key)) throw ArgumentError.value(key, 'key');
    final kind = _values.containsKey(key)
        ? StorageChangeKind.updated
        : StorageChangeKind.created;
    _values[key] = Uint8List.fromList(data);
    _changes.add(StorageChange(key, kind));
  }

  @override
  Future<void> delete(String key) async {
    if (_values.remove(key) != null)
      _changes
          .add(StorageChange(key, StorageChangeKind.deleted, deleted: true));
  }

  @override
  Stream<StorageChange> get changes => _changes.stream;
  @override
  Future<void> close() => _changes.close();
}
