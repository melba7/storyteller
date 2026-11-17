// LOFI-FORK: finds the ads in a whole transcript (see FORK.md).
import Foundation
import PodcastTranscripts

public enum AdsOutcome: Sendable, Equatable {
  case finished(AdsFile)
  /// Stopped between pieces. Nothing is saved, so the next run starts over.
  case stopped
}

public enum AdsRunner {
  /// Splits the transcript into pieces for the detector, asks it about each one, cleans up the
  /// answers and saves the file. A piece that does not fit the model is split in two and asked
  /// again. `progress` is called with how many pieces are done and how many there are.
  public static func run(
    transcript: Transcript, detector: AdDetector, store: AdsStore, osVersion: String,
    overlap: Double = AdChunker.overlap, progress: @Sendable (Int, Int) -> Void = { _, _ in },
    shouldContinue: @Sendable () -> Bool = { true }
  ) async throws -> AdsOutcome {
    let pieces = AdChunker.pieces(
      of: AdChunker.number(transcript.lines), tokenBudget: detector.tokenBudget, overlap: overlap)
    var ranges: [AdRange] = []
    progress(0, pieces.count)
    for (index, piece) in pieces.enumerated() {
      guard shouldContinue(), !Task.isCancelled else { return .stopped }
      ranges += try await ask(detector, piece)
      progress(index + 1, pieces.count)
    }
    let file = AdsFile(
      sha256: store.sha256, detector: detector.name, detectorVersion: detector.version,
      osVersion: osVersion, duration: transcript.duration,
      ads: AdCleanup.run(ranges: ranges, transcript: transcript))
    try store.save(file)
    return .finished(file)
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
