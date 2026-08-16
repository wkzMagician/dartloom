# dartloom_resident_tray

Dartloom package. Applications normally select it through `the Dartloom package selection UI`
instead of importing it directly from feature code.

It applies the contract's menu, click-policy, and exit-callback configuration
to `tray_manager` and `window_manager`.

The adapter accepts an `icon_path` fallback plus optional
`icon_path_linux`, `icon_path_macos`, and `icon_path_windows` options. This
allows applications to use PNG tray icons on Linux and ICO tray icons on
Windows.
