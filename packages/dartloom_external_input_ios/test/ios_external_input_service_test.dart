import 'package:dartloom_external_input/dartloom_external_input.dart';
import 'package:dartloom_external_input_ios/dartloom_external_input_ios.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('takes pending batches with a configured App Group', () async {
    const methods = MethodChannel('dev.dartloom.external_input/ios/methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methods, (call) async {
      expect(call.method, 'takePending');
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
    addTearDown(() => messenger.setMockMethodCallHandler(methods, null));

    final batches = await IosExternalInputService(
      appGroupIdentifier: 'group.example.app',
      methods: methods,
    ).takePending();

    expect(batches.single.items.single.toJson()['url'], 'https://example.com');
  });

  test('reads clipboard results through the platform adapter', () async {
    const methods = MethodChannel('dev.dartloom.external_input/ios/methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methods, (call) async {
      expect(call.method, 'readClipboard');
      expect(call.arguments, {'afterChangeToken': 'token'});
      return {'kind': 'unchanged'};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(methods, null));

    final result = await IosClipboardExternalInputReader(
      methods: methods,
    ).read(afterChangeToken: 'token');

    expect(result, isA<ClipboardUnchanged>());
  });
}
