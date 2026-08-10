import 'dart:async';

import 'package:dartloom_resident/dartloom_resident.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

final class TrayResidentService
    with WindowListener, TrayListener
    implements ResidentService {
  TrayResidentService({
    this.tooltip = 'Dartloom application',
    this.linuxIconPath,
    this.macosIconPath,
    this.windowsIconPath,
  });

  final String tooltip;
  final String? linuxIconPath;
  final String? macosIconPath;
  final String? windowsIconPath;
  bool _initialized = false;
  ResidentConfiguration _configuration = const ResidentConfiguration();

  @override
  ResidentConfiguration get configuration => _configuration;

  @override
  Future<void> initialize({
    required String iconPath,
    ResidentConfiguration configuration = const ResidentConfiguration(),
  }) async {
    if (_initialized) return;
    WidgetsFlutterBinding.ensureInitialized();
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    trayManager.addListener(this);
    await trayManager.setIcon(_iconPathForCurrentPlatform(iconPath));
    if (defaultTargetPlatform != TargetPlatform.linux) {
      await trayManager.setToolTip(tooltip);
    }
    _initialized = true;
    await configure(configuration);
  }

  @override
  Future<void> configure(ResidentConfiguration configuration) async {
    _configuration = configuration;
    if (!_initialized) return;
    await trayManager.setContextMenu(
      Menu(
        items: [
          for (final item in configuration.menu)
            if (item.isSeparator)
              MenuItem.separator()
            else
              MenuItem(
                key: item.id,
                label: item.label,
                disabled: !item.enabled,
              ),
        ],
      ),
    );
  }

  @override
  Future<void> restore() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> quit() async {
    final shouldQuit = await _configuration.onExitRequested?.call() ?? true;
    if (!shouldQuit) return;
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
  void onTrayIconMouseDown() =>
      unawaited(_handleClick(_configuration.leftClick));

  @override
  void onTrayIconRightMouseDown() =>
      unawaited(_handleClick(_configuration.rightClick));

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final id = menuItem.key;
    if (id != null) unawaited(_handleMenuSelection(id));
  }

  Future<void> _handleClick(ResidentClickAction action) => switch (action) {
    ResidentClickAction.restore => restore(),
    ResidentClickAction.showMenu => trayManager.popUpContextMenu(),
    ResidentClickAction.ignore => Future<void>.value(),
  };

  Future<void> _handleMenuSelection(String id) async {
    if (id == _configuration.exitMenuItemId) {
      await quit();
      return;
    }
    await _configuration.onMenuSelected?.call(id);
  }

  String _iconPathForCurrentPlatform(String fallback) =>
      switch (defaultTargetPlatform) {
        TargetPlatform.linux => linuxIconPath ?? fallback,
        TargetPlatform.macOS => macosIconPath ?? fallback,
        TargetPlatform.windows => windowsIconPath ?? fallback,
        _ => fallback,
      };
}
