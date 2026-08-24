# Dartloom Android External Input

This [Dartloom](https://github.com/wkzMagician/dartloom) package receives
Android sharing and Open With intents and exposes them through
AndroidExternalInputService.

Declare the app activity's SEND, SEND_MULTIPLE, and VIEW intent filters in the
application manifest. The plugin copies files into private app storage before
emitting them, so callers do not need URI grants.
