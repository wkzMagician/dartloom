import 'package:dartloom_resident/dartloom_resident.dart';
import 'package:flutter/widgets.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

final class TrayResidentService
    with WindowListener, TrayListener
    implements ResidentService {
  TrayResidentService({this.tooltip = 'Dartloom application'});

  final String tooltip;
  bool _initialized = false;

  @override
  Future<void> initialize({required String iconPath}) async {
    if (_initialized) return;
    WidgetsFlutterBinding.ensureInitialized();
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    trayManager.addListener(this);
    await trayManager.setToolTip(tooltip);
    await trayManager.setIcon(iconPath);
    _initialized = true;
  }

  @override
  Future<void> restore() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> quit() async {
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  Future<void> dispose() async {
    if (!_initialized) return;
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    await trayManager.destroy();
    _initialized = false;
  }

  @override
  Future<void> onWindowClose() => windowManager.hide();
  @override
  Future<void> onTrayIconMouseDown() => restore();
}
