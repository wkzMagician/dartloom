import 'dart:async';
import 'dart:io';

import '../capabilities/capability_registry.dart';
import '../config/config_loader.dart';
import '../config/dartloom_config.dart';
import '../process/process_runner.dart';
import 'capability_manager.dart';

/// Keyboard-driven terminal UI for selecting capabilities as one batch.
class CapTui {
  CapTui(this.runner, {ConfigLoader? loader})
      : _loader = loader ?? const ConfigLoader(),
        _manager = CapabilityManager(runner, loader: loader);

  final ProcessRunner runner;
  final ConfigLoader _loader;
  final CapabilityManager _manager;

  Future<void> run(Directory project) async {
    if (!stdin.hasTerminal || !stdout.hasTerminal) {
      throw StateError(
          'dartloom cap requires an interactive terminal. Use cap add, list, or remove instead.');
    }
    final config = await _loader.load(project);
    final selection = {...config.capabilities};
    final result = await _select(config, selection);
    if (!result.save) {
      stdout.writeln('\nCancelled. No capability changes were made.');
      return;
    }

    final change = await _manager.apply(project, result.selection);
    stdout.writeln('\nCapability changes applied:');
    stdout.writeln('  Added:   ${_names(change.added)}');
    stdout.writeln('  Removed: ${_names(change.removed)}');
  }

  Future<_SelectionResult> _select(
    DartloomConfig config,
    Set<Capability> selection,
  ) async {
    final oldEcho = stdin.echoMode;
    final oldLineMode = stdin.lineMode;
    var echoChanged = false;
    var lineModeChanged = false;
    var cursor = 0;
    var escapeState = 0;
    var windowsPrefix = false;
    final completion = Completer<_SelectionResult>();

    try {
      stdin.echoMode = false;
      echoChanged = true;
      stdin.lineMode = false;
      lineModeChanged = true;
      stdout.write('\x1B[?25l');
      _render(config, selection, cursor);
      final subscription = stdin.listen((bytes) {
        for (final byte in bytes) {
          if (completion.isCompleted) return;
          final action = _handleByte(byte, escapeState, windowsPrefix);
          escapeState = action.escapeState;
          windowsPrefix = action.windowsPrefix;
          if (action.move != 0) {
            cursor = (cursor + action.move) % _rowCount;
            if (cursor < 0) cursor += _rowCount;
            _render(config, selection, cursor);
            continue;
          }
          if (action.cancel) {
            completion.complete(_SelectionResult.cancel());
            return;
          }
          if (!action.activate) continue;
          if (cursor < Capability.values.length) {
            final capability = Capability.values[cursor];
            if (selection.contains(capability)) {
              selection.remove(capability);
            } else {
              selection.add(capability);
            }
            _render(config, selection, cursor);
          } else if (cursor == Capability.values.length) {
            completion.complete(_SelectionResult.save(selection));
          } else {
            completion.complete(_SelectionResult.cancel());
          }
        }
      });
      final result = await completion.future;
      await subscription.cancel();
      return result;
    } finally {
      _restoreTerminalMode(
        oldEcho: oldEcho,
        oldLineMode: oldLineMode,
        echoChanged: echoChanged,
        lineModeChanged: lineModeChanged,
      );
      stdout.write('\x1B[?25h\n');
    }
  }

  /// Some Windows terminals close their input handle before Dart's final mode
  /// restore. The selection has already completed, so restoration must not turn
  /// a successful save or cancel into an error.
  void _restoreTerminalMode({
    required bool oldEcho,
    required bool oldLineMode,
    required bool echoChanged,
    required bool lineModeChanged,
  }) {
    if (lineModeChanged) {
      try {
        stdin.lineMode = oldLineMode;
      } on StdinException {
        // The host owns a closed or replaced input handle now.
      }
    }
    if (echoChanged) {
      try {
        stdin.echoMode = oldEcho;
      } on StdinException {
        // See the comment above; no action is possible for an invalid handle.
      }
    }
  }

  _KeyAction _handleByte(int byte, int escapeState, bool windowsPrefix) {
    if (windowsPrefix) {
      return switch (byte) {
        72 => const _KeyAction(move: -1),
        80 => const _KeyAction(move: 1),
        _ => const _KeyAction(),
      };
    }
    if (escapeState == 1) {
      if (byte == 91) return const _KeyAction(escapeState: 2);
      return const _KeyAction(cancel: true);
    }
    if (escapeState == 2) {
      return switch (byte) {
        65 => const _KeyAction(move: -1),
        66 => const _KeyAction(move: 1),
        _ => const _KeyAction(),
      };
    }
    return switch (byte) {
      27 => const _KeyAction(escapeState: 1),
      // Windows console hosts use either 0 or 224 before the scan code.
      0 || 224 => const _KeyAction(windowsPrefix: true),
      72 => const _KeyAction(move: -1),
      80 => const _KeyAction(move: 1),
      32 || 13 || 10 => const _KeyAction(activate: true),
      113 || 81 => const _KeyAction(cancel: true),
      _ => const _KeyAction(),
    };
  }

  void _render(DartloomConfig config, Set<Capability> selection, int cursor) {
    stdout.write('\x1B[2J\x1B[H');
    stdout.writeln('Dartloom Capability Manager');
    stdout.writeln('Project: ${config.app.name}');
    stdout.writeln('Source: ${config.capabilitySource.name}');
    stdout.writeln('↑/↓ move   Space toggle/select   q or Esc cancel\n');
    for (var index = 0; index < Capability.values.length; index++) {
      final capability = Capability.values[index];
      final selected = selection.contains(capability) ? 'x' : ' ';
      final prefix = cursor == index ? '›' : ' ';
      final platforms = CapabilityRegistry.all[capability]!.platforms
          .map((item) => item.name)
          .join(', ');
      stdout.writeln(
          '$prefix [$selected] ${capability.name.padRight(12)} $platforms');
    }
    _menuRow('保存并应用变更', Capability.values.length, cursor);
    _menuRow('取消', Capability.values.length + 1, cursor);
  }

  void _menuRow(String label, int index, int cursor) {
    final prefix = cursor == index ? '›' : ' ';
    stdout.writeln('$prefix $label');
  }

  int get _rowCount => Capability.values.length + 2;

  String _names(Set<Capability> capabilities) => capabilities.isEmpty
      ? 'none'
      : capabilities.map((item) => item.name).join(', ');
}

class _SelectionResult {
  const _SelectionResult._({required this.save, required this.selection});
  factory _SelectionResult.save(Set<Capability> selection) =>
      _SelectionResult._(save: true, selection: {...selection});
  factory _SelectionResult.cancel() =>
      const _SelectionResult._(save: false, selection: {});

  final bool save;
  final Set<Capability> selection;
}

class _KeyAction {
  const _KeyAction({
    this.move = 0,
    this.activate = false,
    this.cancel = false,
    this.escapeState = 0,
    this.windowsPrefix = false,
  });

  final int move;
  final bool activate;
  final bool cancel;
  final int escapeState;
  final bool windowsPrefix;
}
