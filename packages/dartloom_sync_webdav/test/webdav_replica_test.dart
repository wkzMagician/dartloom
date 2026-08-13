import 'dart:convert';

import 'package:dartloom_sync_webdav/dartloom_sync_webdav.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('flat scan uses authoritative Depth 1 and ignores child contents',
      () async {
    http.Request? captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
          _multistatus([
            ('/dav/MiniTodo/', null, true),
            ('/dav/MiniTodo/todo-1', '"v1"', false),
            ('/dav/MiniTodo/json/', null, true),
          ]),
          207,
          headers: {'content-type': 'application/xml'});
    });
    final replica = WebDavRemoteReplica(
      baseUrl: Uri.parse('https://example.test/dav/'),
      rootPath: 'MiniTodo',
      username: '',
      password: '',
      connectTimeout: const Duration(seconds: 1),
      requestTimeout: const Duration(seconds: 1),
      maxParallelRequests: 1,
      createMissingCollections: false,
      client: client,
    );

    final scan = await replica.scan();

    expect(captured?.method, 'PROPFIND');
    expect(captured?.headers['depth'], '1');
    expect(captured?.headers['content-type'], contains('application/xml'));
    expect(scan.complete, isTrue);
    expect(scan.objects.map((object) => object.key), ['todo-1']);
  });

  test('legacy child collection is copied without deleting the source',
      () async {
    final methods = <String>[];
    final client = MockClient((request) async {
      methods.add('${request.method} ${request.url.path}');
      if (request.method == 'PROPFIND') {
        return http.Response(
            _multistatus([
              ('/dav/MiniTodo/json/', null, true),
              ('/dav/MiniTodo/json/todo-1', '"legacy"', false),
            ]),
            207);
      }
      if (request.method == 'GET' && request.url.path.endsWith('/todo-1')) {
        if (request.url.path.contains('/json/')) {
          return http.Response.bytes(utf8.encode('{"id":"1"}'), 200,
              headers: {'etag': '"legacy"'});
        }
        return http.Response('', 404);
      }
      if (request.method == 'PUT') {
        expect(request.headers['if-none-match'], '*');
        return http.Response('', 201, headers: {'etag': '"new"'});
      }
      return http.Response('', 500);
    });
    final replica = WebDavRemoteReplica(
      baseUrl: Uri.parse('https://example.test/dav/'),
      rootPath: 'MiniTodo',
      username: '',
      password: '',
      connectTimeout: const Duration(seconds: 1),
      requestTimeout: const Duration(seconds: 1),
      maxParallelRequests: 1,
      createMissingCollections: false,
      legacyCollection: 'json',
      legacyKeyPrefix: 'todo-',
      client: client,
    );

    await replica.initialize();

    expect(methods, contains('PUT /dav/MiniTodo/todo-1'));
    expect(methods.where((method) => method.startsWith('DELETE')), isEmpty);
  });
}

String _multistatus(List<(String, String?, bool)> entries) => '''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
${entries.map((entry) => '''
  <d:response>
    <d:href>${entry.$1}</d:href>
    <d:propstat><d:prop>
      ${entry.$2 == null ? '' : '<d:getetag>${entry.$2}</d:getetag>'}
      <d:resourcetype>${entry.$3 ? '<d:collection/>' : ''}</d:resourcetype>
    </d:prop></d:propstat>
  </d:response>''').join()}
</d:multistatus>
''';
