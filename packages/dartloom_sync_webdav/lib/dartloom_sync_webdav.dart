import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartloom_sync/dartloom_sync.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

final class WebDavBackendFactory implements SyncBackendFactory {
  WebDavBackendFactory({
    this.defaultRootPath = 'Dartloom',
    this.connectTimeout = const Duration(seconds: 10),
    this.requestTimeout = const Duration(seconds: 30),
    this.maxParallelRequests = 4,
    this.createMissingCollections = true,
    this.hierarchical = false,
    this.probeDepthInfinity = false,
    this.legacyCollection,
    this.legacyKeyPrefix = '',
    this.listingLimitHint = 750,
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final String defaultRootPath;
  final Duration connectTimeout;
  final Duration requestTimeout;
  final int maxParallelRequests;
  final bool createMissingCollections;
  final bool hierarchical;
  final bool probeDepthInfinity;
  final String? legacyCollection;
  final String legacyKeyPrefix;
  final int listingLimitHint;
  final http.Client Function() _clientFactory;

  @override
  String get id => 'webdav';

  @override
  RemoteReplicaCapabilities get capabilities => const RemoteReplicaCapabilities(
        deltaScan: false,
        changeFeed: false,
        conditionalWrites: true,
      );

  @override
  Future<void> validateProfile(SyncProfileDraft profile) async {
    final raw = profile.options['base_url'];
    final uri = raw is String ? Uri.tryParse(raw.trim()) : null;
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const FormatException('WebDAV profile requires a valid base_url.');
    }
  }

  @override
  Future<RemoteReplica> open(
      SyncProfile profile, Map<String, String> secrets) async {
    final uri = Uri.parse(profile.options['base_url'] as String);
    return WebDavRemoteReplica(
      baseUrl: uri,
      rootPath: defaultRootPath,
      username:
          profile.options['username'] as String? ?? secrets['username'] ?? '',
      password: secrets['password'] ?? '',
      connectTimeout: connectTimeout,
      requestTimeout: requestTimeout,
      maxParallelRequests: maxParallelRequests,
      createMissingCollections: createMissingCollections,
      hierarchical: hierarchical,
      probeDepthInfinity: probeDepthInfinity,
      legacyCollection: legacyCollection,
      legacyKeyPrefix: legacyKeyPrefix,
      listingLimitHint: listingLimitHint,
      client: _clientFactory(),
    );
  }
}

final class WebDavRemoteReplica implements RemoteReplica {
  WebDavRemoteReplica({
    required Uri baseUrl,
    required this.rootPath,
    required this.username,
    required this.password,
    required this.connectTimeout,
    required this.requestTimeout,
    required this.maxParallelRequests,
    required this.createMissingCollections,
    this.hierarchical = false,
    this.probeDepthInfinity = false,
    this.legacyCollection,
    this.legacyKeyPrefix = '',
    this.listingLimitHint = 750,
    http.Client? client,
  })  : baseUrl = baseUrl.replace(path: _directoryPath(baseUrl.path)),
        _client = client ?? http.Client();

  final Uri baseUrl;
  final String rootPath;
  final String username;
  final String password;
  final Duration connectTimeout;
  final Duration requestTimeout;
  final int maxParallelRequests;
  final bool createMissingCollections;
  final bool hierarchical;
  final bool probeDepthInfinity;
  final String? legacyCollection;
  final String legacyKeyPrefix;
  final int listingLimitHint;
  final http.Client _client;
  bool _closed = false;
  int _activeRequests = 0;
  final List<Completer<void>> _requestQueue = [];
  WebDavDepthSupport depthSupport = WebDavDepthSupport.unknown;
  bool _scanComplete = true;

  @override
  String get identity {
    final endpoint = baseUrl.replace(
      scheme: baseUrl.scheme.toLowerCase(),
      host: baseUrl.host.toLowerCase(),
      fragment: '',
      query: '',
    );
    final account = sha256.convert(utf8.encode(username)).toString();
    return 'webdav-v4|$endpoint|${_normalizeRelativePath(rootPath)}|$account';
  }

  @override
  RemoteReplicaCapabilities get capabilities => const RemoteReplicaCapabilities(
        deltaScan: false,
        changeFeed: false,
        conditionalWrites: true,
      );

  @override
  Stream<void>? get changeHints => null;

  Map<String, String> get _authorization => {
        if (username.isNotEmpty)
          'authorization':
              'Basic ${base64Encode(utf8.encode('$username:$password'))}',
      };

  @override
  Future<void> initialize() async {
    await _ensureCollection(rootPath);
    final legacy = legacyCollection;
    if (legacy != null && legacy.isNotEmpty) {
      await _migrateLegacyCollection(legacy);
    }
  }

  Future<void> _migrateLegacyCollection(String collection) async {
    final entries = await _propfind(
      '$rootPath/$collection',
      depth: '1',
      missingIsEmpty: true,
    );
    final prefix = '${_normalizeRelativePath(collection)}/';
    for (final entry in entries.where((entry) => !entry.isCollection)) {
      if (!entry.key.startsWith(prefix)) continue;
      final key = entry.key.substring(prefix.length);
      if (key.contains('/') || !key.startsWith(legacyKeyPrefix)) continue;
      if (await read(key) != null) continue;
      final source = await _readUri(key, _uri('$rootPath/$collection/$key'));
      if (source == null) continue;
      try {
        await write(key, source.data,
            condition: const RemoteWriteCondition.create());
      } on RemotePreconditionException {
        // A concurrent migrator already copied this object.
      }
    }
  }

  Future<void> _ensureCollection(String path) async {
    if (!createMissingCollections) return;
    var current = '';
    for (final segment in path.split('/').where((part) => part.isNotEmpty)) {
      current = '$current/$segment';
      final response = await _send(
          http.Request('MKCOL', _uri(current))..headers.addAll(_authorization));
      if (![201, 405, 301].contains(response.statusCode)) {
        _throwResponse('MKCOL', response, _uri(current));
      }
    }
  }

  @override
  Future<RemoteScan> scan({String? cursor}) async {
    _scanComplete = true;
    final entries = <String, _DavEntry>{};
    final pending = <String>[rootPath];
    final visited = <String>{};
    while (pending.isNotEmpty) {
      final collection = pending.removeLast();
      if (!visited.add(_normalizeRelativePath(collection))) continue;
      for (final entry in await _propfind(collection, depth: '1')) {
        if (entry.key.isEmpty) continue;
        if (entry.isCollection) {
          if (hierarchical) pending.add('$rootPath/${entry.key}');
          continue;
        }
        if (!hierarchical && entry.key.contains('/')) continue;
        entries[entry.key] = entry;
      }
    }
    depthSupport = hierarchical
        ? WebDavDepthSupport.finiteDepth
        : WebDavDepthSupport.finiteDepth;
    if (hierarchical && probeDepthInfinity) {
      try {
        final infinite = await _propfind(rootPath, depth: 'infinity');
        final infiniteFiles = {
          for (final entry in infinite.where((entry) => !entry.isCollection))
            entry.key,
        };
        final baselineFiles = entries.keys.toSet();
        depthSupport = infiniteFiles.containsAll(baselineFiles)
            ? WebDavDepthSupport.verifiedInfinity
            : WebDavDepthSupport.partial;
      } on Object {
        depthSupport = WebDavDepthSupport.unknown;
      }
    }
    final values = entries.values
        .map((entry) => RemoteObjectMetadata(
              key: entry.key,
              version: entry.version!,
            ))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return RemoteScan(
      kind: SyncScanKind.full,
      objects: values,
      complete: _scanComplete,
    );
  }

  Future<List<_DavEntry>> _propfind(
    String collection, {
    required String depth,
    bool missingIsEmpty = false,
  }) async {
    final request = http.Request('PROPFIND', _uri(collection))
      ..headers.addAll({
        ..._authorization,
        'depth': depth,
        'content-type': 'application/xml; charset=utf-8',
      })
      ..body = '<?xml version="1.0" encoding="utf-8" ?>'
          '<d:propfind xmlns:d="DAV:"><d:prop><d:getetag/><d:resourcetype/></d:prop></d:propfind>';
    final response = await _send(request);
    if (missingIsEmpty && response.statusCode == 404) return const [];
    if (response.statusCode != 207) {
      _throwResponse('PROPFIND', response, request.url);
    }
    final document = XmlDocument.parse(utf8.decode(response.bodyBytes));
    final rootUri = _uri(rootPath);
    final prefix = _directoryPath(rootUri.path);
    final result = <_DavEntry>[];
    for (final node
        in document.findAllElements('response', namespace: 'DAV:')) {
      final href =
          node.findElements('href', namespace: 'DAV:').firstOrNull?.innerText;
      if (href == null) continue;
      final hrefUri = baseUrl.resolve(href);
      if (hrefUri.scheme != rootUri.scheme ||
          hrefUri.host != rootUri.host ||
          !hrefUri.path.startsWith(prefix)) {
        continue;
      }
      final key = _normalizeRelativePath(hrefUri.path.substring(prefix.length));
      if (key.isEmpty) continue;
      final isCollection =
          node.findAllElements('collection', namespace: 'DAV:').isNotEmpty;
      final version = node
          .findAllElements('getetag', namespace: 'DAV:')
          .firstOrNull
          ?.innerText;
      if (!isCollection && (version == null || version.isEmpty)) continue;
      result.add(_DavEntry(key, version, isCollection));
    }
    if (listingLimitHint > 0 && result.length >= listingLimitHint) {
      _scanComplete = false;
    }
    return result;
  }

  @override
  Future<RemoteObject?> read(String key) async {
    return _readUri(key, _objectUri(key));
  }

  Future<RemoteObject?> _readUri(String key, Uri uri) async {
    final response =
        await _send(http.Request('GET', uri)..headers.addAll(_authorization));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) _throwResponse('GET', response, uri);
    final version = response.headers['etag'];
    if (version == null || version.isEmpty) {
      throw StateError('WebDAV server did not return an ETag for $key.');
    }
    return RemoteObject(
        key: key,
        data: Uint8List.fromList(response.bodyBytes),
        version: version);
  }

  @override
  Future<String> write(String key, Uint8List data,
      {RemoteWriteCondition? condition}) async {
    final slash = key.lastIndexOf('/');
    if (slash > 0) {
      await _ensureCollection('$rootPath/${key.substring(0, slash)}');
    }
    final uri = _objectUri(key);
    final request = http.Request('PUT', uri)
      ..headers.addAll({..._authorization, ..._conditionHeaders(condition)})
      ..bodyBytes = data;
    final response = await _send(request);
    if (response.statusCode == 412) throw RemotePreconditionException(key);
    if (![200, 201, 204].contains(response.statusCode)) {
      _throwResponse('PUT', response, uri);
    }
    final version = response.headers['etag'];
    if (version != null && version.isNotEmpty) return version;
    final refreshed = await read(key);
    if (refreshed != null) return refreshed.version;
    throw StateError('WebDAV server did not return an ETag for $key.');
  }

  @override
  Future<void> delete(String key, {RemoteWriteCondition? condition}) async {
    final uri = _objectUri(key);
    final request = http.Request('DELETE', uri)
      ..headers.addAll({..._authorization, ..._conditionHeaders(condition)});
    final response = await _send(request);
    if (response.statusCode == 412) throw RemotePreconditionException(key);
    if (![200, 204, 404].contains(response.statusCode)) {
      _throwResponse('DELETE', response, uri);
    }
  }

  Map<String, String> _conditionHeaders(RemoteWriteCondition? condition) =>
      switch (condition) {
        RemoteCreateCondition() => const {'if-none-match': '*'},
        RemoteVersionCondition(:final version) => {'if-match': version},
        null => const {},
      };

  Future<http.Response> _send(http.Request request) async {
    if (_closed) throw StateError('WebDAV replica is closed.');
    await _acquireRequestPermit();
    try {
      return await http.Response.fromStream(
              await _client.send(request).timeout(connectTimeout))
          .timeout(requestTimeout);
    } on TimeoutException {
      throw SyncOperationException(SyncFailure(
        SyncFailureKind.timeout,
        'WebDAV ${request.method} timed out.',
        retryable: true,
      ));
    } on http.ClientException catch (error) {
      throw SyncOperationException(SyncFailure(
        SyncFailureKind.connectivity,
        error.message,
        retryable: true,
      ));
    } finally {
      _releaseRequestPermit();
    }
  }

  Future<void> _acquireRequestPermit() async {
    if (maxParallelRequests < 1) {
      throw ArgumentError.value(
          maxParallelRequests, 'maxParallelRequests', 'Must be at least 1.');
    }
    if (_activeRequests < maxParallelRequests) {
      _activeRequests++;
      return;
    }
    final waiter = Completer<void>();
    _requestQueue.add(waiter);
    await waiter.future;
    _activeRequests++;
  }

  void _releaseRequestPermit() {
    _activeRequests--;
    if (_requestQueue.isNotEmpty) _requestQueue.removeAt(0).complete();
  }

  Never _throwResponse(String method, http.Response response, Uri uri) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw SyncOperationException(SyncFailure(
        SyncFailureKind.authentication,
        'WebDAV authentication failed with ${response.statusCode}.',
      ));
    }
    throw SyncOperationException(SyncFailure(
      SyncFailureKind.connectivity,
      'WebDAV $method failed with ${response.statusCode} at $uri.',
      retryable: response.statusCode == 408 ||
          response.statusCode == 429 ||
          response.statusCode >= 500,
    ));
  }

  Uri _objectUri(String key) =>
      _uri('$rootPath/${_normalizeRelativePath(key)}');
  Uri _uri(String path) {
    final encoded = path
        .split('/')
        .where((part) => part.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    return baseUrl.replace(path: '${baseUrl.path}$encoded');
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client.close();
  }

  static String _directoryPath(String value) =>
      value.isEmpty || value.endsWith('/') ? value : '$value/';

  static String _normalizeRelativePath(String value) {
    final normalized = value.replaceAll('\\', '/');
    final parts =
        normalized.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.any((part) => part == '.' || part == '..')) {
      throw FormatException('Invalid WebDAV relative path: $value');
    }
    return parts.join('/');
  }
}

enum WebDavDepthSupport { verifiedInfinity, finiteDepth, partial, unknown }

final class _DavEntry {
  const _DavEntry(this.key, this.version, this.isCollection);

  final String key;
  final String? version;
  final bool isCollection;
}
