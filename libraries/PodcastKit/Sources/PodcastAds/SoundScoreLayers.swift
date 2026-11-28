// LOFI-FORK: the scorecard rows that need an episode's audio (see FORK.md and AdScoreLayer.swift).
// Foundation only.
//
// The rows are "Plus the phone's own sounds", "Plus repeated sounds", "Plus joints" and "Plus joints
// (steady files too)". They are written here, against sound finders handed in as functions,
// because PodcastAds cannot see the audio code and the audio code cannot see PodcastAds; the
// `podcast-teach` tool joins the two (SoundScoreKit.swift there). So everything these rows decide
// is tested in PodcastAdsTests with finders that are made up.
//
// A finder row only ADDS: what a sound finder gives is made into `unsure` ads of the finder's
// name, cut back to the parts outside every ad of the rows before (`ScoreAds.outside`), and
// joined with them by the scorecard. A new finder never lengthens or upgrades an older finder's
// ad. A row counts the new ads as skips, whatever the Mac's settings say about that finder,
// because it is there to show how right the finder is (the "Plus per-show settings" row is the
// one that applies the settings). An episode with no audio adds nothing.
import Foundation

/// The joints of the episodes that were found before and kept in the teaching folder
/// (`joints.json`, made by `podcast-teach joints`), so the joint rows need no audio.
public struct ScoreCachedJoints: Sendable {
  /// Whether the cache holds the joints of the episode with this id.
  public var has: @Sendable (String) -> Bool
  /// `(episode id, stretches, steadyToo)`: the stretches with their borders moved onto the cached
  /// joints of the episode, in the same order.
  public var snap: @Sendable (String, [ScoreSpan], Bool) -> [ScoreSpan]

  public init(
    has: @escaping @Sendable (String) -> Bool = { _ in false },
    snap: @escaping @Sendable (String, [ScoreSpan], Bool) -> [ScoreSpan] = { _, spans, _ in spans }
  ) {
    self.has = has
    self.snap = snap
  }

  /// What moves the stretches of this episode: the cache when it holds the episode (it is the same
  /// joints, without reading the file again), else the audio, else nothing.
  func mover(
    for input: AdScoreInput, audio snap: @escaping @Sendable (URL, [ScoreSpan], Bool) -> [ScoreSpan]
  ) -> (@Sendable ([ScoreSpan], Bool) -> [ScoreSpan])? {
    let id = input.episode.id
    if has(id) {
      let cached = self.snap
      return { cached(id, $0, $1) }
    }
    guard let audio = input.audio else { return nil }
    return { snap(audio, $0, $1) }
  }
}

/// The sound finders of the scorecard, as functions. The caller that has the audio code makes
/// them; each learns across episodes in a box of its own (the scorecard goes through the
/// episodes in order, one at a time).
public struct ScoreSoundKit: Sendable {
  /// `(audio, show, episode, what to learn)`: the stretches of the show's earlier episodes' sounds
  /// that play in this audio, and then learns the stretches it is given (the sure ads of the rows
  /// before, which were skipped in this episode). The order matters: an episode is searched with
  /// what the show's EARLIER episodes taught, never with its own ads.
  public var ownSounds: @Sendable (URL, String, String, [ScoreSpan]) -> [ScoreSpan]
  /// `(audio, show, episode)`: the stretches that an earlier episode of the show also had, and
  /// then keeps this episode's print for the ones after it.
  public var repeatedSounds: @Sendable (URL, String, String) -> [ScoreSpan]
  /// `(audio, stretches, steadyToo)`: the stretches with their borders moved onto the joints of
  /// the audio, in the same order.
  public var snapJoints: @Sendable (URL, [ScoreSpan], Bool) -> [ScoreSpan]
  /// The joints kept in the folder, for the episodes that have no audio there (or that need not be
  /// read again). Holds no episode by default.
  public var cachedJoints: ScoreCachedJoints
  /// `(audio, episode)`: the stretches where the ad sounds of the episodes published 1 to 7 days
  /// before this one play in its audio (the row "Plus this week's ad sounds", WeekScoreRow.swift).
  /// Nothing by default.
  public var weekSounds: @Sendable (URL, String) -> [ScoreSpan]

  public init(
    ownSounds: @escaping @Sendable (URL, String, String, [ScoreSpan]) -> [ScoreSpan] = { _, _, _, _ in [] },
    repeatedSounds: @escaping @Sendable (URL, String, String) -> [ScoreSpan] = { _, _, _ in [] },
    snapJoints: @escaping @Sendable (URL, [ScoreSpan], Bool) -> [ScoreSpan] = { _, spans, _ in spans },
    cachedJoints: ScoreCachedJoints = ScoreCachedJoints(),
    weekSounds: @escaping @Sendable (URL, String) -> [ScoreSpan] = { _, _ in [] }
  ) {
    self.ownSounds = ownSounds
    self.repeatedSounds = repeatedSounds
    self.snapJoints = snapJoints
    self.cachedJoints = cachedJoints
    self.weekSounds = weekSounds
  }
}

public enum SoundScoreLayers {
  // MARK: Finders

  /// "Plus the phone's own sounds". `scan` is `ScoreSoundKit.ownSounds`.
  public static func ownSounds(
    _ scan: @escaping @Sendable (URL, String, String, [ScoreSpan]) -> [ScoreSpan],
    finders: ScoreFinderAds? = nil
  ) -> AdScoreLayer {
    finder(name: ScoreRows.ownSounds, source: ShowTuning.ownSound, finders: finders) {
      input, audio, soFar in
      scan(audio, input.episode.feed, input.episode.id, ScoreAds.learnable(soFar))
    }
  }

  /// "Plus repeated sounds". `scan` is `ScoreSoundKit.repeatedSounds`.
  public static func repeatedSounds(
    _ scan: @escaping @Sendable (URL, String, String) -> [ScoreSpan], finders: ScoreFinderAds? = nil
  ) -> AdScoreLayer {
    finder(name: ScoreRows.repeatedSounds, source: ShowTuning.repeatSound, finders: finders) {
      input, audio, _ in
      scan(audio, input.episode.feed, input.episode.id)
    }
  }

  /// A row that adds the ads a sound finder gives for the whole episode. The audio is read once
  /// for an episode: the look at its first seconds (a call with only the head of the transcript)
  /// answers from what the whole call found, and only the ads that end by then.
  private static func finder(
    name: String, source: String, finders: ScoreFinderAds?,
    look: @escaping @Sendable (AdScoreInput, URL, [FoundAd]) -> [ScoreSpan]
  ) -> AdScoreLayer {
    let found = ScoreEpisodeAds()
    return AdScoreLayer(name: name) { input, soFar in
      guard let audio = input.audio else { return [] }
      let id = input.episode.id
      if input.isHead {
        return (found.ads(for: id) ?? []).filter { $0.end <= input.transcript.duration }
      }
      let own = ScoreAds.ads(look(input, audio, soFar), source: source)
      let added =
        finders?.add(own, finder: source, to: soFar, for: id, base: finders?.base(for: id), keep: true)
        ?? ScoreAds.outside(own, of: soFar)
      found.put(added, for: id)
      return added
    }
  }

  // MARK: Joints

  /// "Plus joints": every ad's borders moved onto the joints of the file, as the phone does
  /// before it writes the ads. It rewrites the whole list, and keeps the list it was given in
  /// `stash` for the steady row and the settings row, which start from the ads as they were.
  /// `snap` is `ScoreSoundKit.snapJoints`.
  public static func joints(
    _ snap: @escaping @Sendable (URL, [ScoreSpan], Bool) -> [ScoreSpan], stash: ScoreEpisodeAds,
    cached: ScoreCachedJoints = ScoreCachedJoints(), words: @escaping ScoreWords = { _ in [] }
  ) -> AdScoreLayer {
    snapping(
      name: ScoreRows.joints, steadyToo: false, snap: snap, stash: stash, keep: true, cached: cached,
      words: words)
  }

  /// "Plus joints (steady files too)": the same, and a file whose frames are all alike is used
  /// too. It is an alternative to the row before it, not something on top: it moves the ads from
  /// before the joints row (in `stash`), so the two rows can be told apart. With no joints row
  /// (no stash) it moves what it is given.
  public static func steadyJoints(
    _ snap: @escaping @Sendable (URL, [ScoreSpan], Bool) -> [ScoreSpan], stash: ScoreEpisodeAds,
    cached: ScoreCachedJoints = ScoreCachedJoints(), words: @escaping ScoreWords = { _ in [] }
  ) -> AdScoreLayer {
    snapping(
      name: ScoreRows.steadyJoints, steadyToo: true, snap: snap, stash: stash, keep: false,
      cached: cached, words: words)
  }

  private static func snapping(
    name: String, steadyToo: Bool,
    snap: @escaping @Sendable (URL, [ScoreSpan], Bool) -> [ScoreSpan], stash: ScoreEpisodeAds,
    keep: Bool, cached: ScoreCachedJoints, words: @escaping ScoreWords
  ) -> AdScoreLayer {
    .rewriting(name: name) { input, soFar in
      // The first look is by words; its borders are not moved, and the stash is the whole
      // episode's.
      guard !input.isHead, !soFar.isEmpty, let move = cached.mover(for: input, audio: snap)
      else { return soFar }
      let id = input.episode.id
      if keep { stash.put(soFar, for: id) }
      let base = keep ? soFar : (stash.ads(for: id) ?? soFar)
      return ScoreAds.moved(base, words: words(input)) {
        move($0, steadyToo)
      }
    }
  }
}
