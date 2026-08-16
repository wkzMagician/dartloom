import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartloom_storage/dartloom_storage.dart';
import 'package:web/web.dart' as web;

final class IndexedDbObjectStore implements ObjectStore, ExclusiveObjectStore {
  IndexedDbObjectStore({this.namespace = 'dartloom', String? identity})
      : identity = identity ?? 'indexeddb:$namespace';

  final String namespace;
  @override
  final String identity;
  static const _version = 1;
  static const _objectStoreName = 'objects';
  final StreamController<StorageChange> _changes = StreamController.broadcast();
  web.IDBDatabase? _database;
  web.BroadcastChannel? _channel;
  StreamSubscription<web.Event>? _channelSubscription;
  Future<void>? _opening;
  Future<void> _exclusiveTail = Future<void>.value();
  bool _closed = false;

  @override
  bool acceptsKey(String key) =>
      key.isNotEmpty &&
      !key.startsWith('/') &&
      !key
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..');

  @override
  Stream<StorageChange> get changes => _changes.stream;

  @override
  Future<List<StoredObject>> scan() async {
    final store = await _store('readonly');
    final request = store.getAllKeys();
    final result = await _request(request);
    final keys = (result as JSArray<JSAny?>)
        .toDart
        .map((value) => (value as JSString).toDart)
        .toList();
    final objects = <StoredObject>[];
    for (final key in keys..sort()) {
      final data = await read(key);
      if (data != null) {
        objects.add(StoredObject(
            key: key,
            size: data.length,
            contentHash: sha256.convert(data).toString()));
      }
    }
    return objects;
  }

  @override
  Future<Uint8List?> read(String key) async {
    _checkKey(key);
    final store = await _store('readonly');
    final result = await _request(store.get(key.toJS));
    if (result == null) return null;
    return Uint8List.fromList((result as JSUint8Array).toDart);
  }

  @override
  Future<void> write(String key, Uint8List data) async {
    _checkKey(key);
    final existed = await read(key) != null;
    final store = await _store('readwrite');
    await _request(store.put(data.toJS, key.toJS));
    _publish(StorageChange(
        key, existed ? StorageChangeKind.updated : StorageChangeKind.created));
  }

  @override
  Future<void> delete(String key) async {
    _checkKey(key);
    final existed = await read(key) != null;
    if (!existed) return;
    final store = await _store('readwrite');
    await _request(store.delete(key.toJS));
    _publish(StorageChange(key, StorageChangeKind.deleted, deleted: true));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _channelSubscription?.cancel();
    _channel?.close();
    _database?.close();
    await _changes.close();
  }

  @override
  Future<T> withExclusiveLock<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final previous = _exclusiveTail;
    _exclusiveTail = previous.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<web.IDBObjectStore> _store(String mode) async {
    await _open();
    final db = _database!;
    final transaction = db.transaction([_objectStoreName.toJS].toJS, mode);
    return transaction.objectStore(_objectStoreName);
  }

  Future<void> _open() async {
    if (_closed) throw StateError('IndexedDbObjectStore is closed.');
    if (_database != null) return;
    _opening ??= _openDatabase();
    await _opening;
  }

  Future<void> _openDatabase() async {
    final request = web.window.indexedDB.open(_databaseName, _version);
    request.onupgradeneeded = ((web.Event _) {
      final db = request.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_objectStoreName)) {
        db.createObjectStore(_objectStoreName);
      }
    }).toJS;
    _database = (await _request(request)) as web.IDBDatabase;
    final channel = web.BroadcastChannel(_channelName);
    _channel = channel;
    _channelSubscription = web.EventStreamProvider<web.MessageEvent>('message')
        .forTarget(channel)
        .listen((event) {
      final raw = event.data?.dartify();
      if (raw is! String || _closed) return;
      try {
        final json = jsonDecode(raw);
        if (json is! Map) return;
        final key = json['key'];
        final kind = json['kind'];
        if (key is! String || kind is! String) return;
        final changeKind = StorageChangeKind.values.firstWhere(
          (value) => value.name == kind,
          orElse: () => StorageChangeKind.external,
        );
        _changes.add(StorageChange(key, changeKind,
            deleted: changeKind == StorageChangeKind.deleted));
      } on Object {
        // Cross-tab notifications are advisory; the database remains source of truth.
      }
    });
  }

  Future<JSAny?> _request(web.IDBRequest request) {
    final completer = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) {
      if (!completer.isCompleted) completer.complete(request.result);
    }).toJS;
    request.onerror = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
            StateError(request.error?.name ?? 'IndexedDB request failed'));
      }
    }).toJS;
    return completer.future;
  }

  void _publish(StorageChange change) {
    if (_closed) return;
    _changes.add(change);
    _channel?.postMessage(
        jsonEncode({'key': change.key, 'kind': change.kind.name}).toJS);
  }

  String get _databaseName => 'dartloom.$namespace';
  String get _channelName => 'dartloom.$namespace.changes';

  void _checkKey(String key) {
    if (!acceptsKey(key)) throw ArgumentError.value(key, 'key');
  }
}
