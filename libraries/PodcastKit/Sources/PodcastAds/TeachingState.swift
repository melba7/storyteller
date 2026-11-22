// LOFI-FORK: which of the Mac's files the phone has installed, and what it says about them (see FORK.md).
import Foundation

/// Which teaching files are installed, with the SHA-256 of each and when it came, kept as
/// `state.json` in the teaching folder.
public struct TeachingState: Codable, Sendable, Equatable {
  public static let fileName = "state.json"

  public struct Installed: Codable, Sendable, Equatable {
    public var sha256: String
    /// Milliseconds since 1970.
    public var installedAt: Double

    public init(sha256: String, installedAt: Double) {
      self.sha256 = sha256
      self.installedAt = installedAt
    }
  }

  public var files: [String: Installed]

  public init(files: [String: Installed] = [:]) { self.files = files }

  public mutating func record(name: String, sha256: String, at date: Date) {
    files[name] = Installed(sha256: sha256, installedAt: (date.timeIntervalSince1970 * 1000).rounded())
  }

  /// The state saved in `folder`, or an empty one when there is none or it cannot be read.
  public static func load(from folder: URL) -> TeachingState {
    guard let data = try? Data(contentsOf: folder.appendingPathComponent(fileName)),
      let state = try? JSONDecoder().decode(TeachingState.self, from: data)
    else { return TeachingState() }
    return state
  }

  public func save(to folder: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try encoder.encode(self).write(to: folder.appendingPathComponent(Self.fileName), options: .atomic)
  }

  /// The text of `getTeachingState()`:
  /// `{"files": {"<name>": {"sha256", "installedAt"}}, "model": {"writtenAt", "episodes",
  /// "precision", "recall"} | null, "library": <entries>, "habits": <shows>, "sounds": <sounds>}`.
  /// The sounds are counted by the caller, as this module cannot see the sound library.
  public func json(model: TeachingFiles.ModelInfo?, library: Int, habits: Int, sounds: Int) -> String {
    func number(_ value: Double?) -> Any { value ?? NSNull() }
    var modelValue: Any = NSNull()
    if let model {
      modelValue = [
        "writtenAt": number(model.writtenAt), "episodes": model.episodes.map { $0 as Any } ?? NSNull(),
        "precision": number(model.precision), "recall": number(model.recall),
      ]
    }
    let installed = files.mapValues { ["sha256": $0.sha256, "installedAt": $0.installedAt] as [String: Any] }
    let value: [String: Any] = [
      "files": installed, "model": modelValue, "library": library, "habits": habits, "sounds": sounds,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
      let text = String(data: data, encoding: .utf8)
    else { return "{}" }
    return text
  }
}
