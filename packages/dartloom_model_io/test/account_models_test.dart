import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartloom_model/dartloom_model.dart';
import 'package:dartloom_model_io/dartloom_model_io.dart';
import 'package:test/test.dart';

String jwt(Map<String, Object?> claims) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '')}.signature';

void main() {
  test(
    'OpenRouter uses random S256 PKCE and exchanges code with its own verifier',
    () async {
      Uri? calledUrl;
      Map<String, String>? payload;
      final auth = ModelAccountAuth(
        request: (uri, body, {form = false}) async {
          calledUrl = uri;
          payload = body;
          return const AccountHttpResponse(200, {
            'key': 'test-router-key',
            'user_id': 'test-user',
          });
        },
      );
      final grant = auth.beginOpenRouter();
      expect(grant.verifier, isNot(auth.beginOpenRouter().verifier));
      final query = grant.authorizationUrl.queryParameters;
      expect(query['code_challenge_method'], 'S256');
      expect(query.containsKey('callback_url'), isFalse);
      expect(
        query['code_challenge'],
        base64Url
            .encode(sha256.convert(ascii.encode(grant.verifier)).bytes)
            .replaceAll('=', ''),
      );
      final session = await auth.finishOpenRouter(
        grant,
        ' authorization-code ',
      );
      expect(calledUrl.toString(), 'https://openrouter.ai/api/v1/auth/keys');
      expect(payload, {
        'code': 'authorization-code',
        'code_verifier': grant.verifier,
        'code_challenge_method': 'S256',
      });
      expect(session.accessToken, 'test-router-key');
    },
  );

  test(
    'ChatGPT device flow handles pending, server PKCE, and refresh rotation',
    () async {
      var poll = 0;
      final auth = ModelAccountAuth(
        request: (uri, body, {form = false}) async {
          if (uri.path.endsWith('usercode')) {
            expect(body['client_id'], ModelAccountAuth.chatGptClientId);
            return const AccountHttpResponse(200, {
              'device_auth_id': 'device',
              'usercode': 'CODE-123',
              'interval': '5',
            });
          }
          if (uri.path.endsWith('deviceauth/token')) {
            expect(body, {'device_auth_id': 'device', 'user_code': 'CODE-123'});
            if (++poll == 1) return const AccountHttpResponse(403, {});
            return const AccountHttpResponse(200, {
              'authorization_code': 'auth-code',
              'code_verifier': 'server-verifier',
            });
          }
          expect(form, isTrue);
          if (body['grant_type'] == 'authorization_code') {
            expect(body['code_verifier'], 'server-verifier');
            expect(
              body['redirect_uri'],
              'https://auth.openai.com/deviceauth/callback',
            );
            return AccountHttpResponse(200, {
              'access_token': jwt({'exp': 2000000000}),
              'refresh_token': 'first-refresh',
              'expires_in': 3600,
              'id_token': jwt({
                'https://api.openai.com/auth': {
                  'chatgpt_account_id': 'account',
                },
              }),
            });
          }
          expect(body['refresh_token'], 'first-refresh');
          return const AccountHttpResponse(200, {
            'access_token': 'refreshed',
            'refresh_token': 'rotated',
            'expires_in': 3600,
          });
        },
      );
      final grant = await auth.beginChatGpt();
      expect(
        grant.verificationUrl.toString(),
        'https://auth.openai.com/codex/device',
      );
      expect(await auth.pollChatGpt(grant), isNull);
      final session = (await auth.pollChatGpt(grant))!;
      expect(session.accountId, 'account');
      expect(session.needsRefresh, isFalse);
      final refreshed = await auth.refreshChatGpt(session);
      expect(refreshed.accountId, 'account');
      expect(refreshed.refreshToken, 'rotated');
      expect(
        AccountSession.fromJson(refreshed.toJson()).accessToken,
        'refreshed',
      );
    },
  );

  test(
    'failed authorization errors never contain sensitive response bodies',
    () async {
      final auth = ModelAccountAuth(
        request: (uri, body, {form = false}) async => const AccountHttpResponse(
          401,
          {'access_token': 'private-provider-response'},
        ),
      );
      try {
        await auth.beginChatGpt();
        fail('Expected failure');
      } on ModelException catch (error) {
        expect(error.toString(), isNot(contains('private-provider-response')));
      }
    },
  );

  test(
    'API embeddings restore original order and reject incomplete or malformed vectors',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var invalid = false;
      server.listen((request) async {
        expect(request.uri.path, '/v1/embeddings');
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer test-key',
        );
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(body['input'], ['中文一', '中文二']);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': invalid
                ? [
                    {'index': 0, 'embedding': []},
                    {
                      'index': 0,
                      'embedding': [1],
                    },
                  ]
                : [
                    {
                      'index': 1,
                      'embedding': [0, 1],
                    },
                    {
                      'index': 0,
                      'embedding': [1, 0],
                    },
                  ],
          }),
        );
        await request.response.close();
      });
      final model = ApiEmbeddingModel(
        connection: ModelConnection(
          access: ModelAccess.api,
          endpoint: 'http://127.0.0.1:${server.port}/v1',
          model: 'vectors',
        ),
        credential: 'test-key',
      );
      expect(await model.embed(['中文一', '中文二']), [
        [1, 0],
        [0, 1],
      ]);
      invalid = true;
      expect(model.embed(['中文一', '中文二']), throwsA(isA<ModelException>()));
    },
  );

  test(
    'ChatGPT uses authenticated Responses SSE and requires completed output',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var complete = true;
      server.listen((request) async {
        expect(request.headers.value('ChatGPT-Account-Id'), 'test-account');
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer test-access',
        );
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(body['store'], isFalse);
        expect(body['stream'], isTrue);
        expect(body['instructions'], 'Analyze');
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'text/event-stream',
        );
        request.response.write(
          'data: ${jsonEncode({'type': 'response.output_text.delta', 'delta': '{"notes":[]}'})}\n\n',
        );
        if (complete)
          request.response.write('data: {"type":"response.completed"}\n\n');
        await request.response.close();
      });
      final model = ChatGptGenerationModel(
        model: 'chosen-model',
        session: const AccountSession(
          accessToken: 'test-access',
          accountId: 'test-account',
        ),
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/responses'),
      );
      expect(
        await model.generate(
          const ModelRequest(system: 'Analyze', input: 'Notes'),
        ),
        '{"notes":[]}',
      );
      complete = false;
      expect(
        model.generate(const ModelRequest(system: 'Analyze', input: 'Notes')),
        throwsA(isA<ModelException>()),
      );
    },
  );
}
