import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dartloom_model/dartloom_model.dart';

import 'model_http_client.dart';

enum ModelAccountProvider { chatgpt, openRouter }

class AccountSession {
  const AccountSession({
    required this.accessToken,
    this.refreshToken = '',
    this.accountId = '',
    this.expiresAt,
  });
  final String accessToken;
  final String refreshToken;
  final String accountId;
  final DateTime? expiresAt;
  bool get needsRefresh =>
      expiresAt != null &&
      !expiresAt!.isAfter(
        DateTime.now().toUtc().add(const Duration(minutes: 1)),
      );
  Map<String, Object?> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'account_id': accountId,
    'expires_at': expiresAt?.toUtc().toIso8601String(),
  };
  factory AccountSession.fromJson(Map<String, Object?> value) => AccountSession(
    accessToken: value['access_token'] as String,
    refreshToken: value['refresh_token'] as String? ?? '',
    accountId: value['account_id'] as String? ?? '',
    expiresAt: DateTime.tryParse(value['expires_at'] as String? ?? ''),
  );
}

class AccountHttpResponse {
  const AccountHttpResponse(this.status, this.body);
  final int status;
  final Map<String, Object?> body;
}

class AccountHttpException extends ModelException {
  const AccountHttpException(this.status)
    : super('Account service request failed');
  final int status;
}

typedef AccountRequest =
    Future<AccountHttpResponse> Function(
      Uri url,
      Map<String, String> body, {
      bool form,
    });

/// Deliberately omits response bodies, codes and tokens from errors.
Future<AccountHttpResponse> requestAccount(
  Uri url,
  Map<String, String> body, {
  bool form = false,
}) async {
  final client = await createModelHttpClient(url);
  try {
    return await (() async {
      final request = await client.postUrl(url);
      request.followRedirects = false;
      request.headers.contentType = form
          ? ContentType(
              'application',
              'x-www-form-urlencoded',
              charset: 'utf-8',
            )
          : ContentType.json;
      request.write(form ? Uri(queryParameters: body).query : jsonEncode(body));
      final response = await request.close();
      // Error bodies can contain credentials. They are not parsed or exposed.
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return AccountHttpResponse(response.statusCode, const {});
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > 1024 * 1024) {
          throw const ModelException('Account response is too large');
        }
      }
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map<String, Object?>) {
        throw const ModelException('Invalid account response');
      }
      return AccountHttpResponse(response.statusCode, value);
    })().timeout(const Duration(seconds: 30));
  } on ModelException {
    rethrow;
  } on Object {
    throw const ModelException('Account request failed or timed out');
  } finally {
    client.close(force: true);
  }
}

class ChatGptDeviceGrant {
  const ChatGptDeviceGrant({
    required this.deviceId,
    required this.userCode,
    required this.verificationUrl,
    required this.interval,
    required this.expiresAt,
  });
  final String deviceId, userCode;
  final Uri verificationUrl;
  final Duration interval;
  final DateTime expiresAt;
}

class OpenRouterGrant {
  const OpenRouterGrant({
    required this.verifier,
    required this.authorizationUrl,
  });
  final String verifier;
  final Uri authorizationUrl;
}

/// Native account authorization; the caller owns UI and secure persistence.
/// ChatGPT protocol follows openai/codex login/src/device_code_auth.rs.
/// OpenRouter uses its documented headless PKCE flow (authorization code paste).
class ModelAccountAuth {
  ModelAccountAuth({AccountRequest? request})
    : request = request ?? requestAccount;
  final AccountRequest request;
  static const chatGptClientId = 'app_EMoamEEZ73f0CkXaXp7hrann';
  static final _issuer = Uri.parse('https://auth.openai.com');

  Future<ChatGptDeviceGrant> beginChatGpt() async {
    final value = await _post(
      _issuer.resolve('/api/accounts/deviceauth/usercode'),
      {'client_id': chatGptClientId},
    );
    final id = value['device_auth_id'];
    final code = value['user_code'] ?? value['usercode'];
    if (id is! String || id.isEmpty || code is! String || code.isEmpty) {
      throw const ModelException('Invalid device authorization response');
    }
    final seconds = int.tryParse('${value['interval']}') ?? 5;
    return ChatGptDeviceGrant(
      deviceId: id,
      userCode: code,
      verificationUrl: _issuer.resolve('/codex/device'),
      interval: Duration(seconds: seconds.clamp(5, 60)),
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
    );
  }

  /// One poll only; scheduling and cancellation are caller-owned.
  Future<AccountSession?> pollChatGpt(ChatGptDeviceGrant grant) async {
    if (!DateTime.now().toUtc().isBefore(grant.expiresAt)) {
      throw const ModelException('Device authorization expired');
    }
    final response = await request(
      _issuer.resolve('/api/accounts/deviceauth/token'),
      {'device_auth_id': grant.deviceId, 'user_code': grant.userCode},
    );
    if (response.status == 403 || response.status == 404) return null;
    _check(response);
    final code = response.body['authorization_code'];
    final verifier = response.body['code_verifier'];
    if (code is! String || verifier is! String) {
      throw const ModelException('Invalid device authorization response');
    }
    final tokens = await _post(_issuer.resolve('/oauth/token'), {
      'grant_type': 'authorization_code',
      'client_id': chatGptClientId,
      'code': code,
      'code_verifier': verifier,
      'redirect_uri': '${_issuer.origin}/deviceauth/callback',
    }, form: true);
    return _chatGptSession(tokens);
  }

  Future<AccountSession> refreshChatGpt(AccountSession previous) async {
    if (previous.refreshToken.isEmpty) {
      throw const ModelException('Please sign in to ChatGPT again');
    }
    final tokens = await _post(_issuer.resolve('/oauth/token'), {
      'grant_type': 'refresh_token',
      'client_id': chatGptClientId,
      'refresh_token': previous.refreshToken,
    }, form: true);
    return _chatGptSession(tokens, previous: previous);
  }

  OpenRouterGrant beginOpenRouter() {
    final random = Random.secure();
    final verifier = base64Url
        .encode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
    return OpenRouterGrant(
      verifier: verifier,
      authorizationUrl: Uri.https('openrouter.ai', '/auth', {
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
      }),
    );
  }

  Future<AccountSession> finishOpenRouter(
    OpenRouterGrant grant,
    String code,
  ) async {
    if (code.trim().isEmpty)
      throw const ModelException('Authorization code is empty');
    final value =
        await _post(Uri.parse('https://openrouter.ai/api/v1/auth/keys'), {
          'code': code.trim(),
          'code_verifier': grant.verifier,
          'code_challenge_method': 'S256',
        });
    final key = value['key'];
    if (key is! String || key.isEmpty) {
      throw const ModelException('Invalid OpenRouter authorization response');
    }
    return AccountSession(
      accessToken: key,
      accountId: value['user_id'] as String? ?? '',
    );
  }

  Future<Map<String, Object?>> _post(
    Uri uri,
    Map<String, String> body, {
    bool form = false,
  }) async {
    final response = await request(uri, body, form: form);
    _check(response);
    return response.body;
  }

  static void _check(AccountHttpResponse response) {
    if (response.status < 200 || response.status >= 300) {
      throw AccountHttpException(response.status);
    }
  }

  static Map<String, Object?> _claims(String token) {
    try {
      final value = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
      );
      return (value as Map).cast<String, Object?>();
    } on Object {
      return const {};
    }
  }

  static AccountSession _chatGptSession(
    Map<String, Object?> tokens, {
    AccountSession? previous,
  }) {
    final access = tokens['access_token'];
    if (access is! String || access.isEmpty) {
      throw const ModelException('Invalid ChatGPT authorization response');
    }
    final idClaims = _claims(tokens['id_token'] as String? ?? '');
    final accessClaims = _claims(access);
    final auth =
        idClaims['https://api.openai.com/auth'] ??
        accessClaims['https://api.openai.com/auth'];
    final accountId =
        (auth is Map ? auth['chatgpt_account_id'] as String? : null) ??
        previous?.accountId ??
        '';
    if (accountId.isEmpty)
      throw const ModelException('ChatGPT account ID is missing');
    final expires = tokens['expires_in'];
    final jwtExpiry = accessClaims['exp'];
    return AccountSession(
      accessToken: access,
      refreshToken:
          tokens['refresh_token'] as String? ?? previous?.refreshToken ?? '',
      accountId: accountId,
      expiresAt: expires is num
          ? DateTime.now().toUtc().add(Duration(seconds: expires.toInt()))
          : jwtExpiry is num
          ? DateTime.fromMillisecondsSinceEpoch(
              jwtExpiry.toInt() * 1000,
              isUtc: true,
            )
          : DateTime.now().toUtc().add(const Duration(minutes: 30)),
    );
  }
}
