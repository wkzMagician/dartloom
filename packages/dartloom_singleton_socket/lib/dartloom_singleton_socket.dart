import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartloom_resident/dartloom_resident.dart';
import 'package:dartloom_singleton/dartloom_singleton.dart';
import 'package:path_provider/path_provider.dart';

/// Loopback-socket single-instance adapter.
///
/// A deterministic loopback port is the primary ownership primitive. The
/// operating system owns the bind, so the claim survives Dart object lifetime
/// and is released automatically when the process exits. The same socket
/// carries second-instance arguments.
final class SocketSingleInstanceService implements SingleInstanceService {
  SocketSingleInstanceService({
    ResidentService? resident,
    int? port,
    String? identity,
    List<String> Function()? argumentSource,
    FutureOr<void> Function(int exitCode)? exitHandler,
  })  : _resident = resident,
        _configuredPort = port,
        _configuredIdentity = identity,
        _argumentSource = argumentSource ?? _defaultArguments,
        _exitHandler = exitHandler ?? _defaultExit;

  final ResidentService? _resident;
  final int? _configuredPort;
  final String? _configuredIdentity;
  final List<String> Function() _argumentSource;
  final FutureOr<void> Function(int exitCode) _exitHandler;

  SingleInstanceConfiguration _configuration =
      const SingleInstanceConfiguration();
  final _secondInstances = StreamController<List<String>>.broadcast();
  ServerSocket? _server;
  String? _identity;
  int? _port;
  bool _disposed = false;
  bool _primary = false;

  bool get isPrimary => _primary;
  int? get port => _port;
  String? get identity => _identity;

  @override
  Future<void> ensureSingleInstance({
    SingleInstanceDuplicateExit? onDuplicateExit,
  }) async {
    if (await acquirePrimary()) return;
    await _deliverArguments();
    await onDuplicateExit?.call();
    await _exitHandler(0);
  }

  @override
  Future<bool> acquirePrimary() async {
    if (_disposed) return false;
    await _resolveIdentity();

    for (final candidate in _candidatePorts()) {
      try {
        final server = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          candidate,
          shared: false,
        );
        _server = server;
        _port = candidate;
        _primary = true;
        server.listen(_handleConnection, onError: (_) {});
        return true;
      } on SocketException {
        // A different process may occupy a candidate. Probe it before moving
        // on: the primary instance owns the deterministic first port, and a
        // duplicate must not silently claim a later candidate.
        if (await _isDartloomPrimary(candidate)) {
          _port = candidate;
          return false;
        }
      }
    }
    return false;
  }

  @override
  Stream<List<String>> get onSecondInstance => _secondInstances.stream;

  @override
  Future<void> configure(SingleInstanceConfiguration configuration) async {
    _configuration = configuration;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _secondInstances.close();
    await _server?.close();
    _server = null;
    _primary = false;
  }

  Future<void> _resolveIdentity() async {
    if (_identity != null) return;
    if (_configuredIdentity != null) {
      _identity = _configuredIdentity;
      return;
    }
    final directory = await getApplicationSupportDirectory().catchError(
      (_) => Directory(Directory.systemTemp.path),
    );
    _identity = directory.path;
  }

  Iterable<int> _candidatePorts() sync* {
    final configured = _configuredPort;
    if (configured != null) {
      yield configured;
      return;
    }
    final base = _portFor(_identity!);
    for (var offset = 0; offset < 8; offset++) {
      yield 49152 + ((base - 49152 + offset) % 14000);
    }
  }

  Future<void> _handleConnection(Socket socket) async {
    try {
      final payload =
          await utf8.decoder.bind(socket).transform(const LineSplitter()).first;
      final decoded = jsonDecode(payload);
      if (decoded is! Map || decoded['identity'] != _identity) return;
      final kind = decoded['kind'];
      if (kind == 'ping') {
        socket.write('{"ok":true}');
        await socket.flush();
        return;
      }
      if (kind != 'args' || decoded['args'] is! List) return;
      final args = (decoded['args'] as List).map((e) => '$e').toList();
      _handleSecondInstance(args);
      socket.write('{"ok":true}');
      await socket.flush();
    } catch (_) {
      // Invalid or unrelated local traffic is ignored.
    } finally {
      await socket.close();
    }
  }

  void _handleSecondInstance(List<String> args) {
    _secondInstances.add(args);
    unawaited(_applyWindowAction());
    final onArgs = _configuration.onArgs;
    if (onArgs != null && args.isNotEmpty) {
      final result = onArgs(args);
      if (result is Future<void>) unawaited(result);
    }
  }

  Future<void> _applyWindowAction() async {
    final resident = _resident;
    if (resident == null) return;
    switch (_configuration.windowAction) {
      case SecondInstanceWindowAction.restore:
      case SecondInstanceWindowAction.focusOnly:
        await resident.restore();
      case SecondInstanceWindowAction.ignore:
        break;
    }
  }

  Future<void> _deliverArguments() async {
    final args = _argumentSource();
    final message = jsonEncode({
      'kind': 'args',
      'identity': _identity,
      'args': args,
    });
    for (final candidate in _candidatePorts()) {
      Socket? socket;
      try {
        socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          candidate,
          timeout: const Duration(milliseconds: 150),
        );
        socket.write('$message\n');
        await socket.flush();
        await socket.close();
        return;
      } on Object {
        socket?.destroy();
      }
    }
  }

  Future<bool> _isDartloomPrimary(int candidate) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        candidate,
        timeout: const Duration(milliseconds: 150),
      );
      socket.write('${jsonEncode({'kind': 'ping', 'identity': _identity})}\n');
      await socket.flush();
      final response = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(
            const Duration(milliseconds: 500),
          );
      return response == '{"ok":true}';
    } on Object {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  static int _portFor(String value) {
    var hash = 2166136261;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return 49152 + hash % 14000;
  }

  static List<String> _defaultArguments() =>
      List<String>.from(Platform.executableArguments);

  static Future<void> _defaultExit(int exitCode) => exit(exitCode);
}
