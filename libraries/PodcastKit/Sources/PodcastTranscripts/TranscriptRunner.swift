// LOFI-FORK: the podcast transcripts' piece by piece run (see FORK.md).
import Foundation

/// Turns a stretch of an audio file into timed words. The Apple one is in PodcastSpeech;
/// the tests use a fake.
public protocol PieceRecogniser: Sendable {
  var name: String { get }
  var version: String { get }
  /// The system's version, saved with the transcript.
  var osVersion: String { get }
  /// Makes sure the language can be transcribed (downloading what it needs the first time)
  /// and answers the locale identifier to use. Throws `TranscriptError.notSupported`.
  func prepare(locale: String) async throws -> String
  func duration(of file: URL) throws -> Double
  /// The words said between `from` and `to` seconds, with times counted from the start of
  /// the file (not of the piece).
  func recognise(file: URL, locale: String, from: Double, to: Double) async throws -> [TranscriptWord]
}

public enum RunOutcome: Sendable, Equatable {
  case finished(Transcript)
  /// Stopped between pieces, with the partial file saved.
  case paused(reached: Double)
}

public enum TranscriptRunner {
  /// Transcribes `audio` a piece at a time, saving a partial file after each piece and
  /// carrying on from an earlier one. `shouldContinue` is asked before each piece; a
  /// cancelled task stops too. When the last piece is done the final file is written and the
  /// partial one removed.
  public static func run(
    audio: URL, sha256: String, locale requested: String, recogniser: PieceRecogniser,
    store: TranscriptStore, pieceSeconds: Double = Pieces.seconds, overlap: Double = Pieces.overlap,
    progress: @Sendable (Int) -> Void = { _ in }, shouldContinue: @Sendable () -> Bool = { true }
  ) async throws -> RunOutcome {
    let locale = try await recogniser.prepare(locale: requested)
    let duration: Double
    do { duration = try recogniser.duration(of: audio) } catch {
      throw TranscriptError.failed("The audio could not be read.")
    }
    guard duration > 0 else { throw TranscriptError.failed("The audio is empty.") }

    let identity = TranscriptIdentity(
      locale: locale, recogniser: recogniser.name, recogniserVersion: recogniser.version,
      osVersion: recogniser.osVersion, sha256: sha256)
    var (words, reached) = Resume.state(
      partial: store.loadPartial(), identity: identity, duration: duration)
    progress(Pieces.percent(reached: reached, duration: duration))

    while let piece = Pieces.next(
      reached: reached, duration: duration, pieceSeconds: pieceSeconds, overlap: overlap)
    {
      guard shouldContinue(), !Task.isCancelled else { return .paused(reached: reached) }
      let heard = try await recogniser.recognise(
        file: audio, locale: locale, from: piece.readFrom, to: piece.readTo)
      words = Pieces.merge(saved: words, new: heard, keepFrom: piece.keepFrom)
      reached = piece.readTo
      try store.savePartial(
        PartialTranscript(identity: identity, duration: duration, reached: reached, words: words))
      progress(Pieces.percent(reached: reached, duration: duration))
    }

    let transcript = Transcript(
      identity: identity, duration: duration, lines: LineRule.lines(from: words), words: words)
    try store.finish(transcript)
    return .finished(transcript)
  }
}
