// LOFI-FORK: the ads the meaning model finds, as a finder of its own (see FORK.md). Foundation only.
import Foundation
import PodcastTranscripts

/// What one run of the meaning finder gave.
public struct MeaningRun: Sendable, Equatable {
  /// The ads, all `unsure`, with `source` "meaning". Empty when the layer is off.
  public var ads: [FoundAd]
  public var state: MeaningState
  /// The class probabilities of the transcript's lines, in the order of `AdChunker.number(lines)`.
  /// A caller that asks about the middle band (a line the model is not sure of) reads them here.
  public var rows: [[Double]]
  /// The seconds a line took over the first lines, for the diary.
  public var secondsPerLine: Double?
}

/// The meaning model as a finder of its own. It is not a layer of `LocalAds`: it returns its own
/// list, and the code that joins finders trims it against what the older ones found first. With no
/// meaning model nobody calls it and nothing else changes.
public enum MeaningAds {
  /// The `source` of the ads it makes.
  public static let source = "meaning"

  /// Runs the model over the transcript. The spans become ranges that the same clean-up as for
  /// every finder turns into ads (edges, merging, length limits); then each ad gets its source.
  /// A finder that only this model backs never says "sure", so every ad is unsure and the
  /// listener sees the Undo note.
  public static func run(
    model: AdMeaningModel, transcript: Transcript, embedder: LineEmbedder,
    clock: () -> Double = { ProcessInfo.processInfo.systemUptime }
  ) -> MeaningRun {
    let lines = AdChunker.number(transcript.lines)
    let made = model.probabilities(
      lines: lines, duration: transcript.duration > 0 ? transcript.duration : nil,
      embedder: embedder, clock: clock)
    let ranges = model.spans(of: made, lines: lines).compactMap { span -> AdRange? in
      guard let kind = AdKind(sort: span.sort) else { return nil }
      return AdRange(
        startLine: span.firstLine, endLine: span.lastLine, advertiser: "", kind: kind,
        confidence: .unsure)
    }
    var ads = AdCleanup.run(ranges: ranges, transcript: transcript)
    for index in ads.indices {
      ads[index].source = source
      ads[index].confidence = min(ads[index].confidence, .unsure)
    }
    return MeaningRun(ads: ads, state: made.state, rows: made.rows, secondsPerLine: made.secondsPerLine)
  }

  /// Just the ads of `run`.
  public static func find(
    model: AdMeaningModel, transcript: Transcript, embedder: LineEmbedder,
    clock: () -> Double = { ProcessInfo.processInfo.systemUptime }
  ) -> [FoundAd] {
    run(model: model, transcript: transcript, embedder: embedder, clock: clock).ads
  }
}
