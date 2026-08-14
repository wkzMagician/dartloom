import 'dart:convert';
import 'dart:typed_data';

import 'package:dartloom_sync/dartloom_sync.dart';
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

  test('binary write, read, and delete use conditional requests', () async {
    final payload = <int>[0, 255, 128, 10];
    final methods = <String>[];
    final client = MockClient((request) async {
      methods.add(request.method);
      switch (request.method) {
        case 'PUT':
          expect(request.headers['if-none-match'], '*');
          expect(request.bodyBytes, payload);
          return http.Response('', 201, headers: {'etag': 'w/"probe"'});
        case 'GET':
          return http.Response.bytes(payload, 200,
              headers: {'etag': 'W/"probe"'});
        case 'DELETE':
          expect(request.headers['if-match'], 'W/"probe"');
          return http.Response('', 204);
        default:
          return http.Response('', 500);
      }
    });
    final replica = _replica(client);

    final version = await replica.write(
      'binary',
      Uint8List.fromList(payload),
      condition: const RemoteWriteCondition.create(),
    );
    final object = await replica.read('binary');
    await replica.delete(
      'binary',
      condition: RemoteWriteCondition.version(version),
    );

    expect(version, 'W/"probe"');
    expect(object?.data, payload);
    expect(methods, ['PUT', 'GET', 'DELETE']);
  });

  test('update uses If-Match and preserves strong ETag semantics', () async {
    final client = MockClient((request) async {
      expect(request.method, 'PUT');
      expect(request.headers['if-match'], '"strong"');
      return http.Response('', 204, headers: {'etag': '"next"'});
    });

    final version = await _replica(client).write(
      'object',
      Uint8List(0),
      condition: const RemoteWriteCondition.version('"strong"'),
    );

    expect(version, '"next"');
    expect(version, isNot('W/"next"'));
  });

  test('missing ETag makes a listing partial and a GET invalid', () async {
    var method = 'PROPFIND';
    final client = MockClient((request) async {
      if (method == 'PROPFIND') {
        return http.Response(
          _multistatus([('/dav/MiniTodo/no-etag', null, false)]),
          207,
        );
      }
      return http.Response.bytes([1], 200);
    });
    final replica = _replica(client);

    expect((await replica.scan()).complete, isFalse);
    method = 'GET';
    await expectLater(
      replica.read('no-etag'),
      throwsA(_failure(SyncFailureKind.invalidResponse)),
    );
  });

  test('412 remains an explicit optimistic-concurrency failure', () async {
    final replica = _replica(MockClient((_) async => http.Response('', 412)));

    await expectLater(
      replica.write(
        'object',
        Uint8List(0),
        condition: const RemoteWriteCondition.create(),
      ),
      throwsA(isA<RemotePreconditionException>()),
    );
  });

  for (final entry in const [
    (401, SyncFailureKind.authentication),
    (403, SyncFailureKind.permission),
    (429, SyncFailureKind.serverLimit),
    (500, SyncFailureKind.connectivity),
  ]) {
    test('PROPFIND ${entry.$1} maps to ${entry.$2.name}', () async {
      final replica = _replica(
        MockClient((_) async => http.Response('', entry.$1)),
      );

      await expectLater(replica.scan(), throwsA(_failure(entry.$2)));
    });
  }

  test('listing at the configured server limit is explicitly partial',
      () async {
    final replica = _replica(
      MockClient((_) async => http.Response(
            _multistatus([('/dav/MiniTodo/one', '"v1"', false)]),
            207,
          )),
      listingLimitHint: 1,
    );

    final scan = await replica.scan();

    expect(scan.objects.single.key, 'one');
    expect(scan.complete, isFalse);
    expect(scan.cursor, isNull);
  });

  test('cursor cannot imply fake WebDAV pagination', () async {
    final replica = _replica(MockClient((_) async => http.Response('', 500)));

    await expectLater(
      replica.scan(cursor: 'next'),
      throwsA(_failure(SyncFailureKind.configuration)),
    );
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
    expect(methods.where((method) => method.contains('/json/todo-1')),
        isNot(contains(startsWith('DELETE'))));
  });

  test('concurrent legacy migration is idempotent and preserves source',
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
          207,
        );
      }
      if (request.method == 'GET' &&
          request.url.path == '/dav/MiniTodo/todo-1') {
        return http.Response('', 404);
      }
      if (request.method == 'GET') {
        return http.Response.bytes([1, 2, 3], 200,
            headers: {'etag': '"legacy"'});
      }
      if (request.method == 'PUT') return http.Response('', 412);
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
    expect(
      methods.where((method) =>
          method.startsWith('DELETE') && method.contains('/json/todo-1')),
      isEmpty,
    );
  });
}

WebDavRemoteReplica _replica(
  http.Client client, {
  int listingLimitHint = 750,
}) =>
    WebDavRemoteReplica(
      baseUrl: Uri.parse('https://example.test/dav/'),
      rootPath: 'MiniTodo',
      username: '',
      password: '',
      connectTimeout: const Duration(seconds: 1),
      requestTimeout: const Duration(seconds: 1),
      maxParallelRequests: 1,
      createMissingCollections: false,
      listingLimitHint: listingLimitHint,
      client: client,
    );

Matcher _failure(SyncFailureKind kind) => isA<SyncOperationException>().having(
      (error) => error.failure.kind,
      'failure kind',
      kind,
    );

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
