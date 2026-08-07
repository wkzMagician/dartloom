# dartloom_resident

Desktop close-to-tray support for Dartloom applications on Windows, macOS, and
Linux. It uses `window_manager` to intercept a close request and `tray_manager`
to restore or quit the application from a system tray/menu bar icon.

Add it with `dartloom cap add resident`, then initialize it before `runApp`:

```dart
final resident = DartloomResidentController();
await resident.initialize(iconPath: 'assets/tray_icon.png');
runApp(const MyApp());
```

Call `resident.dispose()` during shutdown. Use an `.ico` icon on Windows where
appropriate. Some Linux desktops require an AppIndicator package before tray
icons are visible.
