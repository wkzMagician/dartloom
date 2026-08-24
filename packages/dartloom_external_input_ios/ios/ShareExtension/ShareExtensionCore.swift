import Foundation
import Social
import UniformTypeIdentifiers

/// Add this source file and ExternalInputInbox.swift to an application's Share
/// Extension target. The extension only writes the App Group inbox; it never
/// attempts to launch the containing application.
open class DartloomExternalInputShareViewController: SLComposeServiceViewController {
  /// Override this in the application-owned configuration subclass.
  open var appGroupIdentifier: String {
    fatalError("Configure appGroupIdentifier in the Share Extension subclass.")
  }

  public override func isContentValid() -> Bool { true }

  public override func didSelectPost() {
    let providers = (extensionContext?.inputItems ?? [])
      .compactMap { $0 as? NSExtensionItem }
      .flatMap { $0.attachments ?? [] }
    let completion = DispatchGroup()
    let lock = NSLock()
    var inputs = [[String: Any]]()

    for provider in providers {
      completion.enter()
      load(provider: provider) { input in
        if let input {
          lock.lock()
          inputs.append(input)
          lock.unlock()
        }
        completion.leave()
      }
    }
    completion.notify(queue: .main) { [weak self] in
      guard let self else { return }
      try? ExternalInputInbox.write(
        appGroupIdentifier: self.appGroupIdentifier,
        items: inputs,
        source: "share"
      )
      self.extensionContext?.completeRequest(returningItems: nil)
    }
  }

  public override func configurationItems() -> [Any]! { [] }

  private func load(
    provider: NSItemProvider,
    completion: @escaping ([String: Any]?) -> Void
  ) {
    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
      loadFile(provider: provider, typeIdentifier: UTType.fileURL.identifier, completion: completion)
      return
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
      provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) {
        value, error in
        guard error == nil, let text = value as? String else {
          completion(nil)
          return
        }
        completion(["type": "text", "text": text])
      }
      return
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
      provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) {
        value, error in
        let url = (value as? URL) ?? (value as? NSURL).map { $0 as URL }
        guard error == nil, let url else {
          completion(nil)
          return
        }
        completion(["type": "url", "url": url.absoluteString])
      }
      return
    }
    let fallback = provider.registeredTypeIdentifiers.first {
      UTType($0)?.conforms(to: .data) == true
    } ?? UTType.data.identifier
    loadFile(provider: provider, typeIdentifier: fallback, completion: completion)
  }

  private func loadFile(
    provider: NSItemProvider,
    typeIdentifier: String,
    completion: @escaping ([String: Any]?) -> Void
  ) {
    provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] url, error in
      guard let self, let url, error == nil else {
        completion(nil)
        return
      }
      do {
        let destination = try ExternalInputInbox.fileDestination(
          appGroupIdentifier: self.appGroupIdentifier,
          suggestedName: url.lastPathComponent
        )
        try FileManager.default.copyItem(at: url, to: destination)
        completion([
          "type": "file",
          "path": destination.path,
          "name": url.lastPathComponent,
          "mimeType": UTType(typeIdentifier)?.preferredMIMEType as Any,
        ])
      } catch {
        completion(nil)
      }
    }
  }
}
