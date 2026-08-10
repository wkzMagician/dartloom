import 'package:dartloom_resident_tray/dartloom_resident_tray.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const trayChannel = MethodChannel('tray_manager');
  const windowChannel = MethodChannel('window_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> trayCalls;
  late List<MethodCall> trayMethodCalls;

  setUp(() {
    trayCalls = [];
    trayMethodCalls = [];
    messenger.setMockMethodCallHandler(windowChannel, (call) async => true);
    messenger.setMockMethodCallHandler(trayChannel, (call) async {
      trayCalls.add(call.method);
      trayMethodCalls.add(call);
      return true;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(windowChannel, null);
    messenger.setMockMethodCallHandler(trayChannel, null);
  });

  test('skips the unsupported tooltip call on Linux', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final service = TrayResidentService(
      tooltip: 'Mini Todo',
      linuxIconPath: 'images/tray_icon.png',
    );

    await service.initialize(iconPath: 'images/tray_icon.ico');

    expect(trayCalls, ['setIcon', 'setContextMenu']);
    expect(
      (trayMethodCalls.first.arguments as Map)['iconPath'],
      endsWith('images/tray_icon.png'),
    );
    await service.dispose();
  });

  test('sets the tooltip after the icon on supported platforms', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final service = TrayResidentService(tooltip: 'Mini Todo');

    await service.initialize(iconPath: 'images/tray_icon.ico');

    expect(trayCalls, ['setIcon', 'setToolTip', 'setContextMenu']);
    await service.dispose();
  });
}
