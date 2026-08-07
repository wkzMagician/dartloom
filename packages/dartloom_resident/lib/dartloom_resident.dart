import 'package:flutter/widgets.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Handles the desktop pattern where a close request hides the window and the
/// application remains reachable from a system tray or menu-bar icon.
///
/// Call [initialize] before `runApp`, provide a platform-appropriate icon, and
/// call [dispose] before the process exits. Supported desktop hosts are
/// Windows, macOS, and Linux.
class DartloomResidentController with WindowListener, TrayListener {
  DartloomResidentController({this.tooltip = 'Dartloom application'});

  final String tooltip;
  bool _initialized = false;

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

  Future<void> restore() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> quit() async {
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

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
