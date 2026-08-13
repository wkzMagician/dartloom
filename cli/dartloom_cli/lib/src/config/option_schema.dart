import 'dartloom_config.dart';

enum OptionValueType {
  boolean,
  integer,
  number,
  duration,
  percentage,
  enumeration,
  string,
  stringList,
  map
}

final class OptionCondition {
  const OptionCondition(this.path, this.values);
  final String path;
  final Set<Object?> values;
}

final class OptionField {
  const OptionField({
    required this.path,
    required this.label,
    required this.description,
    required this.type,
    required this.defaultValue,
    this.values = const {},
    this.minimum,
    this.maximum,
    this.condition,
    this.platforms,
    this.platformOverride = true,
    this.restartRequired = false,
    this.sensitive = false,
    this.requiredBackendCapabilities = const {},
    this.group = 'general',
  });

  final String path;
  final String label;
  final String description;
  final OptionValueType type;
  final Object? defaultValue;
  final Set<Object?> values;
  final num? minimum;
  final num? maximum;
  final OptionCondition? condition;
  final Set<TargetPlatform>? platforms;
  final bool platformOverride;
  final bool restartRequired;
  final bool sensitive;
  final Set<String> requiredBackendCapabilities;
  final String group;
}

final class OptionSchema {
  const OptionSchema(this.fields);
  final List<OptionField> fields;

  Map<String, Object?> defaults() {
    final result = <String, Object?>{};
    for (final field in fields) {
      setPath(result, field.path, field.defaultValue);
    }
    return result;
  }

  List<String> validate(Map<String, Object?> values,
      {String context = 'options'}) {
    final errors = <String>[];
    final known = fields.map((field) => field.path).toSet();
    for (final path in leafPaths(values)) {
      if (!known.contains(path)) errors.add('$context.$path is unknown.');
    }
    for (final field in fields) {
      final value = readPath(values, field.path);
      if (value == null) continue;
      if (field.sensitive) {
        errors.add(
            '$context.${field.path} is sensitive and cannot be stored in YAML.');
        continue;
      }
      final error = _validateField(field, value);
      if (error != null) errors.add('$context.${field.path} $error');
    }
    return errors;
  }

  String? _validateField(OptionField field, Object value) {
    final validType = switch (field.type) {
      OptionValueType.boolean => value is bool,
      OptionValueType.integer => value is int,
      OptionValueType.number => value is num,
      OptionValueType.duration =>
        value is String && tryParseDuration(value) != null,
      OptionValueType.percentage =>
        value is String && tryParsePercentage(value) != null,
      OptionValueType.enumeration => field.values.contains(value),
      OptionValueType.string => value is String,
      OptionValueType.stringList =>
        value is List && value.every((item) => item is String),
      OptionValueType.map => value is Map,
    };
    if (!validType) return 'has invalid ${field.type.name} value $value.';
    num? comparable;
    if (value is num) comparable = value;
    if (field.type == OptionValueType.duration && value is String) {
      comparable = tryParseDuration(value)?.inMilliseconds;
    }
    if (field.type == OptionValueType.percentage && value is String) {
      comparable = tryParsePercentage(value);
    }
    if (comparable != null &&
        field.minimum != null &&
        comparable < field.minimum!) {
      return 'must be at least ${field.minimum}.';
    }
    if (comparable != null &&
        field.maximum != null &&
        comparable > field.maximum!) {
      return 'must be at most ${field.maximum}.';
    }
    return null;
  }
}

Duration? tryParseDuration(String input) {
  final match = RegExp(r'^(\d+(?:\.\d+)?)(ms|s|m|h|d)$')
      .firstMatch(input.trim().toLowerCase());
  if (match == null) return null;
  final value = double.parse(match.group(1)!);
  final micros = switch (match.group(2)) {
    'ms' => value * Duration.microsecondsPerMillisecond,
    's' => value * Duration.microsecondsPerSecond,
    'm' => value * Duration.microsecondsPerMinute,
    'h' => value * Duration.microsecondsPerHour,
    'd' => value * Duration.microsecondsPerDay,
    _ => 0,
  };
  return Duration(microseconds: micros.round());
}

double? tryParsePercentage(String input) {
  final match = RegExp(r'^(\d+(?:\.\d+)?)%$').firstMatch(input.trim());
  if (match == null) return null;
  return double.parse(match.group(1)!) / 100;
}

Object? readPath(Map<String, Object?> map, String path) {
  Object? current = map;
  for (final segment in path.split('.')) {
    if (current is! Map) return null;
    current = current[segment];
  }
  return current;
}

void setPath(Map<String, Object?> map, String path, Object? value) {
  final parts = path.split('.');
  var current = map;
  for (final part in parts.take(parts.length - 1)) {
    final next = current[part];
    if (next is Map<String, Object?>) {
      current = next;
    } else if (next is Map) {
      current = next.cast<String, Object?>();
    } else {
      final created = <String, Object?>{};
      current[part] = created;
      current = created;
    }
  }
  current[parts.last] = value;
}

Set<String> leafPaths(Map<String, Object?> values, [String prefix = '']) {
  final result = <String>{};
  for (final entry in values.entries) {
    final path = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
    if (entry.value is Map) {
      result.addAll(
          leafPaths((entry.value as Map).cast<String, Object?>(), path));
    } else {
      result.add(path);
    }
  }
  return result;
}

Map<String, Object?> deepMerge(
    Map<String, Object?> base, Map<String, Object?> override) {
  final result = <String, Object?>{...base};
  for (final entry in override.entries) {
    final existing = result[entry.key];
    if (existing is Map && entry.value is Map) {
      result[entry.key] = deepMerge(existing.cast<String, Object?>(),
          (entry.value as Map).cast<String, Object?>());
    } else {
      result[entry.key] = entry.value;
    }
  }
  return result;
}

abstract final class SyncOptionSchemas {
  static const policy = OptionSchema([
    OptionField(
        path: 'mode',
        label: 'Mode',
        description: 'Manual or automatic synchronization.',
        type: OptionValueType.enumeration,
        defaultValue: 'automatic',
        values: {'manual', 'automatic'},
        group: 'basic'),
    OptionField(
        path: 'triggers.startup',
        label: 'Sync on startup',
        description: 'Run after application startup.',
        type: OptionValueType.boolean,
        defaultValue: true,
        condition: OptionCondition('mode', {'automatic'}),
        group: 'triggers'),
    OptionField(
        path: 'triggers.resume',
        label: 'Sync on resume',
        description: 'Run when the application returns to foreground.',
        type: OptionValueType.boolean,
        defaultValue: true,
        condition: OptionCondition('mode', {'automatic'}),
        group: 'triggers'),
    OptionField(
        path: 'triggers.connectivity_restored',
        label: 'Sync when online',
        description: 'Run when connectivity returns.',
        type: OptionValueType.boolean,
        defaultValue: true,
        condition: OptionCondition('mode', {'automatic'}),
        group: 'triggers'),
    OptionField(
        path: 'triggers.local_write.enabled',
        label: 'Sync local writes',
        description: 'Schedule sync after local mutations.',
        type: OptionValueType.boolean,
        defaultValue: true,
        condition: OptionCondition('mode', {'automatic'}),
        group: 'triggers'),
    OptionField(
        path: 'triggers.local_write.debounce',
        label: 'Write debounce',
        description: 'Quiet period before syncing writes.',
        type: OptionValueType.duration,
        defaultValue: '2s',
        minimum: 0,
        condition: OptionCondition('triggers.local_write.enabled', {true}),
        group: 'triggers'),
    OptionField(
        path: 'triggers.local_write.max_delay',
        label: 'Maximum write delay',
        description: 'Maximum delay while writes continue.',
        type: OptionValueType.duration,
        defaultValue: '10s',
        minimum: 1,
        condition: OptionCondition('triggers.local_write.enabled', {true}),
        group: 'triggers'),
    OptionField(
        path: 'discovery.remote_changes',
        label: 'Remote discovery',
        description: 'Automatic, push, poll, or disabled.',
        type: OptionValueType.enumeration,
        defaultValue: 'auto',
        values: {'auto', 'push', 'poll', 'disabled'},
        group: 'discovery'),
    OptionField(
        path: 'discovery.poll_interval',
        label: 'Poll interval',
        description: 'Foreground polling interval.',
        type: OptionValueType.duration,
        defaultValue: '60s',
        minimum: 1000,
        condition:
            OptionCondition('discovery.remote_changes', {'auto', 'poll'}),
        group: 'discovery'),
    OptionField(
        path: 'discovery.safety_reconcile_interval',
        label: 'Safety reconcile',
        description: 'Fallback full reconciliation interval.',
        type: OptionValueType.duration,
        defaultValue: '15m',
        minimum: 1000,
        condition:
            OptionCondition('discovery.remote_changes', {'auto', 'push'}),
        group: 'discovery'),
    OptionField(
        path: 'execution.timeout',
        label: 'Run timeout',
        description: 'Maximum duration of a foreground run.',
        type: OptionValueType.duration,
        defaultValue: '2m',
        minimum: 1000,
        group: 'execution'),
    OptionField(
        path: 'execution.busy_behavior',
        label: 'Busy behavior',
        description: 'Behavior when a run is active.',
        type: OptionValueType.enumeration,
        defaultValue: 'coalesce_then_rerun',
        values: {'coalesce', 'coalesce_then_rerun', 'reject'},
        group: 'execution'),
    OptionField(
        path: 'execution.max_parallel_transfers',
        label: 'Parallel transfers',
        description: 'Maximum concurrent object transfers.',
        type: OptionValueType.integer,
        defaultValue: 4,
        minimum: 1,
        maximum: 64,
        group: 'execution'),
    OptionField(
        path: 'execution.max_object_size',
        label: 'Maximum object size',
        description: 'Maximum synchronized object size.',
        type: OptionValueType.string,
        defaultValue: '20mb',
        group: 'execution'),
    OptionField(
        path: 'retry.strategy',
        label: 'Retry strategy',
        description: 'Retry delay algorithm.',
        type: OptionValueType.enumeration,
        defaultValue: 'exponential',
        values: {'none', 'fixed', 'exponential', 'sequence'},
        group: 'retry'),
    OptionField(
        path: 'retry.initial_delay',
        label: 'Initial retry delay',
        description: 'First exponential retry delay.',
        type: OptionValueType.duration,
        defaultValue: '5s',
        minimum: 0,
        condition: OptionCondition('retry.strategy', {'exponential'}),
        group: 'retry'),
    OptionField(
        path: 'retry.fixed_delay',
        label: 'Fixed retry delay',
        description: 'Delay for fixed retries.',
        type: OptionValueType.duration,
        defaultValue: '30s',
        minimum: 0,
        condition: OptionCondition('retry.strategy', {'fixed'}),
        group: 'retry'),
    OptionField(
        path: 'retry.sequence',
        label: 'Retry sequence',
        description: 'Delay list for sequence retries.',
        type: OptionValueType.stringList,
        defaultValue: ['5s', '30s', '2m', '10m'],
        condition: OptionCondition('retry.strategy', {'sequence'}),
        group: 'retry'),
    OptionField(
        path: 'retry.multiplier',
        label: 'Retry multiplier',
        description: 'Exponential multiplier.',
        type: OptionValueType.number,
        defaultValue: 3,
        minimum: 1,
        condition: OptionCondition('retry.strategy', {'exponential'}),
        group: 'retry'),
    OptionField(
        path: 'retry.max_delay',
        label: 'Maximum retry delay',
        description: 'Exponential delay cap.',
        type: OptionValueType.duration,
        defaultValue: '10m',
        minimum: 0,
        condition: OptionCondition('retry.strategy', {'exponential'}),
        group: 'retry'),
    OptionField(
        path: 'retry.jitter',
        label: 'Retry jitter',
        description: 'Random retry variance.',
        type: OptionValueType.percentage,
        defaultValue: '20%',
        minimum: 0,
        maximum: 1,
        condition: OptionCondition(
            'retry.strategy', {'fixed', 'exponential', 'sequence'}),
        group: 'retry'),
    OptionField(
        path: 'retry.max_attempts',
        label: 'Maximum attempts',
        description: 'Zero means unlimited.',
        type: OptionValueType.integer,
        defaultValue: 0,
        minimum: 0,
        condition: OptionCondition(
            'retry.strategy', {'fixed', 'exponential', 'sequence'}),
        group: 'retry'),
    OptionField(
        path: 'conflicts.strategy',
        label: 'Conflict strategy',
        description: 'Preserve, local wins, remote wins, or merge.',
        type: OptionValueType.enumeration,
        defaultValue: 'preserve',
        values: {'preserve', 'local_wins', 'remote_wins', 'merge'},
        group: 'conflicts'),
    OptionField(
        path: 'conflicts.delete_vs_update',
        label: 'Delete/update conflicts',
        description: 'Conflict, delete wins, or update wins.',
        type: OptionValueType.enumeration,
        defaultValue: 'conflict',
        values: {'conflict', 'delete_wins', 'update_wins'},
        group: 'conflicts'),
    OptionField(
        path: 'state.base_payload',
        label: 'Base payload',
        description: 'When common-base payloads are retained.',
        type: OptionValueType.enumeration,
        defaultValue: 'always',
        values: {'always', 'conflicts_only', 'never'},
        group: 'state'),
    OptionField(
        path: 'state.tombstone_retention',
        label: 'Tombstone retention',
        description: 'How long deletion records are retained.',
        type: OptionValueType.duration,
        defaultValue: '30d',
        minimum: 0,
        group: 'state'),
    OptionField(
        path: 'profiles.sync_on_activate',
        label: 'Sync on profile activation',
        description: 'Sync after switching profiles.',
        type: OptionValueType.boolean,
        defaultValue: true,
        group: 'profiles'),
    OptionField(
        path: 'profiles.existing_data',
        label: 'Existing data',
        description: 'Attach existing data or start empty.',
        type: OptionValueType.enumeration,
        defaultValue: 'attach_to_default',
        values: {'attach_to_default', 'new_empty'},
        group: 'profiles'),
  ]);

  static const background = OptionSchema([
    OptionField(
        path: 'enabled',
        label: 'Background sync',
        description: 'Enable system background scheduling.',
        type: OptionValueType.boolean,
        defaultValue: false,
        group: 'background'),
    OptionField(
        path: 'enqueue_on_pending',
        label: 'Enqueue pending writes',
        description: 'Register one-off work for pending writes.',
        type: OptionValueType.boolean,
        defaultValue: true,
        platforms: {TargetPlatform.android},
        group: 'background'),
    OptionField(
        path: 'periodic_interval',
        label: 'Periodic interval',
        description: 'Android periodic work interval.',
        type: OptionValueType.duration,
        defaultValue: '15m',
        minimum: 900000,
        platforms: {TargetPlatform.android},
        group: 'background'),
    OptionField(
        path: 'flex_interval',
        label: 'Flex interval',
        description: 'Android execution flex window.',
        type: OptionValueType.duration,
        defaultValue: '5m',
        minimum: 300000,
        platforms: {TargetPlatform.android},
        group: 'background'),
    OptionField(
        path: 'network',
        label: 'Network requirement',
        description: 'Connected or unmetered.',
        type: OptionValueType.enumeration,
        defaultValue: 'connected',
        values: {'connected', 'unmetered'},
        platforms: {TargetPlatform.android},
        group: 'background'),
    OptionField(
        path: 'requires_battery_not_low',
        label: 'Battery not low',
        description: 'Require adequate battery.',
        type: OptionValueType.boolean,
        defaultValue: true,
        platforms: {TargetPlatform.android},
        group: 'background'),
    OptionField(
        path: 'requires_charging',
        label: 'Requires charging',
        description: 'Only run while charging.',
        type: OptionValueType.boolean,
        defaultValue: false,
        platforms: {TargetPlatform.android},
        group: 'background'),
    OptionField(
        path: 'task',
        label: 'iOS task',
        description: 'App refresh or processing.',
        type: OptionValueType.enumeration,
        defaultValue: 'app_refresh',
        values: {'app_refresh', 'processing'},
        platforms: {TargetPlatform.ios},
        group: 'background'),
    OptionField(
        path: 'earliest_begin',
        label: 'Earliest begin',
        description: 'Earliest iOS scheduling delay.',
        type: OptionValueType.duration,
        defaultValue: '15m',
        minimum: 0,
        platforms: {TargetPlatform.ios},
        group: 'background'),
    OptionField(
        path: 'requires_network',
        label: 'Requires network',
        description: 'Require network for iOS processing.',
        type: OptionValueType.boolean,
        defaultValue: true,
        platforms: {TargetPlatform.ios},
        group: 'background'),
    OptionField(
        path: 'timeout',
        label: 'Worker timeout',
        description: 'Self-imposed worker time budget.',
        type: OptionValueType.duration,
        defaultValue: '25s',
        minimum: 1000,
        platforms: {TargetPlatform.android, TargetPlatform.ios},
        group: 'background'),
  ]);

  static const webDav = OptionSchema([
    OptionField(
        path: 'root_path',
        label: 'Root path',
        description: 'Default remote collection.',
        type: OptionValueType.string,
        defaultValue: 'Dartloom',
        group: 'backend'),
    OptionField(
        path: 'connect_timeout',
        label: 'Connect timeout',
        description: 'Connection establishment timeout.',
        type: OptionValueType.duration,
        defaultValue: '10s',
        minimum: 1,
        group: 'backend'),
    OptionField(
        path: 'request_timeout',
        label: 'Request timeout',
        description: 'Complete HTTP request timeout.',
        type: OptionValueType.duration,
        defaultValue: '30s',
        minimum: 1,
        group: 'backend'),
    OptionField(
        path: 'max_parallel_requests',
        label: 'Parallel requests',
        description: 'Maximum WebDAV requests.',
        type: OptionValueType.integer,
        defaultValue: 4,
        minimum: 1,
        maximum: 64,
        group: 'backend'),
    OptionField(
        path: 'create_missing_collections',
        label: 'Create collections',
        description: 'Create missing WebDAV collections.',
        type: OptionValueType.boolean,
        defaultValue: true,
        group: 'backend'),
    OptionField(
        path: 'hierarchical',
        label: 'Hierarchical replica',
        description: 'Recursively discover nested replica paths with Depth 1.',
        type: OptionValueType.boolean,
        defaultValue: false,
        group: 'backend'),
    OptionField(
        path: 'probe_depth_infinity',
        label: 'Probe Depth infinity',
        description:
            'Classify optional infinity support without relying on it.',
        type: OptionValueType.boolean,
        defaultValue: false,
        group: 'backend'),
    OptionField(
        path: 'legacy_collection',
        label: 'Legacy collection',
        description:
            'Optional v3 child collection copied into the replica root.',
        type: OptionValueType.string,
        defaultValue: '',
        group: 'migration'),
    OptionField(
        path: 'legacy_key_prefix',
        label: 'Legacy key prefix',
        description: 'Only matching legacy files are copied.',
        type: OptionValueType.string,
        defaultValue: '',
        group: 'migration'),
    OptionField(
        path: 'listing_limit_hint',
        label: 'Listing limit hint',
        description: 'Treat listings at this size as potentially incomplete.',
        type: OptionValueType.integer,
        defaultValue: 750,
        minimum: 1,
        group: 'backend'),
  ]);

  static List<String> validateSync(
    CapabilityInstanceConfig instance,
    Set<TargetPlatform> appPlatforms, {
    required String context,
  }) {
    final resolvedGlobal = deepMerge(
      policy.defaults(),
      Map.fromEntries(
          instance.policy.entries.where((entry) => entry.key != 'platforms')),
    );
    final errors = policy.validate(
      Map.fromEntries(
          instance.policy.entries.where((entry) => entry.key != 'platforms')),
      context: '$context.policy',
    );
    final maxObjectSize = readPath(resolvedGlobal, 'execution.max_object_size');
    if (maxObjectSize is! String ||
        !RegExp(r'^\d+(?:\.\d+)?(?:b|kb|mb|gb)$', caseSensitive: false)
            .hasMatch(maxObjectSize)) {
      errors.add(
          '$context.policy.execution.max_object_size must be a byte size such as 20mb.');
    }
    final retrySequence = readPath(resolvedGlobal, 'retry.sequence');
    if (retrySequence is List &&
        retrySequence.any(
            (value) => value is! String || tryParseDuration(value) == null)) {
      errors.add('$context.policy.retry.sequence must contain durations.');
    }
    final debounce = tryParseDuration(
      readPath(resolvedGlobal, 'triggers.local_write.debounce') as String? ??
          '',
    );
    final maxDelay = tryParseDuration(
      readPath(resolvedGlobal, 'triggers.local_write.max_delay') as String? ??
          '',
    );
    if (debounce != null && maxDelay != null && debounce > maxDelay) {
      errors.add(
          '$context.policy.triggers.local_write.debounce cannot exceed max_delay.');
    }
    final platformValues = instance.policy['platforms'];
    if (platformValues != null && platformValues is! Map) {
      errors.add('$context.policy.platforms must be a map.');
      return errors;
    }
    if (platformValues is Map) {
      for (final entry in platformValues.entries) {
        TargetPlatform? platform;
        try {
          platform = TargetPlatform.values.byName(entry.key.toString());
        } on ArgumentError {
          errors.add('$context.policy.platforms.${entry.key} is unknown.');
          continue;
        }
        if (!appPlatforms.contains(platform)) {
          errors.add(
              '$context.policy.platforms.${platform.name} targets a disabled platform.');
        }
        if (entry.value is! Map) {
          errors
              .add('$context.policy.platforms.${platform.name} must be a map.');
          continue;
        }
        final override = (entry.value as Map).cast<String, Object?>();
        final backgroundValue = override['background'];
        final foregroundOverride = Map<String, Object?>.fromEntries(
            override.entries.where((item) => item.key != 'background'));
        errors.addAll(policy.validate(foregroundOverride,
            context: '$context.policy.platforms.${platform.name}'));
        if (backgroundValue != null) {
          if (!{TargetPlatform.android, TargetPlatform.ios}
              .contains(platform)) {
            errors.add(
                '$context.policy.platforms.${platform.name}.background is unsupported.');
          } else if (backgroundValue is! Map) {
            errors.add(
                '$context.policy.platforms.${platform.name}.background must be a map.');
          } else {
            final backgroundMap = backgroundValue.cast<String, Object?>();
            errors.addAll(background.validate(backgroundMap,
                context:
                    '$context.policy.platforms.${platform.name}.background'));
            for (final field in background.fields) {
              if (readPath(backgroundMap, field.path) != null &&
                  field.platforms != null &&
                  !field.platforms!.contains(platform)) {
                errors.add(
                    '$context.policy.platforms.${platform.name}.background.${field.path} is unsupported on ${platform.name}.');
              }
            }
            if (platform == TargetPlatform.android) {
              final resolvedBackground = deepMerge(
                background.defaults(),
                backgroundMap,
              );
              final periodic = tryParseDuration(
                readPath(resolvedBackground, 'periodic_interval') as String? ??
                    '',
              );
              final flex = tryParseDuration(
                readPath(resolvedBackground, 'flex_interval') as String? ?? '',
              );
              if (periodic != null && flex != null && flex > periodic) {
                errors.add(
                    '$context.policy.platforms.android.background.flex_interval cannot exceed periodic_interval.');
              }
            }
          }
        }
      }
    }
    if (instance.backend?.implementation == 'webdav') {
      errors.addAll(webDav.validate(instance.backend!.options,
          context: '$context.backend.options'));
      if (readPath(instance.policy, 'discovery.remote_changes') == 'push') {
        errors.add(
            '$context cannot use discovery.remote_changes=push with WebDAV.');
      }
    }
    if (readPath(instance.policy, 'conflicts.strategy') == 'merge' &&
        instance.mergeFactory == null) {
      errors.add('$context conflict strategy merge requires merge_factory.');
    }
    return errors;
  }
}
