class NtfyCredentials {
  NtfyCredentials(String rawToken) : token = _validate(rawToken);

  final String token;

  String get authorizationHeader => 'Bearer $token';
}

String _validate(String value) {
  final token = value.trim();
  if (!token.startsWith('tk_') || token.length <= 3) {
    throw const FormatException('ntfy token must start with tk_');
  }
  if (token.contains(RegExp(r'\s'))) {
    throw const FormatException('ntfy token must not contain whitespace');
  }
  return token;
}
