import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartloom_resident/dartloom_resident.dart';
import 'package:dartloom_singleton/dartloom_singleton.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// File-lock based single-instance adapter.
///
/// Owns a lock file in the application support directory. The first process to
/// acquire an OS-level exclusive lock on it becomes the primary, binds a
/// loopback `ServerSocket`, and records its endpoint (host:port) in a sidecar
/// file. Later processes (duplicates) fail to acquire the lock, read the
/// endpoint, connect, and deliver their command-line arguments to the primary
/// before exiting via [ensureSingleInstance].
///
/// The default window action is delegated to an optional [ResidentService]
/// (soft dependency). When no resident is available, [windowAction] degrades
/// to no-ops for `restore`/`focusOnly`, leaving argument delivery unaffected.
final class FileLockSingleInstanceService implements SingleInstanceService {
  FileLockSingleInstanceService({
    ResidentService? resident,
    String? lockFilePath,
    String? endpointFilePath,
    List<String> Function()? argumentSource,
    FutureOr<void> Function(int exitCode)? exitHandler,
  })  : _resident = resident,
        _defaultLockFilePath = lockFilePath,
        _defaultEndpointFilePath = endpointFilePath,
        _argumentSource = argumentSource ?? _defaultArguments,
        _exitHandler = exitHandler ?? _defaultExit;

  final ResidentService? _resident;
  final String? _defaultLockFilePath;
  final String? _defaultEndpointFilePath;
  final List<String> Function() _argumentSource;
  final FutureOr<void> Function(int exitCode) _exitHandler;

  SingleInstanceConfiguration _configuration =
      const SingleInstanceConfiguration();
  late final String _lockFilePath;
  late final String _endpointFilePath;
  RandomAccessFile? _lockHandle;
  File? _lockFile;
  ServerSocket? _server;
  bool _disposed = false;
  var _primary = false;
  final _secondInstances = StreamController<List<String>>.broadcast();

  /// Paths used by this process. Resolved lazily so tests can inject custom
  /// directories without touching the real application support location.
  String get lockFilePath => _lockFilePath;
  String get endpointFilePath => _endpointFilePath;

  /// Whether [acquirePrimary] claimed the primary role.
  bool get isPrimary => _primary;

  @override
  Future<void> ensureSingleInstance({
    SingleInstanceDuplicateExit? onDuplicateExit,
  }) async {
    final primary = await acquirePrimary();
    if (primary) return;
    await _deliverArguments();
    await onDuplicateExit?.call();
    await _exitHandler(0);
  }

  @override
  Future<bool> acquirePrimary() async {
    if (_disposed) return false;
    await _resolvePaths();
    final handle = await _tryAcquireLock();
    if (handle == null) return false;
    _lockHandle = handle;
    _primary = true;
    await _advertiseEndpoint();
    return true;
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
    if (_lockHandle != null) {
      try {
        await _lockHandle!.unlock();
      } on FileSystemException {
        // Already released.
      }
      await _lockHandle!.close();
    }
    await _lockFile?.delete();
    await File(_endpointFilePath).delete();
  }

  Future<void> _resolvePaths() async {
    if (_defaultLockFilePath != null && _defaultEndpointFilePath != null) {
      _lockFilePath = _defaultLockFilePath;
      _endpointFilePath = _defaultEndpointFilePath;
      return;
    }
    final dir = await getApplicationSupportDirectory().catchError((Object _) {
      // Fallback for environments without path_provider.
      return Directory(Directory.systemTemp.path);
    });
    final base = p.join(dir.path, 'dartloom.singleton');
    _lockFilePath = _defaultLockFilePath ?? '$base.lock';
    _endpointFilePath = _defaultEndpointFilePath ?? '$base.endpoint';
  }

  Future<RandomAccessFile?> _tryAcquireLock() async {
    _lockFile = File(_lockFilePath);
    try {
      final raf = _lockFile!.openSync(mode: FileMode.append);
      try {
        await raf.lock(FileLock.exclusive);
        return raf;
      } on FileSystemException {
        await raf.close();
        return null;
      }
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _advertiseEndpoint() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    final endpointFile = File(_endpointFilePath);
    await endpointFile
        .writeAsString('${server.address.address}:${server.port}');
    server.listen(_handleConnection, onError: (_) {});
  }

  Future<void> _handleConnection(Socket socket) async {
    try {
      final payload = await utf8.decoder.bind(socket).join();
      socket.destroy();
      if (payload.isEmpty) return;
      final Object? decoded;
      try {
        decoded = jsonDecode(payload);
      } on FormatException {
        return;
      }
      if (decoded is! List) return;
      final args = decoded.map((e) => e.toString()).toList();
      _handleSecondInstance(args);
    } catch (_) {
      socket.destroy();
    }
  }

  void _handleSecondInstance(List<String> args) {
    _secondInstances.add(args);
    _applyWindowAction();
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
        await resident.restore();
      case SecondInstanceWindowAction.focusOnly:
        await _focusOnly(resident);
      case SecondInstanceWindowAction.ignore:
        break;
    }
  }

  Future<void> _focusOnly(ResidentService resident) async {
    // ResidentService exposes restore (show+focus). For a focus-only intent we
    // re-show is not what the caller wants, so with the current contract the
    // least surprising behavior is a no-op. Adapters can refine this when the
    // resident contract gains a dedicated focus primitive.
    await resident.restore();
  }

  Future<void> _deliverArguments() async {
    final List<String> args;
    try {
      args = _argumentSource();
    } catch (_) {
      return; // No usable argument source; delivery is best-effort.
    }
    var deadline = DateTime.now().add(const Duration(milliseconds: 500));
    while (true) {
      Socket? socket;
      try {
        final endpointText = await File(_endpointFilePath).readAsString();
        final sep = endpointText.lastIndexOf(':');
        final host = endpointText.substring(0, sep);
        final port = int.parse(endpointText.substring(sep + 1));
        socket = await Socket.connect(host, port);
        socket.add(utf8.encode(jsonEncode(args)));
        await socket.flush();
      } on Object {
        socket?.destroy();
        if (DateTime.now().isAfter(deadline)) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        continue;
      }
      socket.destroy();
      return;
    }
  }

  static List<String> _defaultArguments() =>
      List<String>.from(Platform.executableArguments);

  static Future<void> _defaultExit(int exitCode) => exit(exitCode);
}
