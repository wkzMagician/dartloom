import 'dart:convert';
import 'dart:typed_data';

import 'package:dartloom_sync/dartloom_sync.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

final class WebDavObjectStore implements RemoteObjectStore {
  WebDavObjectStore({
    required Uri baseUrl,
    required this.rootPath,
    required this.username,
    required this.password,
    http.Client? client,
  })  : baseUrl = baseUrl.replace(path: _directoryPath(baseUrl.path)),
        _client = client ?? http.Client();

  final Uri baseUrl;
  final String rootPath;
  final String username;
  final String password;
  final http.Client _client;

  Map<String, String> get _authorization => {
        if (username.isNotEmpty)
          'authorization':
              'Basic ${base64Encode(utf8.encode('$username:$password'))}',
      };

  @override
  Future<void> initialize() async {
    var current = '';
    for (final segment
        in rootPath.split('/').where((part) => part.isNotEmpty)) {
      current = '$current/$segment';
      final response = await _client.send(
        http.Request('MKCOL', _uri(current))..headers.addAll(_authorization),
      );
      if (response.statusCode != 201 &&
          response.statusCode != 405 &&
          response.statusCode != 301) {
        throw http.ClientException(
          'WebDAV MKCOL failed with ${response.statusCode}.',
          _uri(current),
        );
      }
    }
  }

  @override
  Future<List<RemoteObjectMetadata>> list() async {
    final request = http.Request('PROPFIND', _uri(rootPath))
      ..headers.addAll({..._authorization, 'depth': 'infinity'})
      ..body = '''<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:"><d:prop><d:getetag/><d:resourcetype/></d:prop></d:propfind>''';
    final response =
        await http.Response.fromStream(await _client.send(request));
    if (response.statusCode != 207) {
      throw http.ClientException(
        'WebDAV PROPFIND failed with ${response.statusCode}.',
        request.url,
      );
    }
    final document = XmlDocument.parse(response.body);
    final rootUri = _uri(rootPath);
    final values = <RemoteObjectMetadata>[];
    for (final node
        in document.findAllElements('response', namespace: 'DAV:')) {
      final href =
          node.findElements('href', namespace: 'DAV:').firstOrNull?.innerText;
      final etag = node
          .findAllElements('getetag', namespace: 'DAV:')
          .firstOrNull
          ?.innerText;
      final isCollection =
          node.findAllElements('collection', namespace: 'DAV:').isNotEmpty;
      if (href == null || etag == null || etag.isEmpty || isCollection) {
        continue;
      }
      final hrefUri = rootUri.resolve(href);
      final prefix = _directoryPath(rootUri.path);
      if (!hrefUri.path.startsWith(prefix)) continue;
      final key = Uri.decodeFull(hrefUri.path.substring(prefix.length));
      if (key.isNotEmpty) {
        values.add(RemoteObjectMetadata(key: key, etag: etag));
      }
    }
    return values..sort((a, b) => a.key.compareTo(b.key));
  }

  @override
  Future<SyncObject?> read(String key) async {
    final response =
        await _client.get(_objectUri(key), headers: _authorization);
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw http.ClientException(
        'WebDAV GET failed with ${response.statusCode}.',
        _objectUri(key),
      );
    }
    final etag = response.headers['etag'];
    if (etag == null || etag.isEmpty) {
      throw StateError('WebDAV server did not return an ETag for $key.');
    }
    return SyncObject(
      key: key,
      data: Uint8List.fromList(response.bodyBytes),
      etag: etag,
    );
  }

  @override
  Future<String> write(
    String key,
    Uint8List data, {
    String? ifMatch,
    bool createOnly = false,
  }) async {
    final request = http.Request('PUT', _objectUri(key))
      ..headers.addAll({
        ..._authorization,
        if (ifMatch != null) 'if-match': ifMatch,
        if (createOnly) 'if-none-match': '*',
      })
      ..bodyBytes = data;
    final response =
        await http.Response.fromStream(await _client.send(request));
    if (response.statusCode == 412) throw SyncPreconditionException(key);
    if (response.statusCode != 200 &&
        response.statusCode != 201 &&
        response.statusCode != 204) {
      throw http.ClientException(
        'WebDAV PUT failed with ${response.statusCode}.',
        request.url,
      );
    }
    final etag = response.headers['etag'];
    if (etag != null && etag.isNotEmpty) return etag;
    final refreshed = await read(key);
    if (refreshed?.etag case final refreshedEtag?) return refreshedEtag;
    throw StateError('WebDAV server did not return an ETag for $key.');
  }

  @override
  Future<void> delete(String key, {String? ifMatch}) async {
    final request = http.Request('DELETE', _objectUri(key))
      ..headers.addAll({
        ..._authorization,
        if (ifMatch != null) 'if-match': ifMatch,
      });
    final response =
        await http.Response.fromStream(await _client.send(request));
    if (response.statusCode == 412) throw SyncPreconditionException(key);
    if (response.statusCode != 200 &&
        response.statusCode != 204 &&
        response.statusCode != 404) {
      throw http.ClientException(
        'WebDAV DELETE failed with ${response.statusCode}.',
        request.url,
      );
    }
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

  static String _directoryPath(String value) =>
      value.isEmpty || value.endsWith('/') ? value : '$value/';
}
