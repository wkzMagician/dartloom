import 'dart:async';
import 'dart:io';

Future<String>? _windowsProxy;
DateTime? _proxyReadAt;

bool _loopback(Uri uri) =>
    const {
      'localhost',
      '127.0.0.1',
      '::1',
      '[::1]',
    }.contains(uri.host.toLowerCase()) ||
    uri.host.startsWith('127.');

bool _environmentBypasses(Uri target) {
  final noProxy =
      Platform.environment['no_proxy'] ??
      Platform.environment['NO_PROXY'] ??
      '';
  if (noProxy.isEmpty) return false;
  return HttpClient.findProxyFromEnvironment(
        target,
        environment: {
          'http_proxy': 'http://proxy.invalid:9',
          'https_proxy': 'http://proxy.invalid:9',
          'no_proxy': noProxy,
        },
      ) ==
      'DIRECT';
}

/// Local model inputs always stay on the local connection. Public services use
/// the environment proxy, then Windows' configured manual system proxy.
Future<HttpClient> createModelHttpClient(Uri target) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  if (_loopback(target)) {
    client.findProxy = (_) => 'DIRECT';
    return client;
  }
  var registry = '';
  if (Platform.isWindows &&
      HttpClient.findProxyFromEnvironment(target) == 'DIRECT' &&
      !_environmentBypasses(target)) {
    if (_windowsProxy == null ||
        _proxyReadAt == null ||
        DateTime.now().difference(_proxyReadAt!) > const Duration(minutes: 1)) {
      _proxyReadAt = DateTime.now();
      _windowsProxy = _readWindowsProxy();
    }
    registry = await _windowsProxy!;
  }
  client.findProxy = (uri) {
    if (_loopback(uri)) return 'DIRECT';
    final value = HttpClient.findProxyFromEnvironment(uri);
    if (value != 'DIRECT' || _environmentBypasses(uri)) return value;
    return windowsModelProxy(registry, uri);
  };
  return client;
}

Future<String> _readWindowsProxy() async {
  try {
    final result = await Process.run('reg.exe', const [
      'query',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
    ]).timeout(const Duration(seconds: 3));
    return result.exitCode == 0 ? result.stdout as String : '';
  } on Object {
    return '';
  }
}

/// Parse only documented Internet Settings values; never log registry output.
String windowsModelProxy(String registry, Uri target) {
  if (_loopback(target)) return 'DIRECT';
  String value(String name) =>
      RegExp(
        '^\\s*$name\\s+REG_\\w+\\s+(.+)\\s*\$',
        multiLine: true,
      ).firstMatch(registry)?.group(1)?.trim() ??
      '';
  final enabled = value('ProxyEnable');
  if (enabled != '0x1' && enabled != '1') return 'DIRECT';
  final host = target.host.toLowerCase();
  for (final entry in value('ProxyOverride').split(';')) {
    final rule = entry.trim().toLowerCase();
    if (rule.isEmpty) continue;
    if (rule == '<local>' && !host.contains('.') && !host.contains(':'))
      return 'DIRECT';
    if (rule.startsWith('<')) continue;
    final pattern = RegExp.escape(rule).replaceAll(r'\*', '.*');
    if (RegExp('^$pattern\$').hasMatch(host)) return 'DIRECT';
  }
  final server = value('ProxyServer');
  var address = server;
  if (server.contains('=')) {
    final mappings = <String, String>{};
    for (final entry in server.split(';')) {
      final split = entry.indexOf('=');
      if (split > 0)
        mappings[entry.substring(0, split).trim().toLowerCase()] = entry
            .substring(split + 1)
            .trim();
    }
    address = mappings[target.scheme] ?? '';
  }
  if (address.isEmpty || address.contains(RegExp(r'[\r\n;\s]')))
    return 'DIRECT';
  final uri = Uri.tryParse(
    address.contains('://') ? address : 'http://$address',
  );
  if (uri == null ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      !const {'http', 'https'}.contains(uri.scheme) ||
      uri.port < 1 ||
      uri.port > 65535 ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/'))
    return 'DIRECT';
  return 'PROXY ${uri.host.contains(':') ? '[${uri.host}]' : uri.host}:${uri.port}';
}
