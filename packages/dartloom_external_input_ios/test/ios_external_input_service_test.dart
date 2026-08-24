import 'package:dartloom_external_input_ios/dartloom_external_input_ios.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('takes pending batches with the configured App Group', () async {
    const methods = MethodChannel('dev.dartloom.external_input/ios/methods');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methods, (call) async {
      expect(call.arguments, {'appGroupIdentifier': 'group.example.app'});
      return [
        {
          'source': 'share',
          'items': [
            {'type': 'url', 'url': 'https://example.com'},
          ],
        },
      ];
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methods, null),
    );

    final batches = await IosExternalInputService(
      appGroupIdentifier: 'group.example.app',
    ).takePending();

    expect(batches.single.items.single.toJson()['url'], 'https://example.com');
  });
}
