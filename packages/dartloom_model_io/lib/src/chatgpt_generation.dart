import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartloom_model/dartloom_model.dart';

import 'account_auth.dart';

import 'model_http_client.dart';

/// ChatGPT account requests use the Codex Responses service, not the API-key API.
class ChatGptGenerationModel implements GenerationModel {
  ChatGptGenerationModel({
    required this.model,
    required this.session,
    Uri? endpoint,
    this.originator = 'dartloom',
    this.timeout = const Duration(minutes: 3),
  }) : endpoint =
           endpoint ??
           Uri.parse('https://chatgpt.com/backend-api/codex/responses');
  final String model;
  final AccountSession session;
  final Uri endpoint;
  final String originator;
  final Duration timeout;

  @override
  Future<String> generate(ModelRequest request) async {
    final client = await createModelHttpClient(endpoint);
    try {
      return await (() async {
        final httpRequest = await client.postUrl(endpoint);
        httpRequest.followRedirects = false;
        httpRequest.headers.contentType = ContentType.json;
        httpRequest.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${session.accessToken}',
        );
        httpRequest.headers.set('ChatGPT-Account-Id', session.accountId);
        httpRequest.headers.set('originator', originator);
        httpRequest.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
        httpRequest.write(
          jsonEncode({
            'model': model,
            'instructions': request.system,
            'store': false,
            'stream': true,
            'input': [
              {
                'role': 'user',
                'content': [
                  {'type': 'input_text', 'text': request.input},
                ],
              },
            ],
          }),
        );
        final response = await httpRequest.close();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw AccountHttpException(response.statusCode);
        }
        final result = StringBuffer();
        var received = 0;
        var completed = false;
        await for (final line
            in response
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
          received += line.length;
          if (received > 8 * 1024 * 1024)
            throw const ModelException('Model response is too large');
          if (!line.startsWith('data:')) continue;
          final data = line.substring(5).trim();
          if (data.isEmpty || data == '[DONE]') continue;
          final event = jsonDecode(data) as Map;
          switch (event['type']) {
            case 'response.output_text.delta':
              result.write(event['delta'] as String? ?? '');
            case 'response.completed':
              completed = true;
              if (result.isEmpty) {
                final output = (event['response'] as Map?)?['output'];
                if (output is List) {
                  for (final item in output.whereType<Map>()) {
                    final content = item['content'];
                    if (content is List) {
                      for (final part in content.whereType<Map>()) {
                        if (part['type'] == 'output_text')
                          result.write(part['text'] as String? ?? '');
                      }
                    }
                  }
                }
              }
            case 'error' || 'response.failed' || 'response.incomplete':
              throw const ModelException('ChatGPT generation failed');
          }
        }
        if (!completed || result.isEmpty)
          throw const ModelException('Incomplete ChatGPT response');
        return result.toString();
      })().timeout(timeout);
    } on ModelException {
      rethrow;
    } on Object {
      throw const ModelException('ChatGPT request failed or timed out');
    } finally {
      client.close(force: true);
    }
  }
}
