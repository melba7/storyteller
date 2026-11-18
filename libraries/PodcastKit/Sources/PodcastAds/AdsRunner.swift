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
      let result = try await answers(
        for: pieces, growing: nil, detector: detector, store: store, shouldContinue: shouldContinue,
        progress: progress)
    else { return .stopped }
    var file = AdsFile(
      sha256: store.sha256, detector: detector.name, detectorVersion: detector.version,
      osVersion: osVersion, duration: transcript.duration,
      ads: AdCleanup.run(ranges: result.ranges, transcript: transcript),
      refusedPieces: result.refused > 0 ? result.refused : nil)
    // Skips the listener took back while only the partial file existed stay undone.
    file.undone = store.loadPartial(detector: detector.name)?.undone ?? []
    try store.save(file)
    store.removeScratch(detector: detector.name)
    return .finished(file)
  }

  /// Asks the pieces of a partial transcript that are safe to ask now and have no kept answer,
  /// then saves a partial ads file over the answers so far (`coveredUntil` says how far it
  /// reaches), for the player to skip from. Nothing is saved when nothing is safe yet.
  ///
  /// Besides the whole pieces, the growing last piece is asked once it holds
  /// `AdChunker.growingMinimum` seconds of lines, and again each time it has grown by
  /// `AdChunker.growingStep` seconds. Its newest answer replaces the older ones for the same
  /// start, so an ad is neither doubled nor kept when the longer answer dropped it.
  public static func runPartial(
    partial: PartialTranscript, detector: AdDetector, store: AdsStore, osVersion: String,
    margin: Double = AdChunker.partialMargin, overlap: Double = AdChunker.overlap,
    shouldContinue: @Sendable () -> Bool = { true }
  ) async throws -> AdsOutcome {
    let lines = LineRule.lines(from: partial.words)
    let numbered = AdChunker.number(lines)
    let pieces = AdChunker.safePieces(
      of: numbered, tokenBudget: detector.tokenBudget, reached: partial.reached, margin: margin,
      overlap: overlap)
    let growing = AdChunker.growingPiece(
      of: numbered, tokenBudget: detector.tokenBudget, reached: partial.reached, margin: margin,
      overlap: overlap)
    guard pieces.last != nil || growing != nil else { return .stopped }
    guard
      let result = try await answers(
        for: pieces, growing: growing, detector: detector, store: store,
        shouldContinue: shouldContinue, progress: { _, _ in })
    else { return .stopped }
    let covered = max(pieces.last?.end ?? 0, result.growingEnd ?? 0)
    let transcript = Transcript(
      identity: partial.identity, duration: partial.duration, lines: lines, words: partial.words)
    var file = AdsFile(
      sha256: store.sha256, detector: detector.name, detectorVersion: detector.version,
      osVersion: osVersion, duration: partial.duration,
      ads: AdCleanup.run(ranges: result.ranges, transcript: transcript), coveredUntil: covered,
      refusedPieces: result.refused > 0 ? result.refused : nil)
    file.undone = store.loadPartial(detector: detector.name)?.undone ?? []
    try store.savePartial(file)
    return .finished(file)
  }

  /// What the pieces said: the ranges, how many pieces the model refused, and where the
  /// growing piece's answer reaches.
  private struct Answers {
    var ranges: [AdRange] = []
    var refused = 0
    var growingEnd: Double?
  }

  /// The answers for all the pieces in order, asking only those without a kept answer and
  /// keeping each new answer at once, then the growing piece's. Nil when stopped between
  /// pieces.
  private static func answers(
    for pieces: [TranscriptPiece], growing: TranscriptPiece?, detector: AdDetector,
    store: AdsStore, shouldContinue: @Sendable () -> Bool, progress: @Sendable (Int, Int) -> Void
  ) async throws -> Answers? {
    var kept = store.loadProgress(detector: detector.name, version: detector.version)
    var result = Answers()
    func take(_ answer: [AdRange], key: String) {
      result.ranges += answer
      if kept.refused?.contains(key) == true { result.refused += 1 }
    }
    for (index, piece) in pieces.enumerated() {
      if let answer = kept.answers[piece.key] {
        take(answer, key: piece.key)
      } else {
        guard shouldContinue(), !Task.isCancelled else { return nil }
        try await ask(detector, piece, into: &kept)
        take(kept.answers[piece.key] ?? [], key: piece.key)
        // The piece is whole now; the answers for its growing versions are no use.
        kept.dropShorter(than: piece)
        try? store.saveProgress(kept)
      }
      progress(index + 1, pieces.count)
    }
    if let growing {
      let key = growing.key
      if kept.answers[key] != nil {
        take(kept.answers[key] ?? [], key: key)
        result.growingEnd = growing.end
      } else if let older = kept.growingAnswer(for: growing),
        growing.end - older.end < AdChunker.growingStep
      {
        take(older.ranges, key: older.key)
        result.growingEnd = older.end
      } else {
        guard shouldContinue(), !Task.isCancelled else { return nil }
        try await ask(detector, growing, into: &kept)
        kept.dropShorter(than: growing)
        try? store.saveProgress(kept)
        take(kept.answers[key] ?? [], key: key)
        result.growingEnd = growing.end
      }
    }
    return result
  }

  /// Asks about a piece (or its halves when it is too long) and keeps the answer under the
  /// piece's key. A refusal by the model counts as no ads and is noted in `refused`; any other
  /// failure is thrown, so the piece is asked again next time.
  private static func ask(
    _ detector: AdDetector, _ piece: TranscriptPiece, into kept: inout AdProgress
  ) async throws {
    var refused = false
    let answer = try await ask(detector, piece, refused: &refused)
    kept.answers[piece.key] = answer
    if refused { kept.refused = (kept.refused ?? []) + [piece.key] }
  }

  private static func ask(
    _ detector: AdDetector, _ piece: TranscriptPiece, refused: inout Bool
  ) async throws -> [AdRange] {
    do {
      return try await detector.findAds(in: piece)
    } catch AdDetectorError.refused {
      refused = true
      return []
    } catch AdDetectorError.tooLong {
      guard let (first, second) = AdChunker.split(piece) else {
        throw AdDetectorError.failed("A single line does not fit the model.")
      }
      let before = try await ask(detector, first, refused: &refused)
      return try await before + ask(detector, second, refused: &refused)
    }
  }
}
