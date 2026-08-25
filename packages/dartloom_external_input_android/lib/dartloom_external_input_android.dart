import 'package:dartloom_external_input/dartloom_external_input.dart';
import 'package:flutter/services.dart';

final class AndroidExternalInputService implements ExternalInputService {
  AndroidExternalInputService({EventChannel? events, MethodChannel? methods})
      : _events =
            events ?? const EventChannel('dev.dartloom.external_input/events'),
        _methods = methods ??
            const MethodChannel('dev.dartloom.external_input/methods');

  final EventChannel _events;
  final MethodChannel _methods;

  Stream<ExternalInputBatch>? _inputs;

  @override
  Stream<ExternalInputBatch> get inputs => _inputs ??=
      _events.receiveBroadcastStream().map(ExternalInputBatch.fromJson);

  @override
  Future<List<ExternalInputBatch>> takePending() async {
    final values = await _methods.invokeMethod<List<Object?>>('takePending');
    return [
      for (final value in values ?? const <Object?>[])
        ExternalInputBatch.fromJson(value),
    ];
  }
}

/// Explicit reader for the foreground Android system clipboard.
///
/// The application owns lifecycle policy and calls [read] only when clipboard
/// access is appropriate for its user experience.
final class AndroidClipboardExternalInputReader
    implements ClipboardExternalInputReader {
  AndroidClipboardExternalInputReader({MethodChannel? methods})
      : _methods = methods ??
            const MethodChannel('dev.dartloom.external_input/methods');

  final MethodChannel _methods;

  @override
  Future<ClipboardReadResult> read({String? afterChangeToken}) async {
    final value = await _methods.invokeMethod<Object?>('readClipboard', {
      if (afterChangeToken != null) 'afterChangeToken': afterChangeToken,
    });
    return ClipboardReadResult.fromJson(value);
  }
}
