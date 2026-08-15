import 'dart:async';

/// Behavior for the existing (primary) window when a second instance launches.
///
/// This is dimension 1 of the two orthogonal second-instance behaviors: what
/// happens to the primary window. It is fully platform-generic and is
/// implemented by adapters (typically through the `resident` capability's
/// restore/focus primitives).
enum SecondInstanceWindowAction {
  /// Show and focus the existing window (un-minimize from tray/minimized).
  restore,

  /// Bring the window to the front without changing its minimized state.
  focusOnly,

  /// Leave the window untouched.
  ignore,
}

/// Configuration for how a second-instance launch is handled.
///
/// The two dimensions are orthogonal and compose:
///
/// - [windowAction] (dimension 1) decides what happens to the primary window.
/// - [onArgs] (dimension 2) decides what to do with the second instance's
///   command-line arguments (open a file, jump to a deep link, ...). Dartloom
///   only delivers the arguments; interpreting them is application-specific,
///   so it is left to the app-provided callback.
///
/// Both can be active at once: e.g. double-clicking an associated file while
/// the app is minimized should both restore the window (`windowAction`) and
/// open that file (`onArgs`).
final class SingleInstanceConfiguration {
  const SingleInstanceConfiguration({
    this.windowAction = SecondInstanceWindowAction.restore,
    this.onArgs,
  });

  /// What to do with the primary window when a second instance launches.
  final SecondInstanceWindowAction windowAction;

  /// Invoked on the primary with the second instance's command-line arguments
  /// whenever the second instance carried any. `null` (the default) ignores
  /// arguments.
  final FutureOr<void> Function(List<String> args)? onArgs;

  SingleInstanceConfiguration copyWith({
    SecondInstanceWindowAction? windowAction,
    FutureOr<void> Function(List<String> args)? onArgs,
    bool clearOnArgs = false,
  }) =>
      SingleInstanceConfiguration(
        windowAction: windowAction ?? this.windowAction,
        onArgs: clearOnArgs ? null : onArgs ?? this.onArgs,
      );
}

/// Optional teardown run by a duplicate instance immediately before it exits.
typedef SingleInstanceDuplicateExit = FutureOr<void> Function();

/// Platform-neutral single-instance capability contract.
///
/// Use [acquirePrimary] as the atomic component to claim the primary role, or
/// [ensureSingleInstance] for the full flow (claim, and if a duplicate, deliver
/// arguments, run teardown, and exit).
abstract interface class SingleInstanceService {
  /// Full single-instance flow.
  ///
  /// Atomically claims the primary role via [acquirePrimary]. If this process
  /// becomes primary, returns and the app continues. Otherwise it is a
  /// duplicate: the second instance's arguments are delivered to the primary
  /// (surfacing on [onSecondInstance]), [onDuplicateExit] (if provided) runs,
  /// and then this process exits.
  ///
  /// The actual exit routine is implementation-defined so that adapters and
  /// tests can replace `dart:io`'s `exit`.
  Future<void> ensureSingleInstance({
    SingleInstanceDuplicateExit? onDuplicateExit,
  });

  /// Atomically claim the primary role: acquire the lock, advertise the
  /// inter-process endpoint, and start listening — all in one step with no
  /// observable intermediate state.
  ///
  /// Returns `true` when this process became the primary, `false` when another
  /// primary already exists (the discovered endpoint to reach it is retained
  /// internally for subsequent [onSecondInstance] delivery). Does not touch
  /// arguments and never exits.
  Future<bool> acquirePrimary();

  /// Stream on the primary of each subsequent second-instance launch, carrying
  /// that launch's command-line arguments. The adapter applies [windowAction]
  /// and forwards to [SingleInstanceConfiguration.onArgs].
  Stream<List<String>> get onSecondInstance;

  /// Apply the second-instance behavior ([SingleInstanceConfiguration]).
  Future<void> configure(SingleInstanceConfiguration configuration);

  /// Release the primary role and tear down IPC state.
  Future<void> dispose();
}

/// In-memory test implementation.
///
/// It never performs real process locking or exiting. Use [exitHandler] to
/// observe when a duplicate would exit, and [emit] to simulate a second
/// instance firing `[onSecondInstance]`.
final class MemorySingleInstanceService implements SingleInstanceService {
  MemorySingleInstanceService({
    this.isPrimary = true,
    FutureOr<void> Function(int exitCode)? exitHandler,
  }) : exitHandler = exitHandler ?? _noopExit;

  /// Whether [acquirePrimary] reports this as the primary. Flip to `false` to
  /// simulate a duplicate.
  bool isPrimary;

  /// Records what a duplicate would do before exit. Defaults to doing nothing.
  final FutureOr<void> Function(int exitCode) exitHandler;

  SingleInstanceConfiguration _configuration =
      const SingleInstanceConfiguration();
  final StreamController<List<String>> _secondInstances =
      StreamController<List<String>>.broadcast();
  bool _disposed = false;

  SingleInstanceConfiguration get configuration => _configuration;
  bool get disposed => _disposed;

  @override
  Future<bool> acquirePrimary() async => isPrimary;

  @override
  Future<void> ensureSingleInstance({
    SingleInstanceDuplicateExit? onDuplicateExit,
  }) async {
    if (await acquirePrimary()) return;
    await onDuplicateExit?.call();
    await exitHandler(0);
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
  }

  /// Publish a simulated second-instance launch carrying [args], mirroring what
  /// a real adapter does: surface the launch on [onSecondInstance] and forward
  /// the arguments to the configured [SingleInstanceConfiguration.onArgs].
  void emit(List<String> args) {
    _secondInstances.add(args);
    final result = _configuration.onArgs?.call(args);
    if (result is Future<void>) unawaited(result);
  }

  static Future<void> _noopExit(int exitCode) async {}
}
