// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// What a stream's head scan does with the ads the phone remembers (PodcastKnownAds): after each
// step the words so far are looked at for them before the quick rules run. An ad that is whole
// in the words is a sure ad, exact to the word. An ad that opens at the end of the words makes
// the next step end after where it should end, and, when it was seen at least twice, is saved at
// once with a guessed end (KnownAdUse).
import Foundation
import PodcastAds
import PodcastTranscripts

final class HeadMemory: @unchecked Sendable {
  private let lock = NSLock()
  /// The guessed ads of the last look, and every guessed ad that was ever saved.
  private var current: [FoundAd] = []
  private var everGuessed: [FoundAd] = []
  private var heard: [TranscriptWord] = []

  /// The words of the last step, for forgetting an ad when the listener undoes it.
  var words: [TranscriptWord] { lock.withLock { heard } }

  /// Looks for remembered ads in `words` and logs what it found. Nothing is found for an episode
  /// whose show is not known.
  func look(in words: [TranscriptWord], episodeId: String) -> KnownAdUse {
    lock.withLock { heard = words }
    guard let show = EpisodeShows.shared.show(for: episodeId) else {
      PodcastTimeline.mark(episodeId, "memory: no show known")
      return KnownAdUse()
    }
    let use = KnownAdUse.from(PodcastKnownAds.shared.find(in: words, show: show), words: words)
    lock.withLock {
      current = use.provisional
      for ad in use.provisional where !everGuessed.contains(ad) { everGuessed.append(ad) }
    }
    let count = use.ads.count
    PodcastTimeline.mark(episodeId, "memory: \(count) ad\(count == 1 ? "" : "s")")
    if let jump = use.jumpTo {
      PodcastTimeline.mark(episodeId, "memory: the next step ends at \(Int(jump)) s")
    }
    return use
  }

  /// The ads of the file on disk without the guessed ones that a later look has replaced: a
  /// guessed end must not stay once the whole ad was found, because the longer of two ads wins
  /// when they are joined.
  func withoutOutdated(_ ads: [FoundAd]) -> [FoundAd] {
    lock.withLock { KnownAdUse.withoutOutdated(ads, everGuessed: everGuessed, current: current) }
  }
}
