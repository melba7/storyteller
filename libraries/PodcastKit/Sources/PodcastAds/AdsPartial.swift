// LOFI-FORK: ads found while the transcript is still growing (see FORK.md).
import Foundation
import PodcastTranscripts

extension TranscriptPiece {
  /// A name for the piece that stays the same between a partial transcript and the whole
  /// one: its first and last line numbers, its times and a hash of its text. An answer saved
  /// under it is for exactly these lines.
  public var key: String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in lines.map(\.text).joined(separator: "\n").utf8 {
      hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
    }
    let milli = { (seconds: Double) in Int((seconds * 1000).rounded()) }
    return "\(firstNumber)-\(lastNumber)-\(milli(start))-\(milli(end))-\(String(hash, radix: 16))"
  }
}

extension AdChunker {
  /// How far before the edge of a partial transcript a piece has to end to be asked, so the
  /// words near the edge (which can still change) are left out.
  public static let partialMargin = 20.0

  /// The pieces of a partial transcript that can be asked now. The pieces are cut greedily
  /// from the start, so every piece but the last is the same in the whole transcript; of
  /// those, only the ones that end at least `margin` seconds before `reached`.
  public static func safePieces(
    of lines: [NumberedLine], tokenBudget: Int, reached: Double, margin: Double = partialMargin,
    overlap: Double = overlap
  ) -> [TranscriptPiece] {
    let all = pieces(of: lines, tokenBudget: tokenBudget, overlap: overlap)
    return Array(all.dropLast().prefix { $0.end <= reached - margin })
  }
}

/// What a detector answered for each piece so far, saved as
/// `<sha256>.ads.<detector>.progress.json`, so a later run does not ask again.
public struct AdProgress: Codable, Sendable, Equatable {
  public var sha256: String
  public var detector: String
  public var detectorVersion: String
  /// The answers by `TranscriptPiece.key`.
  public var answers: [String: [AdRange]] = [:]

  public init(sha256: String, detector: String, detectorVersion: String) {
    self.sha256 = sha256
    self.detector = detector
    self.detectorVersion = detectorVersion
  }
}

extension AdsStore {
  private func scratchURL(_ detector: String, _ kind: String) -> URL {
    let name = url(detector: detector).deletingPathExtension().lastPathComponent
    return folder.appendingPathComponent("\(name).\(kind).json")
  }

  public func saveProgress(_ progress: AdProgress) throws {
    try Self.encoder.encode(progress).write(
      to: scratchURL(progress.detector, "progress"), options: .atomic)
  }

  /// The answers kept for this detector and version, or none (empty) when there is no file, it
  /// cannot be read, or it is for another file, detector or version.
  public func loadProgress(detector: String, version: String) -> AdProgress {
    let fresh = AdProgress(sha256: sha256, detector: detector, detectorVersion: version)
    guard let data = try? Data(contentsOf: scratchURL(detector, "progress")),
      let saved = try? JSONDecoder().decode(AdProgress.self, from: data),
      saved.sha256 == sha256, saved.detector == detector, saved.detectorVersion == version
    else { return fresh }
    return saved
  }

  /// Saves what a partial run found so far, as `<sha256>.ads.<detector>.partial.json`.
  public func savePartial(_ file: AdsFile) throws {
    try Self.encoder.encode(file).write(to: scratchURL(file.detector, "partial"), options: .atomic)
  }

  /// The partial result, or nil as for `load`.
  public func loadPartial(detector: String) -> AdsFile? {
    guard let data = try? Data(contentsOf: scratchURL(detector, "partial")),
      let file = try? JSONDecoder().decode(AdsFile.self, from: data),
      file.version == AdsFile.currentVersion, file.sha256 == sha256
    else { return nil }
    return file
  }

  /// What the player reads: the final file, else the partial one.
  public func best(detector: String) -> AdsFile? {
    load(detector: detector) ?? loadPartial(detector: detector)
  }

  /// Removes the progress and partial files, once the final file is saved.
  public func removeScratch(detector: String) {
    for kind in ["progress", "partial"] {
      try? FileManager.default.removeItem(at: scratchURL(detector, kind))
    }
  }
}
