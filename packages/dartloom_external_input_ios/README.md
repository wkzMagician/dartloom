# Dartloom iOS External Input

This [Dartloom](https://github.com/wkzMagician/dartloom) package exposes an App
Group inbox through `IosExternalInputService` and an explicit system-pasteboard
reader through `IosClipboardExternalInputReader`.

Enable the same App Group on the app and its Share Extension. Compile
`ios/Classes/ExternalInputInbox.swift` and
`ios/ShareExtension/ShareExtensionCore.swift` into the extension target, then
configure a minimal subclass whose `appGroupIdentifier` returns the configured
group string. The extension writes batches to the inbox and completes. The app
consumes them at launch and whenever it becomes active; it never depends on
opening a custom URL from the extension.

Applications decide when to call the clipboard reader. Calling it may show the
system “Paste from …” prompt. File URLs are copied while their security-scoped
access is active before the adapter returns them.
