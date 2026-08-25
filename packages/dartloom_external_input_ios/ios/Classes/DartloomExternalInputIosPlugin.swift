import Flutter
import UIKit
import UniformTypeIdentifiers

public final class DartloomExternalInputIosPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let methodChannelName = "dev.dartloom.external_input/ios/methods"
  private static let eventChannelName = "dev.dartloom.external_input/ios/events"

  private var eventSink: FlutterEventSink?
  private var appGroupIdentifier: String?
  private var foregroundObserver: NSObjectProtocol?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = DartloomExternalInputIosPlugin()
    let methods = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: registrar.messenger()
    )
    let events = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: methods)
    events.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "takePending":
      guard let arguments = call.arguments as? [String: Any],
            let identifier = arguments["appGroupIdentifier"] as? String,
            !identifier.isEmpty else {
        result(FlutterMethodNotImplemented)
        return
      }
      do {
        result(try ExternalInputInbox.take(appGroupIdentifier: identifier))
      } catch {
        result(FlutterError(
          code: "external_input_inbox_error",
          message: error.localizedDescription,
          details: nil
        ))
      }
    case "readClipboard":
      let arguments = call.arguments as? [String: Any]
      result(readClipboard(afterChangeToken: arguments?["afterChangeToken"] as? String))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    guard let values = arguments as? [String: Any],
          let identifier = values["appGroupIdentifier"] as? String,
          !identifier.isEmpty else {
      return FlutterError(
        code: "missing_app_group",
        message: "An App Group identifier is required.",
        details: nil
      )
    }
    eventSink = events
    appGroupIdentifier = identifier
    foregroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.publishPending()
    }
    publishPending()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    appGroupIdentifier = nil
    if let observer = foregroundObserver {
      NotificationCenter.default.removeObserver(observer)
      foregroundObserver = nil
    }
    return nil
  }

  private func readClipboard(afterChangeToken: String?) -> [String: Any] {
    let pasteboard = UIPasteboard.general
    let token = String(pasteboard.changeCount)
    if afterChangeToken == token {
      return ["kind": "unchanged"]
    }

    var items = [[String: Any]]()
    for item in pasteboard.items {
      if let url = url(from: item) {
        if url.isFileURL {
          do {
            let retained = try retainClipboardFile(url)
            items.append([
              "type": "file",
              "path": retained.path,
              "name": retained.lastPathComponent,
            ])
          } catch {
            continue
          }
        } else {
          items.append(["type": "url", "url": url.absoluteString])
        }
      } else if let text = text(from: item) {
        items.append(input(for: text))
      }
    }

    // Some providers expose only a convenience pasteboard value rather than a
    // property-list value in `items`.
    if items.isEmpty, let url = pasteboard.url {
      items.append(["type": "url", "url": url.absoluteString])
    }
    if items.isEmpty, let text = pasteboard.string, !text.isEmpty {
      items.append(input(for: text))
    }
    if items.isEmpty {
      return ["kind": "empty", "changeToken": token]
    }
    return [
      "kind": "content",
      "changeToken": token,
      "batch": ["items": items, "source": "clipboard"],
    ]
  }

  private func url(from item: [String: Any]) -> URL? {
    for identifier in [UTType.fileURL.identifier, UTType.url.identifier] {
      guard let value = item[identifier] else { continue }
      if let url = value as? URL {
        return url
      }
      if let url = value as? NSURL {
        return url as URL
      }
      if let value = value as? String, let url = URL(string: value) {
        return url
      }
    }
    return nil
  }

  private func text(from item: [String: Any]) -> String? {
    for identifier in [
      UTType.plainText.identifier,
      "public.utf8-plain-text",
      "public.text",
    ] {
      if let text = item[identifier] as? String, !text.isEmpty {
        return text
      }
    }
    return nil
  }

  private func input(for text: String) -> [String: Any] {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let url = URL(string: trimmed),
       let scheme = url.scheme?.lowercased(),
       scheme == "http" || scheme == "https" {
      return ["type": "url", "url": url.absoluteString]
    }
    return ["type": "text", "text": text]
  }

  private func retainClipboardFile(_ source: URL) throws -> URL {
    let manager = FileManager.default
    let directory = try manager.url(
      for: .cachesDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    .appendingPathComponent("DartloomExternalInput/clipboard", isDirectory: true)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    let name = source.lastPathComponent
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "\0", with: "")
    let destination = directory.appendingPathComponent(
      "\(UUID().uuidString)-\(name.isEmpty ? "attachment" : name)"
    )
    let accessing = source.startAccessingSecurityScopedResource()
    defer {
      if accessing {
        source.stopAccessingSecurityScopedResource()
      }
    }
    try manager.copyItem(at: source, to: destination)
    return destination
  }

  private func publishPending() {
    guard let appGroupIdentifier, let eventSink else { return }
    do {
      for batch in try ExternalInputInbox.take(appGroupIdentifier: appGroupIdentifier) {
        eventSink(batch)
      }
    } catch {
      eventSink(FlutterError(
        code: "external_input_inbox_error",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }
}
