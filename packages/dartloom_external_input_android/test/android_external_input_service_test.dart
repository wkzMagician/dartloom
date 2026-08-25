import 'package:dartloom_external_input/dartloom_external_input.dart';
import 'package:dartloom_external_input_android/dartloom_external_input_android.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('takes pending batches from the platform adapter', () async {
    const methods = MethodChannel('dev.dartloom.external_input/methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methods, (call) async {
      expect(call.method, 'takePending');
      return [
        {
          'source': 'share',
          'items': [
            {'type': 'text', 'text': 'Shared note'},
          ],
        },
      ];
    });
    addTearDown(() => messenger.setMockMethodCallHandler(methods, null));

    final batches = await AndroidExternalInputService(
      methods: methods,
    ).takePending();

    expect(batches.single.items.single.toJson()['text'], 'Shared note');
  });

  test('reads clipboard results through the platform adapter', () async {
    const methods = MethodChannel('dev.dartloom.external_input/methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methods, (call) async {
      expect(call.method, 'readClipboard');
      expect(call.arguments, {'afterChangeToken': 'old-token'});
      return {
        'kind': 'content',
        'changeToken': 'new-token',
        'batch': {
          'source': 'clipboard',
          'items': [
            {'type': 'text', 'text': 'Copied note'},
          ],
        },
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(methods, null));

    final result = await AndroidClipboardExternalInputReader(
      methods: methods,
    ).read(afterChangeToken: 'old-token');

    expect(result, isA<ClipboardContent>());
    expect((result as ClipboardContent).changeToken, 'new-token');
  });
}
