# dartloom_resident

Stable close-to-tray lifecycle contract for Windows, macOS, and Linux. Tray/window plugin dependencies live in a separate adapter.

Applications normally select implementations through `dartloom cap`.

`ResidentService` exposes `ResidentConfiguration`, so applications can provide
tray menu items, left/right click behavior, and a complete-exit callback
without importing a concrete tray adapter.
