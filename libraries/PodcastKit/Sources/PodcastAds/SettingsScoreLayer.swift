// LOFI-FORK: the scorecard row that applies the Mac's per-show settings (see FORK.md, ShowTuning.swift
// and AdScoreLayer.swift). Foundation only.
import Foundation

public enum SettingsScoreLayer {
  /// "Plus per-show settings": `show-settings.json` applied to the ads of the rows before it, for
  /// each show (the scorecard names a show by its feed address, as the file does). It rewrites
  /// the whole list, because it drops ads (a finder or a sort that only asks, or is off, does not
  /// skip) and chooses whether the borders were snapped onto the joints.
  ///
  /// The order is the phone's: the settings first, on the ads as they were BEFORE the joints
  /// rows (kept in `stash` by them), and the snap after, only where the settings say joints are
  /// on for the show, with steady files too only where they say so. With no stash (the joints rows
  /// did not run for the episode) it starts from the ads it is given and snaps nothing. `snap` is
  /// `ScoreSoundKit.snapJoints`. The first look is by words and only drops.
  public static func perShowSettings(
    tuning: ShowTuning, stash: ScoreEpisodeAds,
    snap: (@Sendable (URL, [ScoreSpan], Bool) -> [ScoreSpan])?
  ) -> AdScoreLayer {
    .rewriting(name: ScoreRows.settings) { input, soFar in
      let show = input.episode.feed
      guard !input.isHead else { return tuning.apply(to: soFar, show: show).skip }
      let base = stash.ads(for: input.episode.id) ?? soFar
      let kept = tuning.apply(to: base, show: show).skip
      guard let snap, let audio = input.audio, tuning.joints(show: show), !kept.isEmpty else {
        return kept
      }
      let steadyToo = tuning.steadyJoints(show: show)
      return ScoreAds.moved(kept) { snap(audio, $0, steadyToo) }
    }
  }
}
