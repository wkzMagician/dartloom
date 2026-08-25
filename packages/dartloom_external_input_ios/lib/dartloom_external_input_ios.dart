import 'package:dartloom_external_input/dartloom_external_input.dart';
import 'package:flutter/services.dart';

final class IosExternalInputService implements ExternalInputService {
  IosExternalInputService({
    required this.appGroupIdentifier,
    EventChannel? events,
    MethodChannel? methods,
  })  : _events = events ??
            const EventChannel('dev.dartloom.external_input/ios/events'),
        _methods = methods ??
            const MethodChannel('dev.dartloom.external_input/ios/methods');

  final String appGroupIdentifier;
  final EventChannel _events;
  final MethodChannel _methods;

  Stream<ExternalInputBatch>? _inputs;

  @override
  Stream<ExternalInputBatch> get inputs => _inputs ??= _events
      .receiveBroadcastStream({'appGroupIdentifier': appGroupIdentifier}).map(
          ExternalInputBatch.fromJson);

  @override
  Future<List<ExternalInputBatch>> takePending() async {
    final values = await _methods.invokeMethod<List<Object?>>('takePending', {
      'appGroupIdentifier': appGroupIdentifier,
    });
    return [
      for (final value in values ?? const <Object?>[])
        ExternalInputBatch.fromJson(value),
    ];
  }
}

/// Explicit reader for the foreground iOS system pasteboard.
///
/// Calling [read] may cause iOS to ask the user to allow pasting. Applications
/// decide when that prompt is appropriate.
final class IosClipboardExternalInputReader
    implements ClipboardExternalInputReader {
  IosClipboardExternalInputReader({MethodChannel? methods})
      : _methods = methods ??
            const MethodChannel('dev.dartloom.external_input/ios/methods');

  final MethodChannel _methods;

  @override
  Future<ClipboardReadResult> read({String? afterChangeToken}) async {
    final value = await _methods.invokeMethod<Object?>('readClipboard', {
      if (afterChangeToken != null) 'afterChangeToken': afterChangeToken,
    });
    return ClipboardReadResult.fromJson(value);
  }
}
