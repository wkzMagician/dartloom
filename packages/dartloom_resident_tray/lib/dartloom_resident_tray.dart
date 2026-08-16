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
  bool _quitting = false;
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
    await Future.wait<void>([
      windowManager.show(),
      windowManager.focus(),
    ]);
  }

  @override
  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    try {
      final shouldQuit = await Future<bool>.sync(
        () => _configuration.onExitRequested?.call() ?? true,
      ).timeout(const Duration(milliseconds: 800), onTimeout: () => true);
      if (!shouldQuit) {
        _quitting = false;
        return;
      }
      windowManager.removeListener(this);
      trayManager.removeListener(this);
      await trayManager.destroy().timeout(const Duration(milliseconds: 250));
      await windowManager.setPreventClose(false);
      // Send the normal native close message so custom Flutter runners can
      // terminate their message loop. The close listener intentionally does
      // nothing while _quitting; calling destroy() from onWindowClose would
      // re-enter the window plugin and can leave the foreground window stuck
      // for several seconds.
      await windowManager.close().timeout(const Duration(seconds: 1));
    } on Object {
      // A tray/window plugin must not strand the process during exit.
      try {
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
      } on Object {
        // The native process is already on the exit path.
      }
    }
  }

  @override
  Future<void> dispose() async {
    if (!_initialized) return;
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    await trayManager.destroy();
    _initialized = false;
    _quitting = false;
  }

  @override
  Future<void> onWindowClose() async {
    if (!_quitting) await windowManager.hide();
  }

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
