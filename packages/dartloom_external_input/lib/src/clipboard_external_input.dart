import 'external_input_batch.dart';

/// Reads the current clipboard as platform-neutral external input.
///
/// Reading is deliberately explicit: applications choose when a platform
/// paste permission prompt or clipboard-access notification is appropriate.
abstract interface class ClipboardExternalInputReader {
  /// Reads clipboard content which differs from [afterChangeToken].
  ///
  /// Tokens are opaque and only meaningful to the reader that returned them.
  /// Passing `null` forces a read even when the clipboard has not changed.
  Future<ClipboardReadResult> read({String? afterChangeToken});
}

sealed class ClipboardReadResult {
  const ClipboardReadResult();

  factory ClipboardReadResult.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('A clipboard result must be a JSON object.');
    }
    final json = Map<String, Object?>.from(value);
    switch (json['kind']) {
      case 'content':
        final token = json['changeToken'];
        if (token is! String || token.isEmpty) {
          throw const FormatException(
              'Clipboard content requires a change token.');
        }
        return ClipboardContent(
          changeToken: token,
          batch: ExternalInputBatch.fromJson(json['batch']),
        );
      case 'unchanged':
        return const ClipboardUnchanged();
      case 'empty':
        final token = json['changeToken'];
        if (token != null && token is! String) {
          throw const FormatException(
              'Clipboard change tokens must be strings.');
        }
        return ClipboardEmpty(changeToken: token as String?);
      case 'unavailable':
        return ClipboardUnavailable(reason: json['reason'] as String?);
      default:
        throw FormatException('Unknown clipboard result kind: ${json['kind']}');
    }
  }
}

final class ClipboardContent extends ClipboardReadResult {
  ClipboardContent({required this.changeToken, required this.batch})
      : assert(batch.source == ExternalInputSource.clipboard);

  final String changeToken;
  final ExternalInputBatch batch;
}

final class ClipboardUnchanged extends ClipboardReadResult {
  const ClipboardUnchanged();
}

final class ClipboardEmpty extends ClipboardReadResult {
  const ClipboardEmpty({this.changeToken});

  /// The observed clipboard token, when the platform can safely expose one.
  final String? changeToken;
}

final class ClipboardUnavailable extends ClipboardReadResult {
  const ClipboardUnavailable({this.reason});

  /// Best-effort platform diagnostic; it is not a stable machine contract.
  final String? reason;
}
