abstract interface class TextStore {
  Future<List<String>> list({String prefix = ''});
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
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

class MemoryJsonStore implements JsonStore {
  final Map<String, Object?> _values = {};

  @override
  Future<void> delete(String key) async => _values.remove(key);
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
