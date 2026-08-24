import Flutter
import UIKit

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
    guard call.method == "takePending",
          let arguments = call.arguments as? [String: Any],
          let appGroupIdentifier = arguments["appGroupIdentifier"] as? String,
          !appGroupIdentifier.isEmpty else {
      result(FlutterMethodNotImplemented)
      return
    }
    do {
      result(try ExternalInputInbox.take(appGroupIdentifier: appGroupIdentifier))
    } catch {
      result(FlutterError(
        code: "external_input_inbox_error",
        message: error.localizedDescription,
        details: nil
      ))
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
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
