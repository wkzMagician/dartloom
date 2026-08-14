import 'dart:io';

import 'package:dart_console/dart_console.dart';

import '../capabilities/capability_registry.dart';
import '../config/config_loader.dart';
import '../config/dartloom_config.dart';
import '../config/option_schema.dart';
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
  Set<TargetPlatform> _appPlatforms = const {};

  Future<void> run(Directory project) async {
    if (!_console.hasTerminal) {
      throw StateError(
        'dartloom cap requires an interactive terminal. Use cap add, list, or remove instead.',
      );
    }
    final config = await _loader.load(project);
    _appPlatforms = config.platforms;
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
              ...CapabilityDefaults.forCapability(
                capability,
                platforms: _appPlatforms,
              ),
            };
            if (capability == Capability.sync) {
              selection.putIfAbsent(
                Capability.settings,
                () =>
                    {...CapabilityDefaults.forCapability(Capability.settings)},
              );
              selection[Capability.settings]!.putIfAbsent(
                'sync_secrets',
                () => const CapabilityInstanceConfig(
                    implementation: 'secure_storage'),
              );
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
    final adapterOptionSchema = metadata?.optionSchema;
    if (capability != Capability.sync && adapterOptionSchema != null) {
      _editOptionSchema(options, adapterOptionSchema, title: 'Adapter options');
    } else if (capability != Capability.sync) {
      for (final option
          in metadata?.options.entries ?? const <MapEntry<String, String>>[]) {
        options[option.key] = _prompt(
            option.key, options[option.key]?.toString() ?? option.value);
      }
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
    var replica = current.replica;
    AdapterConfig? backend = current.backend;
    String? mergeFactory = current.mergeFactory;
    var policy = _deepCopy(current.policy);
    if (capability == Capability.sync) {
      replica = _prompt(
        'Replica (one directory-backed storage capability)',
        replica ?? 'storage.json',
      ).trim();
      _console.writeLine('\nSync backends');
      for (var index = 0;
          index < CapabilityRegistry.syncBackends.length;
          index++) {
        _console.writeLine(
            '  ${index + 1}. ${CapabilityRegistry.syncBackends[index].id}');
      }
      final selectedBackend = _prompt(
        'Select backend',
        backend?.implementation ?? CapabilityRegistry.syncBackends.first.id,
      );
      final backendIndex = int.tryParse(selectedBackend);
      final backendMetadata = backendIndex != null &&
              backendIndex > 0 &&
              backendIndex <= CapabilityRegistry.syncBackends.length
          ? CapabilityRegistry.syncBackends[backendIndex - 1]
          : CapabilityRegistry.syncBackend(selectedBackend) ??
              CapabilityRegistry.syncBackend(backend?.implementation ?? '') ??
              CapabilityRegistry.syncBackends.first;
      final backendOptions = <String, Object?>{
        ...?backendMetadata.optionSchema?.defaults(),
        ...?backend?.options,
      };
      if (backendMetadata.optionSchema case final schema?) {
        _editOptionSchema(
          backendOptions,
          schema,
          title: '${backendMetadata.id} backend options',
        );
      }
      backend = AdapterConfig(
        implementation: backendMetadata.id,
        options: backendOptions,
      );
      final rawMerge = _prompt(
        'Merge factory (blank keeps conflicts)',
        mergeFactory ?? '',
      );
      mergeFactory = rawMerge.isEmpty ? null : rawMerge;
      policy = deepMerge(SyncOptionSchemas.policy.defaults(), policy);
      _console.writeLine('\nBasic sync policy');
      _editOptionSchema(
        policy,
        OptionSchema(SyncOptionSchemas.policy.fields
            .where((field) =>
                field.group == 'basic' || field.path == 'conflicts.strategy')
            .toList()),
        title: 'Basic',
      );
      if (_prompt('Configure advanced policy? (y/n)', 'n').toLowerCase() ==
          'y') {
        _editOptionSchema(
          policy,
          OptionSchema(SyncOptionSchemas.policy.fields
              .where((field) =>
                  field.group != 'basic' && field.path != 'conflicts.strategy')
              .toList()),
          title: 'Advanced',
        );
      }
      final platformPolicies = policy['platforms'] is Map
          ? (policy['platforms'] as Map).cast<String, Object?>()
          : <String, Object?>{};
      if (_prompt('Configure platform overrides? (y/n)', 'n').toLowerCase() ==
          'y') {
        for (final platform
            in TargetPlatform.values.where(_appPlatforms.contains)) {
          final currentOverride = platformPolicies[platform.name] is Map
              ? (platformPolicies[platform.name] as Map).cast<String, Object?>()
              : <String, Object?>{};
          if (_prompt('Override ${platform.name}? (y/n/reset)',
                      currentOverride.isEmpty ? 'n' : 'y')
                  .toLowerCase() ==
              'reset') {
            platformPolicies.remove(platform.name);
            continue;
          }
          if (_prompt('Edit ${platform.name} values? (y/n)',
                      currentOverride.isEmpty ? 'n' : 'y')
                  .toLowerCase() !=
              'y') {
            continue;
          }
          _editOptionSchema(currentOverride, SyncOptionSchemas.policy,
              title: '${platform.name} foreground overrides',
              includeMissing: false);
          if ({TargetPlatform.android, TargetPlatform.ios}.contains(platform) &&
              _prompt('Configure ${platform.name} background? (y/n)', 'n')
                      .toLowerCase() ==
                  'y') {
            final background = currentOverride['background'] is Map
                ? (currentOverride['background'] as Map).cast<String, Object?>()
                : <String, Object?>{};
            _editOptionSchema(
              background,
              OptionSchema(SyncOptionSchemas.background.fields
                  .where((field) => field.platforms?.contains(platform) ?? true)
                  .toList()),
              title: '${platform.name} background',
            );
            currentOverride['background'] = background;
          }
          platformPolicies[platform.name] = currentOverride;
        }
        policy['platforms'] = platformPolicies;
        _console.writeLine('Resolved platform policies:');
        for (final platform
            in TargetPlatform.values.where(_appPlatforms.contains)) {
          final override = platformPolicies[platform.name] is Map
              ? (platformPolicies[platform.name] as Map).cast<String, Object?>()
              : const <String, Object?>{};
          _console.writeLine(
              '  ${platform.name}: ${deepMerge(Map.fromEntries(policy.entries.where((entry) => entry.key != 'platforms')), override)}');
        }
      }
    }
    return CapabilityInstanceConfig(
      implementation: implementation,
      factory: factory,
      platforms: current.platforms,
      options: options,
      dependsOn: dependsOn,
      replica: replica,
      backend: backend,
      mergeFactory: mergeFactory,
      policy: policy,
    );
  }

  void _editOptionSchema(
    Map<String, Object?> values,
    OptionSchema schema, {
    required String title,
    bool includeMissing = true,
  }) {
    _console.writeLine('\n$title');
    String? group;
    for (final field in schema.fields) {
      final condition = field.condition;
      if (condition != null) {
        final controllingValue = readPath(values, condition.path);
        if (controllingValue != null &&
            !condition.values.contains(controllingValue)) {
          continue;
        }
      }
      final current = readPath(values, field.path);
      if (!includeMissing && current == null) {
        final enabled = _prompt('Override ${field.path}? (y/n)', 'n');
        if (enabled.toLowerCase() != 'y') continue;
      }
      if (group != field.group) {
        group = field.group;
        _console.writeLine('[$group]');
      }
      final defaultValue = current ?? field.defaultValue;
      final raw = _prompt(
          '${field.label} — ${field.description}', _formatOption(defaultValue));
      setPath(values, field.path, _parseOption(field, raw));
    }
  }

  Object? _parseOption(OptionField field, String raw) => switch (field.type) {
        OptionValueType.boolean => raw.toLowerCase() == 'true',
        OptionValueType.integer => int.tryParse(raw) ?? raw,
        OptionValueType.number => num.tryParse(raw) ?? raw,
        OptionValueType.stringList => raw
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(),
        _ => raw,
      };

  String _formatOption(Object? value) =>
      value is List ? value.join(',') : '$value';

  Map<String, Object?> _deepCopy(Map<String, Object?> value) => {
        for (final entry in value.entries)
          entry.key: entry.value is Map
              ? _deepCopy((entry.value as Map).cast<String, Object?>())
              : entry.value is List
                  ? List<Object?>.from(entry.value as List)
                  : entry.value,
      };

  CapabilityInstanceConfig _defaultInstance(
      Capability capability, String name) {
    final defaults = CapabilityDefaults.forCapability(
      capability,
      platforms: _appPlatforms,
    );
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
