import 'dart:io';

import 'package:dart_console/dart_console.dart';

import '../capabilities/capability_registry.dart';
import '../config/config_loader.dart';
import '../config/dartloom_config.dart';
import '../process/process_runner.dart';
import 'capability_manager.dart';

enum CapTuiIntent { none, up, down, activate, enter, cancel }

CapTuiIntent capTuiIntent(Key key) {
  if (key.controlChar == ControlCharacter.arrowUp) return CapTuiIntent.up;
  if (key.controlChar == ControlCharacter.arrowDown) return CapTuiIntent.down;
  if (key.controlChar == ControlCharacter.enter) return CapTuiIntent.enter;
  if (key.controlChar == ControlCharacter.escape ||
      key.controlChar == ControlCharacter.ctrlC ||
      (!key.isControl && key.char.toLowerCase() == 'q')) {
    return CapTuiIntent.cancel;
  }
  if (!key.isControl && key.char == ' ') return CapTuiIntent.activate;
  return CapTuiIntent.none;
}

int moveCapTuiCursor(int cursor, int rows, CapTuiIntent intent) =>
    switch (intent) {
      CapTuiIntent.up => (cursor - 1 + rows) % rows,
      CapTuiIntent.down => (cursor + 1) % rows,
      _ => cursor,
    };

class CapTui {
  CapTui(this.runner, {ConfigLoader? loader, Console? console})
      : _loader = loader ?? const ConfigLoader(),
        _manager = CapabilityManager(runner, loader: loader),
        _console = console ?? Console();

  final ProcessRunner runner;
  final ConfigLoader _loader;
  final CapabilityManager _manager;
  final Console _console;

  Future<void> run(Directory project) async {
    if (!_console.hasTerminal) {
      throw StateError(
        'dartloom cap requires an interactive terminal. Use cap add, list, or remove instead.',
      );
    }
    final config = await _loader.load(project);
    final selection = {
      for (final entry in config.capabilities.entries)
        entry.key: {...entry.value},
    };
    var cursor = 0;
    try {
      _console.hideCursor();
      while (true) {
        _renderMain(config, selection, cursor);
        final key = _console.readKey();
        cursor = moveCapTuiCursor(cursor, _mainRows, capTuiIntent(key));
        if (_isCancel(key)) {
          stdout.writeln('\nCancelled. No capability changes were made.');
          return;
        }
        if (_isEnter(key) && cursor < Capability.values.length) {
          final capability = Capability.values[cursor];
          if (selection.containsKey(capability)) {
            await _editCapability(capability, selection[capability]!);
          }
          continue;
        }
        if (!_isActivate(key)) continue;
        if (cursor < Capability.values.length) {
          final capability = Capability.values[cursor];
          if (selection.containsKey(capability)) {
            if (capability == Capability.storage &&
                selection.containsKey(Capability.sync)) {
              _message('storage is referenced by sync; remove sync first.');
            } else {
              selection.remove(capability);
            }
          } else {
            selection[capability] = {
              ...CapabilityDefaults.forCapability(capability),
            };
            if (capability == Capability.sync) {
              selection.putIfAbsent(
                Capability.storage,
                () => {...CapabilityDefaults.forCapability(Capability.storage)},
              );
            }
          }
        } else if (cursor == Capability.values.length) {
          final change = await _manager.apply(project, selection);
          stdout
            ..writeln('\nCapability changes applied:')
            ..writeln('  Added:   ${_names(change.added)}')
            ..writeln('  Removed: ${_names(change.removed)}')
            ..writeln('  Changed: ${_names(change.changed)}');
          return;
        } else {
          stdout.writeln('\nCancelled. No capability changes were made.');
          return;
        }
      }
    } finally {
      try {
        _console.rawMode = false;
        _console.showCursor();
      } on Object {
        // The host may have replaced the Windows console handle after input.
      }
    }
  }

  Future<void> _editCapability(
    Capability capability,
    Map<String, CapabilityInstanceConfig> instances,
  ) async {
    final availableNames = capability == Capability.storage
        ? const ['text', 'json', 'database']
        : <String>{...instances.keys, 'default'}.toList();
    var cursor = 0;
    while (true) {
      _console
        ..clearScreen()
        ..resetCursorPosition()
        ..writeLine('Configure ${capability.name}')
        ..writeLine(
            '↑/↓ move   Space enable/disable   Enter edit   a add   d delete   Esc back')
        ..writeLine();
      for (var index = 0; index < availableNames.length; index++) {
        final name = availableNames[index];
        final instance = instances[name];
        _console.writeLine(
          '${cursor == index ? '›' : ' '} [${instance == null ? ' ' : 'x'}] '
          '${name.padRight(12)} ${instance?.implementation ?? ''}',
        );
      }
      final key = _console.readKey();
      if (_isCancel(key)) {
        return;
      }
      cursor = moveCapTuiCursor(
        cursor,
        availableNames.length,
        capTuiIntent(key),
      );
      final name = availableNames[cursor];
      if (_isActivate(key) && !_isEnter(key)) {
        if (instances.containsKey(name)) {
          instances.remove(name);
        } else {
          instances[name] = _defaultInstance(capability, name);
        }
      } else if (_isEnter(key)) {
        final current = instances[name] ?? _defaultInstance(capability, name);
        instances[name] = await _editInstance(capability, name, current);
      } else if (!key.isControl && key.char.toLowerCase() == 'd') {
        instances.remove(name);
      } else if (!key.isControl &&
          key.char.toLowerCase() == 'a' &&
          capability != Capability.storage) {
        final added = _prompt('Instance name', 'default');
        if (RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(added) &&
            !availableNames.contains(added)) {
          availableNames.add(added);
          instances[added] = _defaultInstance(capability, added);
        }
      }
    }
  }

  Future<CapabilityInstanceConfig> _editInstance(
    Capability capability,
    String name,
    CapabilityInstanceConfig current,
  ) async {
    final choices = CapabilityRegistry.all[capability]!.implementations
        .where((item) => item.instanceNames?.contains(name) ?? true)
        .toList();
    _console
      ..rawMode = false
      ..clearScreen()
      ..resetCursorPosition()
      ..writeLine('Implementations for ${capability.name}.$name');
    for (var index = 0; index < choices.length; index++) {
      _console.writeLine('  ${index + 1}. ${choices[index].id}');
    }
    _console.writeLine('  c. custom factory');
    final selected = _prompt('Select', current.implementation);
    String implementation;
    String? factory;
    ImplementationMetadata? metadata;
    final index = int.tryParse(selected);
    if (selected.toLowerCase() == 'c') {
      implementation = 'custom';
      factory =
          _prompt('Factory ID', current.factory ?? 'app_${capability.name}');
    } else if (index != null && index > 0 && index <= choices.length) {
      metadata = choices[index - 1];
      implementation = metadata.id;
    } else {
      implementation = current.implementation;
      factory = current.factory;
      metadata = CapabilityRegistry.implementation(capability, implementation);
    }
    final options = <String, Object?>{...current.options};
    for (final option
        in metadata?.options.entries ?? const <MapEntry<String, String>>[]) {
      options[option.key] = _prompt(
        option.key,
        options[option.key]?.toString() ?? option.value,
      );
    }
    if (implementation == 'custom') {
      final rawOptions = _prompt(
        'Options (comma separated key=value)',
        options.entries.map((entry) => '${entry.key}=${entry.value}').join(','),
      );
      options.clear();
      for (final item in rawOptions.split(',')) {
        final separator = item.indexOf('=');
        if (separator > 0) {
          options[item.substring(0, separator).trim()] =
              item.substring(separator + 1).trim();
        }
      }
    }
    final rawDependencies = _prompt(
      'Dependencies (comma separated capability.instance)',
      current.dependsOn.join(','),
    );
    final dependsOn = rawDependencies
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    var stores = current.stores;
    AdapterConfig? backend = current.backend;
    String? mergeFactory = current.mergeFactory;
    if (capability == Capability.sync) {
      final rawStores = _prompt(
        'Stores (comma separated: storage.text/storage.json/storage.database)',
        stores.isEmpty ? 'storage.json' : stores.join(','),
      );
      stores = rawStores
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      final backendOptions = <String, Object?>{
        ...?backend?.options,
      };
      for (final option in CapabilityRegistry.webDav.options.entries) {
        backendOptions[option.key] = _prompt(
          'webdav.${option.key}',
          backendOptions[option.key]?.toString() ?? option.value,
        );
      }
      backend = AdapterConfig(
        implementation: 'webdav',
        options: backendOptions,
      );
      final rawMerge = _prompt(
        'Merge factory (blank keeps conflicts)',
        mergeFactory ?? '',
      );
      mergeFactory = rawMerge.isEmpty ? null : rawMerge;
    }
    return CapabilityInstanceConfig(
      implementation: implementation,
      factory: factory,
      options: options,
      dependsOn: dependsOn,
      stores: stores,
      backend: backend,
      mergeFactory: mergeFactory,
    );
  }

  CapabilityInstanceConfig _defaultInstance(
      Capability capability, String name) {
    final defaults = CapabilityDefaults.forCapability(capability);
    if (defaults[name] case final value?) return value;
    return defaults.values.first;
  }

  String _prompt(String label, String defaultValue) {
    _console.rawMode = false;
    _console.write('$label [$defaultValue]: ');
    final value = stdin.readLineSync()?.trim() ?? '';
    return value.isEmpty ? defaultValue : value;
  }

  void _renderMain(
    DartloomConfig config,
    Map<Capability, Map<String, CapabilityInstanceConfig>> selection,
    int cursor,
  ) {
    _console
      ..clearScreen()
      ..resetCursorPosition()
      ..writeLine('Dartloom Capability Manager')
      ..writeLine(
          'Project: ${config.app.name}   Source: ${config.capabilitySource.name}')
      ..writeLine(
          '↑/↓ move   Space toggle/select   Enter configure   q/Esc cancel')
      ..writeLine();
    for (var index = 0; index < Capability.values.length; index++) {
      final capability = Capability.values[index];
      final instances = selection[capability] ?? const {};
      final implementations =
          instances.values.map((item) => item.implementation).join(', ');
      _console.writeLine(
        '${cursor == index ? '›' : ' '} [${instances.isEmpty ? ' ' : 'x'}] '
        '${capability.name.padRight(12)} $implementations',
      );
    }
    _row('Save and apply changes', Capability.values.length, cursor);
    _row('Cancel', Capability.values.length + 1, cursor);
  }

  void _row(String value, int index, int cursor) =>
      _console.writeLine('${cursor == index ? '›' : ' '} $value');
  void _message(String value) {
    _console
      ..rawMode = false
      ..writeLine(value)
      ..writeLine('Press Enter to continue.');
    stdin.readLineSync();
  }

  bool _isEnter(Key key) => capTuiIntent(key) == CapTuiIntent.enter;
  bool _isActivate(Key key) =>
      {CapTuiIntent.enter, CapTuiIntent.activate}.contains(capTuiIntent(key));
  bool _isCancel(Key key) => capTuiIntent(key) == CapTuiIntent.cancel;
  int get _mainRows => Capability.values.length + 2;
  String _names(Set<String> values) =>
      values.isEmpty ? 'none' : values.join(', ');
}
