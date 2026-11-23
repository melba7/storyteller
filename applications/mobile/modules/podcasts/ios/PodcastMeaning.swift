// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The meaning layer as a finder of its own: Apple's sentence embedding turns each line of a whole
// transcript into numbers, and the small model the Mac trained (`ad-meaning.json`) says which
// lines read like an ad. It returns its own list of ads (unsure, source "meaning") and its own
// class rows; it is never a layer of LocalAds, so with it off the local result is today's.
// It runs only in the finder's final pass, inside `PodcastFinderGuard.hold`, never on the main
// actor. The model times the first 50 lines and leaves the layer out above 30 ms a line
// (`AdMeaningModel.slowSecondsPerLine`). One embedding is made for the pass and let go after it.
import Foundation
import PodcastAds
import PodcastAdsOnDevice
import PodcastTranscripts

enum PodcastMeaning {
  /// What one run gave: the model's ads and rows (nil when the layer was off or stopped), and the
  /// plain line for the diary (numbers and words of our own, never the transcript's).
  struct Outcome {
    var run: MeaningRun?
    var diary: String
  }

  /// Makes the embedding for the revision the model was trained on, or nil when this system has
  /// none of that revision.
  typealias EmbedderFactory = @Sendable (Int) -> LineEmbedder?

  /// Apple's English sentence embedding (NaturalLanguage; Mac and iOS only).
  static let appleEmbedder: EmbedderFactory = { revision in
    #if canImport(NaturalLanguage)
      return AppleLineEmbedder(revision: revision)
    #else
      return nil
    #endif
  }

  static func run(
    model: AdMeaningModel, transcript: Transcript, stop: StopFlag,
    makeEmbedder: EmbedderFactory = PodcastMeaning.appleEmbedder
  ) -> Outcome {
    guard let apple = makeEmbedder(model.revision) else {
      return Outcome(
        run: nil,
        diary:
          "meaning layer off: this phone has no sentence embedding of revision \(model.revision)")
    }
    let run = MeaningAds.run(model: model, transcript: transcript, embedder: Stoppable(apple, stop))
    if stop.isStopped {
      return Outcome(run: nil, diary: "meaning layer stopped: the time was up")
    }
    switch run.state {
    case .off(let reason):
      return Outcome(run: nil, diary: "meaning layer off: \(reason)")
    case .ready:
      let speed = run.secondsPerLine.map { ", \(Int($0 * 1000)) ms a line" } ?? ""
      return Outcome(run: run, diary: "meaning: \(run.ads.count) ads\(speed)")
    }
  }

  /// The embedding, which gives nothing for a line once the time is up, so a pass that is
  /// stopped goes through the rest of its lines at once.
  private struct Stoppable: LineEmbedder {
    let base: LineEmbedder
    let stop: StopFlag

    init(_ base: LineEmbedder, _ stop: StopFlag) {
      self.base = base
      self.stop = stop
    }

    var dimension: Int { base.dimension }
    var revision: Int { base.revision }

    func vector(for text: String) -> [Double]? {
      stop.isStopped ? nil : base.vector(for: text)
    }
  }
}
