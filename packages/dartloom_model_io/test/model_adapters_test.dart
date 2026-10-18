import 'dart:convert';
import 'dart:io';

import 'package:dartloom_model/dartloom_model.dart';
import 'package:dartloom_model_io/dartloom_model_io.dart';
import 'package:test/test.dart';

void main() {
  test(
    'subscription runs a model-only CLI with stdin and rejects API-key login',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'dartloom-fake-cli-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final script = File(
        '${folder.path}/model${Platform.isWindows ? '.cmd' : '.sh'}',
      );
      final input = File('${folder.path}/input.txt');
      final args = File('${folder.path}/args.txt');
      Future<void> writeCli(String login) async {
        final event = jsonEncode({
          'type': 'item.completed',
          'item': {'type': 'agent_message', 'text': '{"ok":true}'},
        });
        if (Platform.isWindows) {
          await script.writeAsString(
            '@echo off\r\n'
            'if "%~1"=="login" (\r\necho $login\r\nexit /b 0\r\n)\r\n'
            'echo %* > "${args.path}"\r\nmore > "${input.path}"\r\n'
            'echo $event\r\n',
          );
        } else {
          String quoted(String path) => "'${path.replaceAll("'", "'\\''")}'";
          await script.writeAsString(
            '#!/bin/sh\n'
            'if [ "\$1" = login ]; then printf "%s\\n" "$login"; exit 0; fi\n'
            'printf "%s\\n" "\$@" > ${quoted(args.path)}\n'
            'cat > ${quoted(input.path)}\nprintf "%s\\n" \'$event\'\n',
          );
          await Process.run('chmod', ['+x', script.path]);
        }
      }

      await writeCli('Logged in using ChatGPT');
      final adapter = CodexSubscriptionModel(
        connection: ModelConnection(
          access: ModelAccess.subscription,
          model: 'selected',
          executable: script.path,
        ),
      );
      expect(
        await adapter.generate(
          const ModelRequest(system: 'system prompt', input: 'note data'),
        ),
        '{"ok":true}',
      );
      expect(
        await input.readAsString(),
        allOf(contains('system prompt'), contains('note data')),
      );
      final flags = await args.readAsString();
      for (final flag in [
        '--ignore-user-config',
        '--ephemeral',
        '--strict-config',
        'shell_tool',
        'mcp_servers={}',
        'tools.view_image=false',
        'project_doc_max_bytes=0',
      ]) {
        expect(flags, contains(flag));
      }
      await writeCli('Logged in using an API key');
      await expectLater(
        adapter.generate(const ModelRequest(system: '', input: 'must not run')),
        throwsA(
          isA<ModelException>().having(
            (e) => e.message,
            'reason',
            contains('ChatGPT'),
          ),
        ),
      );
      expect(await input.readAsString(), isNot(contains('must not run')));
    },
  );

  late HttpServer server;
  late String endpoint;
  final requests = <Map<String, Object?>>[];
  setUp(() async {
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    endpoint = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      requests.add({
        'path': request.uri.path,
        'body': body,
        'authorization': request.headers.value(HttpHeaders.authorizationHeader),
      });
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/v1/chat/completions') {
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '{"ok":true}'},
              },
            ],
          }),
        );
      } else if (request.uri.path == '/api/embed') {
        request.response.write(
          jsonEncode({
            'embeddings': [
              for (final _ in body['input'] as List) [1, 0, .5],
            ],
          }),
        );
      } else if (request.uri.path == '/api/chat') {
        request.response.write(
          jsonEncode({
            'message': {'content': '{"local":true}'},
          }),
        );
      } else {
        request.response.statusCode = 401;
        request.response.write('sensitive provider response');
      }
      await request.response.close();
    });
  });
  tearDown(() => server.close(force: true));
  test(
    'API adapter forwards selected model and JSON messages to the configured endpoint',
    () async {
      final adapter = ApiGenerationModel(
        connection: ModelConnection(
          access: ModelAccess.api,
          endpoint: '$endpoint/v1',
          model: 'chosen-model',
        ),
        credential: 'test-credential',
      );
      expect(
        await adapter.generate(
          const ModelRequest(system: 'system', input: 'note'),
        ),
        '{"ok":true}',
      );
      expect(requests.single['path'], '/v1/chat/completions');
      expect(requests.single['authorization'], 'Bearer test-credential');
      expect((requests.single['body'] as Map)['model'], 'chosen-model');
    },
  );
  test(
    'local generation and embedding use Ollama protocols and batch embeddings',
    () async {
      final generator = OllamaGenerationModel(
        connection: ModelConnection(
          access: ModelAccess.local,
          endpoint: endpoint,
          model: 'local-model',
        ),
      );
      expect(
        await generator.generate(const ModelRequest(system: '', input: 'note')),
        '{"local":true}',
      );
      final embedder = OllamaEmbeddingModel(
        endpoint: endpoint,
        model: 'local-embedding',
      );
      expect(await embedder.embed(['one', 'two']), [
        [1, 0, .5],
        [1, 0, .5],
      ]);
      expect((requests.last['body'] as Map)['input'], ['one', 'two']);
      expect(requests.last['authorization'], isNull);
    },
  );
  test('transport errors exclude provider response bodies', () async {
    await expectLater(
      ModelHttpTransport().post(endpoint, 'missing', {}),
      throwsA(
        isA<ModelException>().having(
          (e) => e.message,
          'message',
          allOf(contains('401'), isNot(contains('sensitive'))),
        ),
      ),
    );
  });
  test(
    'Codex subscription adapter extracts assistant messages from event streams',
    () {
      expect(
        CodexSubscriptionModel.parseCodexOutput('''{"type":"thread.started"}
{"type":"item.completed","item":{"type":"agent_message","text":"{\\"notes\\":[]}"}}
{"type":"turn.completed"}'''),
        '{"notes":[]}',
      );
      expect(
        () => CodexSubscriptionModel.parseCodexOutput('{"type":"error"}'),
        throwsA(isA<ModelException>()),
      );
    },
  );
}
