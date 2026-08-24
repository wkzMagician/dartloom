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
