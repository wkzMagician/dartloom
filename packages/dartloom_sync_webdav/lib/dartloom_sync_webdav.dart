import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final String defaultRootPath;
  final Duration connectTimeout;
  final Duration requestTimeout;
  final int maxParallelRequests;
  final bool createMissingCollections;
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
      rootPath: profile.options['root_path'] as String? ?? defaultRootPath,
      username:
          profile.options['username'] as String? ?? secrets['username'] ?? '',
      password: secrets['password'] ?? '',
      connectTimeout: connectTimeout,
      requestTimeout: requestTimeout,
      maxParallelRequests: maxParallelRequests,
      createMissingCollections: createMissingCollections,
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
  final http.Client _client;
  bool _closed = false;
  int _activeRequests = 0;
  final List<Completer<void>> _requestQueue = [];

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
  Future<void> initialize() => _ensureCollection(rootPath);

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
    final request = http.Request('PROPFIND', _uri(rootPath))
      ..headers.addAll({..._authorization, 'depth': 'infinity'})
      ..body = '<?xml version="1.0" encoding="utf-8" ?>'
          '<d:propfind xmlns:d="DAV:"><d:prop><d:getetag/><d:resourcetype/></d:prop></d:propfind>';
    final response = await _send(request);
    if (response.statusCode != 207) {
      _throwResponse('PROPFIND', response, request.url);
    }
    final document = XmlDocument.parse(utf8.decode(response.bodyBytes));
    final rootUri = _uri(rootPath);
    final values = <RemoteObjectMetadata>[];
    for (final node
        in document.findAllElements('response', namespace: 'DAV:')) {
      final href =
          node.findElements('href', namespace: 'DAV:').firstOrNull?.innerText;
      final version = node
          .findAllElements('getetag', namespace: 'DAV:')
          .firstOrNull
          ?.innerText;
      final isCollection =
          node.findAllElements('collection', namespace: 'DAV:').isNotEmpty;
      if (href == null || version == null || version.isEmpty || isCollection) {
        continue;
      }
      final hrefUri = rootUri.resolve(href);
      final prefix = _directoryPath(rootUri.path);
      if (!hrefUri.path.startsWith(prefix)) continue;
      final key = Uri.decodeFull(hrefUri.path.substring(prefix.length));
      if (key.isNotEmpty) {
        values.add(RemoteObjectMetadata(key: key, version: version));
      }
    }
    values.sort((a, b) => a.key.compareTo(b.key));
    return RemoteScan(kind: SyncScanKind.full, objects: values);
  }

  @override
  Future<RemoteObject?> read(String key) async {
    final uri = _objectUri(key);
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

  Uri _objectUri(String key) => _uri('$rootPath/$key');
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
}
