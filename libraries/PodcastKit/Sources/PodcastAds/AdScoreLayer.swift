// LOFI-FORK: a row of the scorecard that adds one finder on top of the rows before it (see
// FORK.md). Foundation only.
//
// THE CONTRACT OF A SCORECARD LAYER (read this before writing one)
//
// The scorecard has a row for each stage of the finders ("Word rules", "Plus promo rules", ...).
// A layer is one more row: "Plus X". Its row is made like this, for every episode:
//
//   1. The rows before it give their ads (`soFar`, as they were joined by the row before).
//   2. `AdScoreLayer.find(input, soFar)` is called.
//   3. What it returns is joined with `soFar` by `AdJoin.join`, so a new finder never edits what
//      an earlier finder found. A layer that returns nothing leaves its row equal to the row
//      before it, exactly.
//   4. The result is scored against the labels, like any other row (`AdScore.score`): only sure
//      and unsure ads of a kind the settings skip count as skips, and a `.guess` is not a skip.
//
// What `find` receives:
//   - `input.episode` is the `TeachingEpisode`: `id`; `feed` (the show's feed address; the
//     scorecard uses it as the show's id through `MacFiles.feedAsShow`, while the phone maps
//     feed addresses to its own show ids with `MacFiles.table`, so it is not the id the phone
//     keeps for the show); `show` (the show's name); `title`; `seconds`;
//     `episodeLength` (the length of the whole episode in seconds, even when the transcript is
//     only its head); `truth` and `maybe` (the labels: the stretches Claude marked, as
//     `TeachingTruth` start, end and sort; `maybe` holds the doubtful ones); `onShelf`.
//   - `input.transcript` is a `PodcastTranscripts.Transcript` with `lines`, `words` and
//     `duration`. It is the whole transcript, or, when `input.isHead` is true, only the first
//     seconds of it (the lines and words that end by then, `duration` set to that many
//     seconds). The scorecard asks about the head to see which opening ads the first look finds,
//     and it does so only for an episode that opens with a marked ad, so a layer is called once,
//     or twice with the head, for an episode.
//   - `input.audio` is the file URL of the episode's audio when the caller has one, else nil. A
//     layer that needs audio and gets nil adds nothing: an adding layer returns no ads, and a
//     rewriting layer returns `soFar` unchanged (see below).
//   - `soFar` is the `[FoundAd]` of the rows before it.
//
// What `find` must return:
//   - Only the MORE ads: ads the layer adds. Every `FoundAd` is in seconds of the audio, with
//     `start < end`, a kind and a confidence. An ad that is not finite or has `end <= start` is
//     left out by the scorecard.
//   - It never traps and never throws. On bad input or when it cannot work, it changes nothing:
//     an adding layer returns no ads, and a rewriting layer returns `soFar` as it was (an empty
//     list from a rewriting layer would wipe the row).
//   - It does not read the labels of the episode it is looking at to find ads, because then the
//     row would score itself. The labels are in the input for a layer that was built to learn
//     from a show's other episodes, and for tests.
//   - It is called on one thread at a time, episode after episode, in the order of the
//     episodes. It may take its time on the Mac.
//
// A layer that changes or drops the ads found before it (moving borders, applying settings)
// cannot do that by adding. It is made with `AdScoreLayer.rewriting`: its function returns the
// WHOLE list of the row, which replaces `soFar` and is not joined. Only two rows are rewriting
// layers: the joints row (it moves borders) and the per-show settings row (it drops or moves
// ads to the questions). A finder row never is, because a new finder never edits what an earlier
// finder found (rule 2 of the round plan); a finder row adds.
//
// `find` is `@Sendable`, so a layer that learns across episodes (prints of the episodes it has
// seen, say) keeps that state in its own box: a final class marked `@unchecked Sendable` that
// guards the state with a lock. The scorecard calls one layer at a time, but the compiler
// cannot know it.
//
// Where a layer lives: `PodcastAudioMatch` does not depend on `PodcastAds`, so a layer that
// needs types of both (the sounds of `PodcastAudioMatch` and `AdScoreLayer` of `PodcastAds`)
// lives in the `podcast-teach` target, which depends on both.
//
// `AdScoreRun.runLayers` makes the rows. Each row stands on the one before it, the first on the
// `base` finder (the last of the rows that are not layers).
import Foundation
import PodcastTranscripts

/// What a layer is told about one episode. See the contract at the top of this file.
public struct AdScoreInput: Sendable {
  public var episode: TeachingEpisode
  public var transcript: Transcript
  public var audio: URL?

  public init(episode: TeachingEpisode, transcript: Transcript, audio: URL? = nil) {
    self.episode = episode
    self.transcript = transcript
    self.audio = audio
  }

  /// Whether `transcript` is only the first seconds of the episode's transcript.
  public var isHead: Bool { transcript.duration < episode.transcript.duration }
}

/// One row of the scorecard that adds a finder to the rows before it.
public struct AdScoreLayer: Sendable {
  public var name: String
  /// True when `find` returns the whole new list instead of more ads.
  public var rewrites: Bool
  /// `(what is known about the episode, the ads so far) -> the ads to add`.
  public var find: @Sendable (AdScoreInput, [FoundAd]) -> [FoundAd]

  public init(name: String, find: @escaping @Sendable (AdScoreInput, [FoundAd]) -> [FoundAd]) {
    self.name = name
    rewrites = false
    self.find = find
  }

  /// A layer whose function returns the whole list of the row (for borders moved and ads
  /// dropped), not only more ads.
  public static func rewriting(
    name: String, _ rewrite: @escaping @Sendable (AdScoreInput, [FoundAd]) -> [FoundAd]
  ) -> AdScoreLayer {
    var layer = AdScoreLayer(name: name, find: rewrite)
    layer.rewrites = true
    return layer
  }

  /// The ads of this layer's row, given the ads of the row before it.
  func apply(_ input: AdScoreInput, soFar: [FoundAd]) -> [FoundAd] {
    let sound = find(input, soFar).filter {
      $0.start.isFinite && $0.end.isFinite && $0.end > $0.start
    }
    if rewrites { return sound }
    return sound.isEmpty ? soFar : AdJoin.join(soFar + sound)
  }
}

extension AdScoreRun {
  /// One scorecard for each layer, in the order of `layers`. The first row is `base` plus the
  /// first layer, the next one that plus the second layer, and so on; `base` is run once for an
  /// episode, whatever the number of layers. `audio` says where an episode's audio file is.
  /// There is no scorecard for `base` alone: `run` makes that one.
  public static func runLayers(
    episodes: [TeachingEpisode], habits: ShowHabits, settings: AdSkipSettings = AdSkipSettings(),
    audio: (TeachingEpisode) -> URL? = { _ in nil },
    base: (TeachingEpisode, Transcript) -> [FoundAd], layers: [AdScoreLayer]
  ) -> [Scorecard] {
    guard !layers.isEmpty else { return [] }
    return runRows(episodes: episodes, habits: habits, settings: settings, rows: layers.count) {
      episode, transcript in
      let input = AdScoreInput(episode: episode, transcript: transcript, audio: audio(episode))
      var soFar = base(episode, transcript)
      return layers.map { layer in
        soFar = layer.apply(input, soFar: soFar)
        return soFar
      }
    }
  }
}
