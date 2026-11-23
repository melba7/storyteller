// LOFI-FORK: the cache of Apple's on-device model's answers for the teaching episodes, asked on
// the Mac and read by the scorecard (see FORK.md). It holds times, kinds and how sure the model
// was, never any transcript text. Foundation only.
import Foundation

public struct AppleAnswers: Codable, Sendable, Equatable {
  public static let currentVersion = 1
  public static let fileName = "apple-model.json"

  /// One ad as the file keeps it.
  public struct Ad: Codable, Sendable, Equatable {
    public var start: Double
    public var end: Double
    public var kind: AdKind
    public var confidence: AdConfidence

    public init(start: Double, end: Double, kind: AdKind, confidence: AdConfidence) {
      self.start = start
      self.end = end
      self.kind = kind
      self.confidence = confidence
    }
  }

  /// What the model said about one episode.
  public struct Answer: Codable, Sendable, Equatable {
    public var ads: [Ad]
    public var refusedPieces: Int
    /// How long the asking took.
    public var seconds: Double

    public init(ads: [Ad], refusedPieces: Int, seconds: Double) {
      self.ads = ads
      self.refusedPieces = refusedPieces
      self.seconds = seconds
    }
  }

  public var version: Int
  /// The detector's name and version, so answers of another model are never mixed in.
  public var model: String
  public var episodes: [String: Answer]

  public init(model: String, episodes: [String: Answer] = [:]) {
    version = Self.currentVersion
    self.model = model
    self.episodes = episodes
  }

  /// The answer for an episode as ads the scorecard can join with the finders'.
  public func ads(for id: String) -> [FoundAd]? {
    episodes[id]?.ads.filter { $0.start.isFinite && $0.end.isFinite && $0.end > $0.start }.map {
      FoundAd(
        start: $0.start, end: $0.end, kind: $0.kind, advertiser: "", confidence: $0.confidence,
        firstWords: "", source: "apple-model")
    }
  }

  /// The answers by episode id, for the episodes among `ids` that have one.
  public func ads(among ids: [String]) -> [String: [FoundAd]] {
    var found: [String: [FoundAd]] = [:]
    for id in ids { if let ads = ads(for: id) { found[id] = ads } }
    return found
  }

  /// The file in `folder`: nil when there is none, a plain sentence when it cannot be used. A
  /// damaged file is never read as an empty one, because the asking would start from nothing.
  public static func load(in folder: URL) -> Result<AppleAnswers?, TeachingFolderError> {
    let url = folder.appendingPathComponent(fileName)
    guard FileManager.default.fileExists(atPath: url.path) else { return .success(nil) }
    guard let data = try? Data(contentsOf: url),
      let saved = try? JSONDecoder().decode(AppleAnswers.self, from: data),
      saved.version == currentVersion
    else {
      return .failure(
        TeachingFolderError(
          message:
            "\(fileName) in \(folder.path) is damaged or not of this version. Move it away to start again; nothing was changed."
        ))
    }
    return .success(saved)
  }

  /// Writes the file whole at once, so a run that is stopped leaves the last good one.
  public func save(in folder: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    try encoder.encode(self).write(
      to: folder.appendingPathComponent(Self.fileName), options: .atomic)
  }
}
