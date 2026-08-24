import Foundation

enum ExternalInputInbox {
  private static let directoryName = "DartloomExternalInput"
  private static let batchesDirectoryName = "batches"
  private static let filesDirectoryName = "files"

  static func write(
    appGroupIdentifier: String,
    items: [[String: Any]],
    source: String
  ) throws {
    guard !items.isEmpty else { return }
    let directories = try inboxDirectories(appGroupIdentifier: appGroupIdentifier)
    let payload: [String: Any] = ["items": items, "source": source]
    let data = try JSONSerialization.data(withJSONObject: payload, options: [])
    let destination = directories.batches.appendingPathComponent(
      "\(UUID().uuidString).json"
    )
    try data.write(to: destination, options: .atomic)
  }

  static func fileDestination(
    appGroupIdentifier: String,
    suggestedName: String
  ) throws -> URL {
    let directories = try inboxDirectories(appGroupIdentifier: appGroupIdentifier)
    let sanitized = suggestedName
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "\0", with: "")
    return directories.files.appendingPathComponent(
      "\(UUID().uuidString)-\(sanitized.isEmpty ? "attachment" : sanitized)"
    )
  }

  static func take(appGroupIdentifier: String) throws -> [[String: Any]] {
    let directories = try inboxDirectories(appGroupIdentifier: appGroupIdentifier)
    let files = try FileManager.default.contentsOfDirectory(
      at: directories.batches,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ).sorted { $0.lastPathComponent < $1.lastPathComponent }
    var batches = [[String: Any]]()
    for file in files where file.pathExtension == "json" {
      do {
        let data = try Data(contentsOf: file)
        guard let batch = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
          throw CocoaError(.fileReadCorruptFile)
        }
        let moved = try moveFilesToApplicationSupport(batch)
        batches.append(moved)
        try FileManager.default.removeItem(at: file)
      } catch {
        continue
      }
    }
    return batches
  }

  private static func inboxDirectories(
    appGroupIdentifier: String
  ) throws -> (root: URL, batches: URL, files: URL) {
    guard let group = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ) else {
      throw CocoaError(.fileNoSuchFile)
    }
    let root = group.appendingPathComponent(directoryName, isDirectory: true)
    let batches = root.appendingPathComponent(batchesDirectoryName, isDirectory: true)
    let files = root.appendingPathComponent(filesDirectoryName, isDirectory: true)
    try FileManager.default.createDirectory(at: batches, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
    return (root, batches, files)
  }

  private static func moveFilesToApplicationSupport(
    _ batch: [String: Any]
  ) throws -> [String: Any] {
    guard let rawItems = batch["items"] as? [[String: Any]] else {
      throw CocoaError(.fileReadCorruptFile)
    }
    let support = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ).appendingPathComponent(directoryName, isDirectory: true)
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    let items = try rawItems.map { item -> [String: Any] in
      guard item["type"] as? String == "file",
            let path = item["path"] as? String else {
        return item
      }
      let source = URL(fileURLWithPath: path)
      let destination = support.appendingPathComponent(
        "\(UUID().uuidString)-\(source.lastPathComponent)"
      )
      try FileManager.default.moveItem(at: source, to: destination)
      var mutable = item
      mutable["path"] = destination.path
      return mutable
    }
    var result = batch
    result["items"] = items
    return result
  }
}
