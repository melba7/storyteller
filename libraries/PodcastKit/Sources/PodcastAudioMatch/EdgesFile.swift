// LOFI-FORK: `edges.json` in the teaching folder, the change peaks of each shelf episode, found
// once, so that a scorecard row can snap found edges onto them without the audio (see FORK.md and
// EdgeSound.swift). Foundation only.
import Foundation

struct EdgesFile: Equatable {
  static let fileName = "edges.json"
  /// A file bigger than this is not read (it is damaged or not ours).
  private static let readLimit = 64 * 1024 * 1024

  struct Entry: Codable, Equatable {
    var seconds: Double
    /// Each peak as `[time in seconds, strength]`, in order of time.
    var peaks: [[Double]]

    init(seconds: Double, peaks: [EdgePeak]) {
      self.seconds = seconds
      self.peaks = peaks.map { [$0.time, (Double($0.strength) * 100).rounded() / 100] }
    }

    var edgePeaks: [EdgePeak] {
      peaks.compactMap { $0.count == 2 ? EdgePeak(time: $0[0], strength: Float($0[1])) : nil }
    }
  }

  private struct Root: Codable {
    var version: Int
    var finder: Int
    var episodes: [String: Entry]
  }

  /// The peaks of each episode, by the episode's id.
  var episodes: [String: Entry] = [:]

  /// The file in `folder`. One that is not there is an empty file and no problem. One that cannot be
  /// used (not JSON, another version, made by another version of the score, `EdgeSound.version`, or
  /// with an entry that does not decode) is an empty file and one plain line saying so.
  static func load(in folder: URL) -> (file: EdgesFile, problem: String?) {
    let url = folder.appendingPathComponent(fileName)
    guard FileManager.default.fileExists(atPath: url.path) else { return (EdgesFile(), nil) }
    let ignored =
      "\(fileName) is damaged, not a version 1 file or made by another version of the score (now version \(EdgeSound.version)), so it is ignored and made again."
    guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
      size <= readLimit, let data = try? Data(contentsOf: url),
      let root = try? JSONDecoder().decode(Root.self, from: data), root.version == 1,
      root.finder == EdgeSound.version,
      root.episodes.values.allSatisfy({
        $0.seconds.isFinite && $0.seconds >= 0 && $0.peaks.allSatisfy { $0.count == 2 }
      })
    else { return (EdgesFile(), ignored) }
    return (EdgesFile(episodes: root.episodes), nil)
  }

  /// Writes the file in one piece (a reader never sees half of it).
  func write(in folder: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(Root(version: 1, finder: EdgeSound.version, episodes: episodes))
    try data.write(to: folder.appendingPathComponent(Self.fileName), options: .atomic)
  }
}
