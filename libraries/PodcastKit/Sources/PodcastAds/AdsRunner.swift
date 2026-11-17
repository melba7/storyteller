// LOFI-FORK: finds the ads in a whole transcript (see FORK.md).
import Foundation
import PodcastTranscripts

public enum AdsOutcome: Sendable, Equatable {
  case finished(AdsFile)
  /// Stopped between pieces. No final file is saved; the answers so far are kept in the
  /// progress file, so the next run asks only the rest.
  case stopped
}

public enum AdsRunner {
  /// Splits the transcript into pieces for the detector, asks it about each one (except those
  /// whose answer a partial run already kept), cleans up the answers and saves the file. A
  /// piece that does not fit the model is split in two and asked again. `progress` is called
  /// with how many pieces are done and how many there are. The progress and partial files are
  /// removed once the final file is saved.
  public static func run(
    transcript: Transcript, detector: AdDetector, store: AdsStore, osVersion: String,
    overlap: Double = AdChunker.overlap, progress: @Sendable (Int, Int) -> Void = { _, _ in },
    shouldContinue: @Sendable () -> Bool = { true }
  ) async throws -> AdsOutcome {
    let pieces = AdChunker.pieces(
      of: AdChunker.number(transcript.lines), tokenBudget: detector.tokenBudget, overlap: overlap)
    progress(0, pieces.count)
    guard
      let ranges = try await answers(
        for: pieces, detector: detector, store: store, shouldContinue: shouldContinue,
        progress: progress)
    else { return .stopped }
    var file = AdsFile(
      sha256: store.sha256, detector: detector.name, detectorVersion: detector.version,
      osVersion: osVersion, duration: transcript.duration,
      ads: AdCleanup.run(ranges: ranges, transcript: transcript))
    // Skips the listener took back while only the partial file existed stay undone.
    file.undone = store.loadPartial(detector: detector.name)?.undone ?? []
    try store.save(file)
    store.removeScratch(detector: detector.name)
    return .finished(file)
  }

  /// Asks the pieces of a partial transcript that are safe to ask now and have no kept answer,
  /// then saves a partial ads file over the answers so far (`coveredUntil` says how far it
  /// reaches), for the player to skip from. Nothing is saved when no piece is safe yet.
  public static func runPartial(
    partial: PartialTranscript, detector: AdDetector, store: AdsStore, osVersion: String,
    margin: Double = AdChunker.partialMargin, overlap: Double = AdChunker.overlap,
    shouldContinue: @Sendable () -> Bool = { true }
  ) async throws -> AdsOutcome {
    let lines = LineRule.lines(from: partial.words)
    let pieces = AdChunker.safePieces(
      of: AdChunker.number(lines), tokenBudget: detector.tokenBudget, reached: partial.reached,
      margin: margin, overlap: overlap)
    guard let covered = pieces.last?.end else { return .stopped }
    guard
      let ranges = try await answers(
        for: pieces, detector: detector, store: store, shouldContinue: shouldContinue,
        progress: { _, _ in })
    else { return .stopped }
    let transcript = Transcript(
      identity: partial.identity, duration: partial.duration, lines: lines, words: partial.words)
    var file = AdsFile(
      sha256: store.sha256, detector: detector.name, detectorVersion: detector.version,
      osVersion: osVersion, duration: partial.duration,
      ads: AdCleanup.run(ranges: ranges, transcript: transcript), coveredUntil: covered)
    file.undone = store.loadPartial(detector: detector.name)?.undone ?? []
    try store.savePartial(file)
    return .finished(file)
  }

  /// The answers for all the pieces in order, asking only those without a kept answer and
  /// keeping each new answer at once. Nil when stopped between pieces.
  private static func answers(
    for pieces: [TranscriptPiece], detector: AdDetector, store: AdsStore,
    shouldContinue: @Sendable () -> Bool, progress: @Sendable (Int, Int) -> Void
  ) async throws -> [AdRange]? {
    var kept = store.loadProgress(detector: detector.name, version: detector.version)
    var ranges: [AdRange] = []
    for (index, piece) in pieces.enumerated() {
      if let answer = kept.answers[piece.key] {
        ranges += answer
      } else {
        guard shouldContinue(), !Task.isCancelled else { return nil }
        let answer = try await ask(detector, piece)
        kept.answers[piece.key] = answer
        try? store.saveProgress(kept)
        ranges += answer
      }
      progress(index + 1, pieces.count)
    }
    return ranges
  }

  /// The detector's answer for a piece, or for its halves when the piece is too long.
  private static func ask(_ detector: AdDetector, _ piece: TranscriptPiece) async throws -> [AdRange] {
    do {
      return try await detector.findAds(in: piece)
    } catch AdDetectorError.tooLong {
      guard let (first, second) = AdChunker.split(piece) else {
        throw AdDetectorError.failed("A single line does not fit the model.")
      }
      return try await ask(detector, first) + ask(detector, second)
    }
  }
}
