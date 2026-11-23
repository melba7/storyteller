// LOFI-FORK: the scorecard rows that read the transcript and learn from it (see FORK.md and
// AdScoreLayer.swift). Foundation only.
//
// "Plus repeated words" is `RepeatedWords` over the show's earlier episodes (idea 2, the word
// half) and "Plus the meaning model" is `MeaningAds.run` (idea 8). Both follow the rule of a
// finder row: they add `unsure` ads of the finder's own name, cut back to the parts outside every
// ad of the rows before, so a new finder never lengthens or upgrades an older finder's ad. A row
// counts them as skips, whatever the Mac's settings say about the finder: it is there to show how
// right the finder is.
import Foundation
import PodcastTranscripts

/// What the meaning row noticed while it ran, for the plain notes under the scorecard.
public final class MeaningScoreNotes: @unchecked Sendable {
  private let lock = NSLock()
  private var reasons: [String] = []
  private var ran = 0
  private var perLine: [Double] = []

  public init() {}

  /// Why the layer was off for some episode, each reason once, in the order they came.
  public var offReasons: [String] {
    lock.lock()
    defer { lock.unlock() }
    return reasons
  }

  /// How many episodes the model read.
  public var episodes: Int {
    lock.lock()
    defer { lock.unlock() }
    return ran
  }

  /// The mean of the seconds a line took, over the episodes that were timed; nil if none was.
  public var secondsPerLine: Double? {
    lock.lock()
    defer { lock.unlock() }
    return perLine.isEmpty ? nil : perLine.reduce(0, +) / Double(perLine.count)
  }

  func record(_ run: MeaningRun) {
    lock.lock()
    defer { lock.unlock() }
    switch run.state {
    case .ready: ran += 1
    case .off(let reason): if !reasons.contains(reason) { reasons.append(reason) }
    }
    if let seconds = run.secondsPerLine, seconds.isFinite { perLine.append(seconds) }
  }
}

public enum WordScoreLayers {
  /// "Plus repeated words". The memory of the show's earlier episodes is the layer's own: the
  /// scorecard goes through the episodes in order, and an episode is compared with the ones
  /// before it (up to three, as on the phone) and then remembered. `now` is the time the run
  /// starts. A transcript with no lines gives nothing and is remembered as nothing.
  public static func repeatedWords(now: Date) -> AdScoreLayer {
    let memory = RepeatedWordsMemory()
    return AdScoreLayer(name: ScoreRows.repeatedWords) { input, soFar in
      // The look at the first seconds asks the memory and keeps it as it is: the whole
      // transcript was remembered before it.
      return memory.find(input, soFar: soFar, now: now, remember: !input.isHead)
    }
  }

  /// "Plus the meaning model": the model's own ads, cut back to what the older finders left.
  /// It runs only on the whole transcript (on the phone it runs in the finder's background
  /// passes, not in the head scan). A layer that is off for an episode (the embedder does not give
  /// the numbers the model was trained on, or a line takes too long) adds nothing, and the reason
  /// goes to `notes`.
  public static func meaning(
    model: AdMeaningModel, embedder: LineEmbedder, notes: MeaningScoreNotes
  ) -> AdScoreLayer {
    AdScoreLayer(name: ScoreRows.meaning) { input, soFar in
      guard !input.isHead else { return [] }
      let run = MeaningAds.run(model: model, transcript: input.transcript, embedder: embedder)
      notes.record(run)
      return ScoreAds.outside(run.ads, of: soFar)
    }
  }
}

/// The repeated-words memory of one scorecard run, behind a lock.
private final class RepeatedWordsMemory: @unchecked Sendable {
  private let lock = NSLock()
  private var memory = RepeatedWords()

  func find(_ input: AdScoreInput, soFar: [FoundAd], now: Date, remember: Bool) -> [FoundAd] {
    lock.lock()
    defer { lock.unlock() }
    let episode = input.episode
    let lines = input.transcript.lines
    guard !lines.isEmpty else { return [] }
    // `already` is every ad known for the episode: nothing found overlaps one, and every piece
    // stays a second away from it.
    let found = memory.find(
      show: episode.feed, episode: episode.id, lines: lines, duration: episode.episodeLength,
      now: now, already: soFar)
    if remember {
      memory.remember(show: episode.feed, episode: episode.id, lines: lines, now: now)
    }
    return ScoreAds.outside(found, of: soFar)
  }
}
