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
  ///
  /// With a `placing` (the phone's) only the model's ads that may skip on this show go into the
  /// files, named after the model, and the ones that only ask are left in `placing.asked` for the
  /// questions. With none, every ad is kept as it is.
  public static func run(
    transcript: Transcript, detector: AdDetector, store: AdsStore, osVersion: String,
    overlap: Double = AdChunker.overlap, placing: ModelPlacing? = nil,
    progress: @Sendable (Int, Int) -> Void = { _, _ in },
    shouldContinue: @Sendable () -> Bool = { true }
  ) async throws -> AdsOutcome {
    // A prepared file is the Mac's marks on that very copy: the model is not asked about it.
    if let prepared = store.load(detector: detector.name), prepared.isPrepared {
      return .finished(prepared)
    }
    let pieces = AdChunker.pieces(
      of: AdChunker.number(transcript.lines), tokenBudget: detector.tokenBudget, overlap: overlap)
    progress(0, pieces.count)
    @Sendable func kept(_ ranges: [AdRange]) -> [FoundAd] {
      let ads = AdCleanup.run(ranges: ranges, transcript: transcript)
      return placing?.keep(ads) ?? ads
    }
    // Each piece that is asked is saved as a partial file at once, so the player can skip the
    // ads found so far while the rest is still being asked.
    let checkpoint: @Sendable ([AdRange], Double) -> Void = { ranges, covered in
      var partial = AdsFile(
        sha256: store.sha256, detector: detector.name, detectorVersion: detector.version,
        osVersion: osVersion, duration: transcript.duration,
        ads: kept(ranges), coveredUntil: covered)
      partial.undone = store.loadPartial(detector: detector.name)?.undone ?? []
      try? store.savePartial(partial)
    }
    guard
      let result = try await answers(
        for: pieces, growing: nil, detector: detector, store: store, shouldContinue: shouldContinue,
        progress: progress, checkpoint: checkpoint)
    else { return .stopped }
    var file = AdsFile(
      sha256: store.sha256, detector: detector.name, detectorVersion: detector.version,
      osVersion: osVersion, duration: transcript.duration, ads: kept(result.ranges),
      refusedPieces: result.refused > 0 ? result.refused : nil)
    // Skips the listener took back while only the partial file existed stay undone.
    file.undone = store.undoneSoFar(detector: detector.name)
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
  ///
  /// With `limit`, only the first `limit` seconds of the transcript are looked at (the head of an
  /// episode that is not playing). The answer is kept like any growing piece's, so the later
  /// passes carry on from it.
  ///
  /// With a `placing`, only the model's ads that may skip are kept, as in `run`; a partial pass
  /// makes no questions.
  public static func runPartial(
    partial full: PartialTranscript, detector: AdDetector, store: AdsStore, osVersion: String,
    margin: Double = AdChunker.partialMargin, overlap: Double = AdChunker.overlap,
    limit: Double? = nil, placing: ModelPlacing? = nil,
    shouldContinue: @Sendable () -> Bool = { true }
  ) async throws -> AdsOutcome {
    if let prepared = store.load(detector: detector.name), prepared.isPrepared {
      return .finished(prepared)
    }
    var partial = full
    if let limit, partial.reached > limit {
      partial.reached = limit
      partial.words = partial.words.filter { $0.end <= limit }
    }
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
        shouldContinue: shouldContinue, progress: { _, _ in }, checkpoint: nil)
    else { return .stopped }
    let covered = max(pieces.last?.end ?? 0, result.growingEnd ?? 0)
    let transcript = Transcript(
      identity: partial.identity, duration: partial.duration, lines: lines, words: partial.words)
    let found = AdCleanup.run(ranges: result.ranges, transcript: transcript)
    var file = AdsFile(
      sha256: store.sha256, detector: detector.name, detectorVersion: detector.version,
      osVersion: osVersion, duration: partial.duration, ads: placing?.keep(found) ?? found,
      coveredUntil: covered, refusedPieces: result.refused > 0 ? result.refused : nil)
    let existing = store.loadPartial(detector: detector.name)
    file.undone = existing?.undone ?? []
    // Ads saved by someone else (the stream's first minute) stay unless they lie wholly inside
    // the stretch this run asked about, where this run's answers win. One that runs over the
    // stretch's edge stays, and joins a new answer that it overlaps.
    let from = min(pieces.first?.start ?? .infinity, growing?.start ?? .infinity)
    let kept = (existing?.ads ?? []).filter { !($0.start >= from && $0.end <= covered) }
    file.ads = AdHeadRules.merge(file.ads + kept, touching: -0.001)
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
    store: AdsStore, shouldContinue: @Sendable () -> Bool, progress: @Sendable (Int, Int) -> Void,
    checkpoint: (@Sendable ([AdRange], Double) -> Void)?
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
        try await ask(detector, piece, into: &kept, splits: refusalSplits)
        take(kept.answers[piece.key] ?? [], key: piece.key)
        // The piece is whole now; the answers for its growing versions are no use.
        kept.dropShorter(than: piece)
        try? store.saveProgress(kept)
        checkpoint?(result.ranges, piece.end)
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
        // A growing piece is asked again each time it has grown, so a refusal is not asked in
        // halves here (that would multiply the questions); once it is whole, it is.
        try await ask(detector, growing, into: &kept, splits: 0)
        kept.dropShorter(than: growing)
        try? store.saveProgress(kept)
        take(kept.answers[key] ?? [], key: key)
        result.growingEnd = growing.end
      }
    }
    return result
  }

  /// How many times a refused piece is cut in halves: the piece into two, and each of those
  /// into two. So a refused piece costs at most six more questions, and a leaf is a quarter of
  /// the piece.
  static let refusalSplits = 2

  /// Asks about a piece (or its halves when it is too long or refused) and keeps the answer
  /// under the piece's key. A piece counts as refused, and is noted in `refused`, only when a
  /// part of it that could not be cut any further was refused; any other failure is thrown, so
  /// the piece is asked again next time.
  private static func ask(
    _ detector: AdDetector, _ piece: TranscriptPiece, into kept: inout AdProgress, splits: Int
  ) async throws {
    var refused = false
    let answer = try await ask(detector, piece, refused: &refused, splits: splits)
    kept.answers[piece.key] = answer
    if refused { kept.refused = (kept.refused ?? []) + [piece.key] }
  }

  /// A refused piece is asked again in halves while `splits` allows and the piece holds at
  /// least `AdChunker.growingMinimum` seconds. The halves keep the line numbers of the whole
  /// transcript, are asked with the same prompt and are cleaned by the same `AdCleanup`, so an
  /// ad that the cut runs through can only come out shorter.
  private static func ask(
    _ detector: AdDetector, _ piece: TranscriptPiece, refused: inout Bool, splits: Int
  ) async throws -> [AdRange] {
    do {
      return try await detector.findAds(in: piece)
    } catch AdDetectorError.refused {
      guard splits > 0, piece.end - piece.start >= AdChunker.growingMinimum,
        let (first, second) = AdChunker.split(piece)
      else {
        refused = true
        return []
      }
      let before = try await ask(detector, first, refused: &refused, splits: splits - 1)
      return try await before + ask(detector, second, refused: &refused, splits: splits - 1)
    } catch AdDetectorError.tooLong {
      guard let (first, second) = AdChunker.split(piece) else {
        throw AdDetectorError.failed("A single line does not fit the model.")
      }
      let before = try await ask(detector, first, refused: &refused, splits: splits)
      return try await before + ask(detector, second, refused: &refused, splits: splits)
    }
  }
}
