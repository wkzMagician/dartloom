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
    ResidentService? Function()? residentProvider,
    int? port,
    String? identity,
    List<String> Function()? argumentSource,
    FutureOr<void> Function(int exitCode)? exitHandler,
  })  : _resident = resident,
        _residentProvider = residentProvider,
        _configuredPort = port,
        _configuredIdentity = identity,
        _argumentSource = argumentSource ?? _defaultArguments,
        _exitHandler = exitHandler ?? _defaultExit;

  ResidentService? _resident;
  final ResidentService? Function()? _residentProvider;
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

    final candidate = _candidatePort();
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
      // Never move to a fallback port: that would allow two instances to
      // become primary. Give the first process a short window to bind.
      if (await _waitForPrimary(candidate)) {
        _port = candidate;
      }
      return false;
    }
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

  int _candidatePort() {
    final configured = _configuredPort;
    if (configured != null) return configured;
    final base = _portFor(_identity!);
    return base;
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
      await _handleSecondInstance(args);
      socket.write('{"ok":true}');
      await socket.flush();
    } catch (_) {
      // Invalid or unrelated local traffic is ignored.
    } finally {
      await socket.close();
    }
  }

  Future<void> _handleSecondInstance(List<String> args) async {
    _secondInstances.add(args);
    await _applyWindowAction();
    final onArgs = _configuration.onArgs;
    if (onArgs != null && args.isNotEmpty) {
      await onArgs(args);
    }
  }

  Future<void> _applyWindowAction() async {
    final resident = _resident ??= _residentProvider?.call();
    if (resident == null) return;
    switch (_configuration.windowAction) {
      case SecondInstanceWindowAction.restore:
      case SecondInstanceWindowAction.focusOnly:
        await resident.restore().timeout(const Duration(seconds: 2));
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
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _candidatePort(),
        timeout: const Duration(milliseconds: 250),
      );
      socket.write('$message\n');
      await socket.flush();
      await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 2));
    } on Object {
      // The process remains a duplicate and must not claim a fallback port.
    } finally {
      socket?.destroy();
    }
  }

  Future<bool> _waitForPrimary(int candidate) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      if (await _isDartloomPrimary(candidate)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return false;
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
