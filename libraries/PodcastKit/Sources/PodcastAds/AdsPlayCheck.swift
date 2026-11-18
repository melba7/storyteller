// LOFI-FORK: runs ad finding the way the phone does, to time it (see FORK.md).
import Foundation
import PodcastTranscripts

/// What a play-through check found and how long each part took.
public struct PlayCheckResult: Sendable, Equatable {
  public var duration: Double
  /// What was known after each partial pass, and after the full pass at the end.
  public var snapshots: [AdSnapshot]
  public var verdicts: [AdVerdict]
  public var transcribeSeconds: Double
  public var modelSeconds: Double
  /// From the first piece to the end of the full pass.
  public var totalSeconds: Double
  /// How many pieces the model refused.
  public var refusedPieces: Int

  public var speed: Double {
    AdTimeline.speed(audioSeconds: duration, processingSeconds: totalSeconds)
  }
}

public enum PlayCheck {
  /// Transcribes `audio` piece by piece with `Pieces.next`, runs the partial ad pass after each
  /// piece (as the phone does for the episode that is playing), then the full pass, and times
  /// each step with `now` (seconds from any steady clock). Nothing is saved but the ad files in
  /// `store`'s folder, which the caller removes.
  public static func run(
    audio: URL, sha256: String, locale requested: String, recogniser: PieceRecogniser,
    detector: AdDetector, store: AdsStore, rate: Double = 1, now: @Sendable () -> Double,
    progress: @Sendable (String) -> Void = { _ in }
  ) async throws -> PlayCheckResult {
    let locale = try await recogniser.prepare(locale: requested)
    let duration = try recogniser.duration(of: audio)
    guard duration > 0 else { throw TranscriptError.failed("The audio is empty.") }
    let identity = TranscriptIdentity(
      locale: locale, recogniser: recogniser.name, recogniserVersion: recogniser.version,
      osVersion: recogniser.osVersion, sha256: sha256)
    let osVersion = recogniser.osVersion

    let began = now()
    var transcribing = 0.0
    var modelling = 0.0
    var words: [TranscriptWord] = []
    var reached = 0.0
    var snapshots: [AdSnapshot] = []
    var refused = 0

    while let piece = Pieces.next(reached: reached, duration: duration) {
      let before = now()
      let heard = try await recogniser.recognise(
        file: audio, locale: locale, from: piece.readFrom, to: piece.readTo)
      transcribing += now() - before
      words = Pieces.merge(saved: words, new: heard, keepFrom: piece.keepFrom)
      reached = piece.readTo
      progress("Transcribed \(Int(reached)) of \(Int(duration)) s")
      // At the end of the audio the full pass below does the work.
      guard !Pieces.isDone(reached: reached, duration: duration) else { break }

      let asked = now()
      let outcome = try await AdsRunner.runPartial(
        partial: PartialTranscript(
          identity: identity, duration: duration, reached: reached, words: words),
        detector: detector, store: store, osVersion: osVersion)
      modelling += now() - asked
      if case .finished(let file) = outcome {
        snapshots.append(AdSnapshot(elapsed: now() - began, ads: file.ads))
        refused = file.refusedPieces ?? refused
        progress("Ads known so far: \(file.ads.count), checked to \(Int(file.coveredUntil ?? 0)) s")
      }
    }

    let transcript = Transcript(
      identity: identity, duration: duration, lines: LineRule.lines(from: words), words: words)
    let asked = now()
    let outcome = try await AdsRunner.run(
      transcript: transcript, detector: detector, store: store, osVersion: osVersion)
    modelling += now() - asked
    guard case .finished(let file) = outcome else { throw CancellationError() }
    let total = now() - began
    snapshots.append(AdSnapshot(elapsed: total, ads: file.ads))
    return PlayCheckResult(
      duration: duration, snapshots: snapshots,
      verdicts: AdTimeline.verdicts(snapshots: snapshots, rate: rate),
      transcribeSeconds: transcribing, modelSeconds: modelling, totalSeconds: total,
      refusedPieces: file.refusedPieces ?? refused)
  }
}
