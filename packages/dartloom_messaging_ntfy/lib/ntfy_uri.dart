Uri ntfyTopicUri(Uri server, String channel, {String? suffix}) {
  if (server.hasQuery || server.hasFragment) {
    throw ArgumentError.value(
      server,
      'server',
      'must not contain a query or fragment',
    );
  }
  if (channel.isEmpty || channel.contains('/')) {
    throw ArgumentError.value(channel, 'channel', 'must be one path segment');
  }
  final basePath = server.path.endsWith('/') ? server.path : '${server.path}/';
  final encoded = Uri.encodeComponent(channel);
  return server.replace(path: '$basePath$encoded${suffix ?? ''}');
}

bool ntfyReferenceBelongsToServer(Uri server, Uri reference) {
  if (server.scheme.toLowerCase() != reference.scheme.toLowerCase() ||
      server.host.toLowerCase() != reference.host.toLowerCase() ||
      _effectivePort(server) != _effectivePort(reference)) {
    return false;
  }
  final basePath = server.path.isEmpty ? '/' : server.path;
  return basePath == '/' || reference.path.startsWith(basePath);
}

int _effectivePort(Uri uri) {
  if (uri.hasPort) return uri.port;
  return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
}
