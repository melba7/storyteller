// LOFI-FORK: the scorecard row that applies the Mac's per-show settings (see FORK.md, ShowTuning.swift
// and AdScoreLayer.swift). Foundation only.
import Foundation

public enum SettingsScoreLayer {
  /// "Plus per-show settings": `show-settings.json` applied to the ads of the rows before it, for
  /// each show (the scorecard names a show by its feed address, as the file does). It rewrites
  /// the whole list, because it drops ads (a finder or a sort that only asks, or is off, does not
  /// skip) and chooses whether the borders are snapped onto the joints.
  ///
  /// The order is the phone's. The settings come first, on the list of each finder on its own
  /// (the ads of the older finders, then the lists the finder rows kept in `finders`, each cut back
  /// to the older finders only). Each list that is kept is cut back to what is kept before it, and
  /// the lists are joined: only the skips are in the join. The snap comes last, only where the
  /// settings say joints are on for the show, with steady files too only where they say so. With
  /// no base kept for the episode (the rows before did not run) it starts from the ads it is given.
  /// `snap` is `ScoreSoundKit.snapJoints` and `cached` is `ScoreSoundKit.cachedJoints`. The first look
  /// is by words and only drops.
  public static func perShowSettings(
    tuning: ShowTuning, finders: ScoreFinderAds,
    snap: (@Sendable (URL, [ScoreSpan], Bool) -> [ScoreSpan])?,
    cached: ScoreCachedJoints = ScoreCachedJoints()
  ) -> AdScoreLayer {
    .rewriting(name: ScoreRows.settings) { input, soFar in
      let show = input.episode.feed
      guard !input.isHead else { return tuning.apply(to: soFar, show: show).skip }
      let id = input.episode.id
      var kept: [FoundAd]
      if let base = finders.base(for: id) {
        kept = tuning.apply(to: base, show: show).skip
        for finder in ScoreRows.finderOrder {
          let own = tuning.apply(to: finders.ads(finder: finder, for: id), show: show).skip
          kept += ScoreAds.outside(own, of: kept)
        }
        kept = AdJoin.join(kept)
      } else {
        kept = tuning.apply(to: soFar, show: show).skip
      }
      guard let snap, tuning.joints(show: show), !kept.isEmpty,
        let move = cached.mover(for: input, audio: snap)
      else { return kept }
      let steadyToo = tuning.steadyJoints(show: show)
      return ScoreAds.moved(kept) { move($0, steadyToo) }
    }
  }
}
