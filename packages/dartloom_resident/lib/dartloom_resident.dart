import 'dart:async';

/// Behavior invoked when a user clicks the tray icon.
enum ResidentClickAction { restore, showMenu, ignore }

/// A platform-neutral tray menu entry.
final class ResidentMenuItem {
  const ResidentMenuItem.action({
    required this.id,
    required this.label,
    this.enabled = true,
  }) : isSeparator = false;

  const ResidentMenuItem.separator()
      : id = null,
        label = null,
        enabled = false,
        isSeparator = true;

  final String? id;
  final String? label;
  final bool enabled;
  final bool isSeparator;
}

typedef ResidentMenuSelection = FutureOr<void> Function(String id);
typedef ResidentExitRequest = FutureOr<bool> Function();

/// Adapter-independent resident/tray behavior.
///
/// [onExitRequested] is called for the configured [exitMenuItemId]. Returning
/// false keeps the app alive; returning true (or omitting the callback) exits
/// the application completely.
final class ResidentConfiguration {
  const ResidentConfiguration({
    this.menu = const [],
    this.leftClick = ResidentClickAction.restore,
    this.rightClick = ResidentClickAction.showMenu,
    this.exitMenuItemId = 'quit',
    this.onMenuSelected,
    this.onExitRequested,
  });

  final List<ResidentMenuItem> menu;
  final ResidentClickAction leftClick;
  final ResidentClickAction rightClick;
  final String? exitMenuItemId;
  final ResidentMenuSelection? onMenuSelected;
  final ResidentExitRequest? onExitRequested;

  ResidentConfiguration copyWith({
    List<ResidentMenuItem>? menu,
    ResidentClickAction? leftClick,
    ResidentClickAction? rightClick,
    String? exitMenuItemId,
    ResidentMenuSelection? onMenuSelected,
    ResidentExitRequest? onExitRequested,
  }) =>
      ResidentConfiguration(
        menu: menu ?? this.menu,
        leftClick: leftClick ?? this.leftClick,
        rightClick: rightClick ?? this.rightClick,
        exitMenuItemId: exitMenuItemId ?? this.exitMenuItemId,
        onMenuSelected: onMenuSelected ?? this.onMenuSelected,
        onExitRequested: onExitRequested ?? this.onExitRequested,
      );
}

abstract interface class ResidentService {
  ResidentConfiguration get configuration;

  Future<void> initialize({
    required String iconPath,
    ResidentConfiguration configuration = const ResidentConfiguration(),
  });
  Future<void> configure(ResidentConfiguration configuration);
  Future<void> restore();
  Future<void> quit();
  Future<void> dispose();
}
