import 'package:dartloom_external_input_android/dartloom_external_input_android.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('takes pending batches from the platform adapter', () async {
    const methods = MethodChannel('dev.dartloom.external_input/methods');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methods, (call) async {
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
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methods, null),
    );

    final batches = await AndroidExternalInputService().takePending();

    expect(batches.single.items.single.toJson()['text'], 'Shared note');
  });
}
