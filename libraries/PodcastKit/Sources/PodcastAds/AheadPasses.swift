// LOFI-FORK: which of the Mac's marks the ahead finder has used for each episode (see FORK.md and
// AheadPass.swift). Foundation only.
import Foundation

/// For each episode, the `marked` time of the marks the ahead finder last looked at it with. The
/// finder's pass over an episode whose ads are final already is not repeated at every start, and it
/// runs again when marks that are newer come. Kept as `ahead-passes.json` beside the other teaching
/// files; a file that cannot be read is an empty record, and the pass is then made once more.
public struct AheadPasses: Codable, Sendable, Equatable {
  public static let fileName = "ahead-passes.json"
  /// The most episodes kept (the Mac marks 8 a night and the marks are kept 14 days); the ones with
  /// the oldest marks go first.
  public static let most = 500

  public private(set) var stamps: [String: Double] = [:]

  public init() {}

  /// Whether the episode needs a pass with marks made at `marked`: it has had none, or only older
  /// marks. Marks with no real time are never news.
  public func needs(episode: String, marked: Double) -> Bool {
    guard marked.isFinite else { return false }
    guard let done = stamps[episode] else { return true }
    return marked > done
  }

  /// Notes that the episode was looked at with marks made at `marked`. An older time never
  /// replaces a newer one.
  public mutating func record(episode: String, marked: Double) {
    guard marked.isFinite, !episode.isEmpty else { return }
    stamps[episode] = max(stamps[episode] ?? marked, marked)
    while stamps.count > Self.most,
      let oldest = stamps.min(by: { ($0.value, $0.key) < ($1.value, $1.key) })
    {
      stamps[oldest.key] = nil
    }
  }

  /// The record saved in `folder`, or an empty one when there is none or it cannot be read.
  public static func load(from folder: URL) -> AheadPasses {
    guard let data = try? Data(contentsOf: folder.appendingPathComponent(fileName)),
      data.count <= TeachingFiles.maxBytes,
      let passes = try? JSONDecoder().decode(AheadPasses.self, from: data)
    else { return AheadPasses() }
    return passes
  }

  public func save(to folder: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try encoder.encode(self).write(
      to: folder.appendingPathComponent(Self.fileName), options: .atomic)
  }
}
