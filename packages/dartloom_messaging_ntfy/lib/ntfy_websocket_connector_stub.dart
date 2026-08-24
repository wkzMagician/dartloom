import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectNtfyWebSocket(
  Uri uri, {
  Map<String, String>? headers,
}) => throw UnsupportedError(
  'authenticated ntfy WebSockets are unavailable on this platform',
);
