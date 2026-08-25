# Dartloom Android External Input

This [Dartloom](https://github.com/wkzMagician/dartloom) package receives
Android sharing and Open With intents through `AndroidExternalInputService`,
and reads a foreground clipboard explicitly through
`AndroidClipboardExternalInputReader`. Declare the app activity's `SEND`,
`SEND_MULTIPLE`, and `VIEW` intent filters in the application manifest.

Applications decide when to call `read`; the adapter does not observe lifecycle
events. Clipboard files and shared files are copied into private app storage
before they are returned, so callers do not need URI grants.
