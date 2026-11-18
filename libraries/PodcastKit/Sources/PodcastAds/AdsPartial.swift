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

extension TranscriptPiece {
  /// The numbers inside a `key`: the first line number and the start and end in milliseconds,
  /// or nil for a key of another shape.
  static func keyParts(_ key: String) -> (first: Int, startMilli: Int, endMilli: Int)? {
    let parts = key.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 5, let first = Int(parts[0]), let start = Int(parts[2]),
      let end = Int(parts[3])
    else { return nil }
    return (first, start, end)
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

  /// A growing last piece has to hold at least this many seconds of lines to be asked.
  public static let growingMinimum = 60.0
  /// A growing last piece is asked again only when it has grown by this many seconds since its
  /// last answer (or when it has become a whole piece, which is always asked).
  public static let growingStep = 120.0

  /// The last piece of a partial transcript, which is still growing, cut to the lines that end
  /// at least `margin` seconds before `reached`. Nil while it holds less than `minimum` seconds
  /// of lines, or when it adds nothing to the piece before it.
  public static func growingPiece(
    of lines: [NumberedLine], tokenBudget: Int, reached: Double, margin: Double = partialMargin,
    overlap: Double = overlap, minimum: Double = growingMinimum
  ) -> TranscriptPiece? {
    let all = pieces(of: lines, tokenBudget: tokenBudget, overlap: overlap)
    guard let last = all.last else { return nil }
    let piece = TranscriptPiece(lines: Array(last.lines.prefix { $0.end <= reached - margin }))
    guard !piece.lines.isEmpty, piece.end - piece.start >= minimum else { return nil }
    if all.count > 1, piece.end <= all[all.count - 2].end { return nil }
    return piece
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
  /// The keys of the pieces the model refused. Their answer is "no ads"; they are listed so a
  /// result can say how many pieces were not read.
  public var refused: [String]?

  public init(sha256: String, detector: String, detectorVersion: String) {
    self.sha256 = sha256
    self.detector = detector
    self.detectorVersion = detectorVersion
  }
}

extension AdProgress {
  /// The longest answer kept for a growing piece that starts where `piece` starts: its key,
  /// where it ends and what it said. Nil when there is none.
  func growingAnswer(for piece: TranscriptPiece) -> (key: String, end: Double, ranges: [AdRange])? {
    let best = answers.keys.compactMap { key -> (String, Int)? in
      guard let parts = TranscriptPiece.keyParts(key), sameStart(parts, piece) else { return nil }
      return (key, parts.endMilli)
    }.max { $0.1 < $1.1 }
    guard let best, let ranges = answers[best.0] else { return nil }
    return (best.0, Double(best.1) / 1000, ranges)
  }

  /// Forgets the answers for other pieces that start where `piece` starts: they are shorter
  /// versions of it, and its own answer replaces them.
  mutating func dropShorter(than piece: TranscriptPiece) {
    let own = piece.key
    for key in answers.keys where key != own {
      if let parts = TranscriptPiece.keyParts(key), sameStart(parts, piece) {
        answers[key] = nil
        refused?.removeAll { $0 == key }
      }
    }
  }

  private func sameStart(
    _ parts: (first: Int, startMilli: Int, endMilli: Int), _ piece: TranscriptPiece
  ) -> Bool {
    parts.first == piece.firstNumber && parts.startMilli == Int((piece.start * 1000).rounded())
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

  /// The text of `best`, as saved, for the app to read: the ads list and the seek bar show the
  /// ads the player is already skipping.
  public func bestJSON(detector: String) -> String? {
    if let final = json(detector: detector) { return final }
    guard loadPartial(detector: detector) != nil,
      let data = try? Data(contentsOf: scratchURL(detector, "partial"))
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// Removes the progress and partial files, once the final file is saved.
  public func removeScratch(detector: String) {
    for kind in ["progress", "partial"] {
      try? FileManager.default.removeItem(at: scratchURL(detector, kind))
    }
  }
}
