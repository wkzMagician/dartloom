import 'package:dartloom_model_io/src/model_http_client.dart';
import 'package:test/test.dart';

void main() {
  const single = '''
HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings
    ProxyEnable    REG_DWORD    0x1
    ProxyServer    REG_SZ    127.0.0.1:7897
''';
  test('Windows manual proxy is used for public model services', () {
    expect(
      windowsModelProxy(
        single,
        Uri.parse('https://auth.openai.com/oauth/token'),
      ),
      'PROXY 127.0.0.1:7897',
    );
    expect(
      windowsModelProxy(
        single.replaceFirst('0x1', '0x0'),
        Uri.parse('https://auth.openai.com'),
      ),
      'DIRECT',
    );
    expect(
      windowsModelProxy(
        single.replaceFirst('127.0.0.1:7897', 'proxy.example:80'),
        Uri.parse('https://auth.openai.com'),
      ),
      'PROXY proxy.example:80',
    );
  });
  test('localhost and loopback Ollama never leave the machine', () {
    for (final url in [
      'http://127.0.0.1:11434',
      'http://localhost:11434',
      'http://[::1]:11434',
      'http://127.3.2.1:11434',
    ]) {
      expect(windowsModelProxy(single, Uri.parse(url)), 'DIRECT');
    }
  });
  test('per-protocol proxies and explicit bypasses are respected', () {
    const registry = '''
    ProxyEnable    REG_DWORD    0x1
    ProxyServer    REG_SZ    http=127.0.0.1:8888;https=127.0.0.1:7897
    ProxyOverride    REG_SZ    <local>;*.internal;api.example.com
''';
    expect(
      windowsModelProxy(registry, Uri.parse('https://openrouter.ai/api/v1')),
      'PROXY 127.0.0.1:7897',
    );
    expect(
      windowsModelProxy(registry, Uri.parse('http://models.example.com/v1')),
      'PROXY 127.0.0.1:8888',
    );
    for (final url in [
      'http://intranet',
      'https://notes.internal',
      'https://API.example.com',
    ]) {
      expect(windowsModelProxy(registry, Uri.parse(url)), 'DIRECT');
    }
  });
  test('malformed proxy values do not inject proxy directives', () {
    for (final address in [
      'http://user:secret@proxy:8080',
      'proxy:8080;DIRECT',
      'proxy:99999',
      'socks://proxy:1080',
    ]) {
      final registry = single.replaceFirst('127.0.0.1:7897', address);
      expect(
        windowsModelProxy(registry, Uri.parse('https://auth.openai.com')),
        'DIRECT',
      );
    }
  });
}
