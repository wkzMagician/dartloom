library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartloom_model/dartloom_model.dart';

import 'src/model_http_client.dart';

export 'src/account_auth.dart';
export 'src/chatgpt_generation.dart';

/// OpenAI-compatible embeddings, independently configured from generation.
class ApiEmbeddingModel implements EmbeddingModel {
  ApiEmbeddingModel({
    required this.connection,
    this.credential,
    ModelHttpTransport? transport,
  }) : transport = transport ?? ModelHttpTransport();

  final ModelConnection connection;
  final String? credential;
  final ModelHttpTransport transport;

  @override
  String get identity =>
      'api:${connection.endpoint.replaceFirst(RegExp(r'/+$'), '')}:${connection.model}';

  @override
  Future<List<List<double>>> embed(List<String> texts) async {
    if (texts.isEmpty) return [];
    final response = await transport.post(connection.endpoint, 'embeddings', {
      'model': connection.model,
      'input': texts,
      'encoding_format': 'float',
    }, credential: credential);
    final data = response['data'];
    if (data is! List || data.length != texts.length) {
      throw const ModelException('Unexpected embedding count');
    }
    final ordered = List<List<double>?>.filled(texts.length, null);
    for (final item in data) {
      if (item is! Map || item['index'] is! int) {
        throw const ModelException('Missing embedding index');
      }
      final index = item['index'] as int;
      final vector = item['embedding'];
      if (index < 0 ||
          index >= ordered.length ||
          ordered[index] != null ||
          vector is! List ||
          vector.isEmpty ||
          vector.any((v) => v is! num || !v.isFinite)) {
        throw const ModelException('Invalid embedding vector');
      }
      ordered[index] = vector.cast<num>().map((v) => v.toDouble()).toList();
    }
    if (ordered.any((v) => v == null || v.length != ordered.first!.length)) {
      throw const ModelException('Inconsistent embedding dimensions');
    }
    return ordered.cast<List<double>>();
  }
}

/// HTTP errors deliberately omit provider response bodies and authorization.
class ModelHttpTransport {
  ModelHttpTransport({this.timeout = const Duration(seconds: 90)});
  final Duration timeout;

  Future<Map<String, Object?>> post(
    String endpoint,
    String resource,
    Map<String, Object?> body, {
    String? credential,
  }) async {
    final base = Uri.tryParse(endpoint);
    if (base == null ||
        !['http', 'https'].contains(base.scheme) ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      throw const ModelException('Invalid model service URL');
    }
    final client = await createModelHttpClient(base);
    try {
      return await (() async {
        final uri = base.replace(
          path: '${base.path.replaceFirst(RegExp(r'/+$'), '')}/$resource',
        );
        final request = await client.postUrl(uri);
        request.followRedirects = false;
        request.headers.contentType = ContentType.json;
        if (credential != null && credential.isNotEmpty) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $credential',
          );
        }
        request.write(jsonEncode(body));
        final response = await request.close();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw ModelException(
            'Model service returned HTTP ${response.statusCode}',
          );
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 8 * 1024 * 1024) {
            throw const ModelException('Model response is too large');
          }
        }
        final value = jsonDecode(utf8.decode(bytes));
        if (value is! Map<String, Object?>) {
          throw const ModelException('Model response must be a JSON object');
        }
        return value;
      })().timeout(timeout);
    } on ModelException {
      rethrow;
    } on Object {
      throw const ModelException('Model request failed or timed out');
    } finally {
      client.close(force: true);
    }
  }
}

/// OpenAI-compatible Chat Completions endpoint; model choice is caller-owned.
class ApiGenerationModel implements GenerationModel {
  ApiGenerationModel({
    required this.connection,
    this.credential,
    ModelHttpTransport? transport,
  }) : transport = transport ?? ModelHttpTransport();
  final ModelConnection connection;
  final String? credential;
  final ModelHttpTransport transport;

  @override
  Future<String> generate(ModelRequest request) async {
    final response = await transport.post(
      connection.endpoint,
      'chat/completions',
      {
        'model': connection.model,
        'messages': [
          {'role': 'system', 'content': request.system},
          {'role': 'user', 'content': request.input},
        ],
        'response_format': {'type': 'json_object'},
        'stream': false,
      },
      credential: credential,
    );
    final choices = response['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final message = (choices.first as Map)['message'];
      if (message is Map && message['content'] is String) {
        return message['content'] as String;
      }
    }
    throw const ModelException('Model response has no generated text');
  }
}

class OllamaGenerationModel implements GenerationModel {
  OllamaGenerationModel({
    required this.connection,
    ModelHttpTransport? transport,
  }) : transport = transport ?? ModelHttpTransport();
  final ModelConnection connection;
  final ModelHttpTransport transport;

  @override
  Future<String> generate(ModelRequest request) async {
    final response = await transport.post(connection.endpoint, 'api/chat', {
      'model': connection.model,
      'messages': [
        {'role': 'system', 'content': request.system},
        {'role': 'user', 'content': request.input},
      ],
      'format': 'json',
      'stream': false,
    });
    final message = response['message'];
    if (message is Map && message['content'] is String) {
      return message['content'] as String;
    }
    throw const ModelException('Local model returned no generated text');
  }
}

/// Uses an already-running local Ollama server; never downloads a model.
class OllamaEmbeddingModel implements EmbeddingModel {
  OllamaEmbeddingModel({
    required this.endpoint,
    required this.model,
    ModelHttpTransport? transport,
  }) : transport = transport ?? ModelHttpTransport();
  final String endpoint;
  final String model;
  final ModelHttpTransport transport;

  @override
  String get identity => 'ollama:$endpoint:$model';

  @override
  Future<List<List<double>>> embed(List<String> texts) async {
    if (texts.isEmpty) return [];
    final response = await transport.post(endpoint, 'api/embed', {
      'model': model,
      'input': texts,
      'truncate': true,
    });
    final raw = response['embeddings'];
    if (raw is! List || raw.length != texts.length) {
      throw const ModelException(
        'Local embedding result count does not match input',
      );
    }
    final result = <List<double>>[];
    for (final vector in raw) {
      if (vector is! List ||
          vector.isEmpty ||
          vector.any((v) => v is! num || !v.isFinite)) {
        throw const ModelException('Invalid local embedding vector');
      }
      result.add(vector.cast<num>().map((n) => n.toDouble()).toList());
    }
    if (result.any((v) => v.length != result.first.length)) {
      throw const ModelException('Inconsistent local embedding dimensions');
    }
    return result;
  }
}

/// Codex CLI owns subscription login. No subscription tokens are read by Dartloom.
/// Unsupported on mobile. Prompts are passed through stdin, never shell text.
class CodexSubscriptionModel implements GenerationModel {
  CodexSubscriptionModel({
    required this.connection,
    this.timeout = const Duration(minutes: 3),
  });
  final ModelConnection connection;
  final Duration timeout;

  @override
  Future<String> generate(ModelRequest request) async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      throw const ModelException(
        'Subscription CLI requires a desktop platform',
      );
    }
    if (!RegExp(r'^[a-zA-Z0-9._:/-]*$').hasMatch(connection.model) ||
        connection.executable.contains(RegExp(r'[&|<>^%\r\n]'))) {
      throw const ModelException('Invalid subscription CLI configuration');
    }
    final folder = await Directory.systemTemp.createTemp('dartloom-model-');
    Process? process;
    try {
      final environment = Map<String, String>.of(Platform.environment)
        ..remove('OPENAI_API_KEY')
        ..remove('CODEX_API_KEY');
      final login = await Process.run(
        connection.executable,
        ['login', 'status'],
        workingDirectory: folder.path,
        environment: environment,
        includeParentEnvironment: false,
        runInShell: Platform.isWindows,
      ).timeout(const Duration(seconds: 15));
      if (login.exitCode != 0 ||
          !'${login.stdout} ${login.stderr}'.toLowerCase().contains(
            'chatgpt',
          )) {
        throw const ModelException(
          'Subscription mode requires Codex CLI signed in with ChatGPT.',
        );
      }
      process = await Process.start(
        connection.executable,
        [
          'exec',
          '--ignore-user-config',
          '--strict-config',
          '--ephemeral',
          '--disable',
          'shell_tool',
          '--disable',
          'image_generation',
          '-c',
          'mcp_servers={}',
          '-c',
          'web_search="disabled"',
          '-c',
          'tools.view_image=false',
          '-c',
          'project_doc_max_bytes=0',
          '--skip-git-repo-check',
          '--sandbox',
          'read-only',
          '--json',
          if (connection.model.isNotEmpty) ...['--model', connection.model],
          '-',
        ],
        workingDirectory: folder.path,
        environment: environment,
        includeParentEnvironment: false,
        runInShell: Platform.isWindows,
      );
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.drain<void>();
      process.stdin.write('${request.system}\n\n${request.input}');
      await process.stdin.close();
      final exit = await process.exitCode.timeout(timeout);
      await errors;
      if (exit != 0)
        throw ModelException(
          'Subscription CLI failed (exit $exit). Check CLI login.',
        );
      return parseCodexOutput(await output);
    } on ModelException {
      rethrow;
    } on Object {
      throw const ModelException(
        'Subscription CLI unavailable or timed out. Check installation and login.',
      );
    } finally {
      process?.kill();
      await folder.delete(recursive: true);
    }
  }

  static String parseCodexOutput(String output) {
    String? text;
    for (final line in const LineSplitter().convert(output)) {
      try {
        final value = jsonDecode(line);
        if (value is Map && value['type'] == 'item.completed') {
          final item = value['item'];
          if (item is Map &&
              item['type'] == 'agent_message' &&
              item['text'] is String) {
            text = item['text'] as String;
          }
        }
      } on FormatException {
        /* Ignore progress lines from older CLIs. */
      }
    }
    if (text == null)
      throw const ModelException(
        'Subscription CLI returned no assistant message',
      );
    return text;
  }
}
