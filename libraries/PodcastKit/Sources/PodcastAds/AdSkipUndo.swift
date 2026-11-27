// LOFI-FORK: which ads of a skip an Undo takes back (see FORK.md and CueAds.swift). Plain values.
import Foundation

extension AdSkip {
  /// The ads an Undo of this skip takes back, in order of time. A stretch the opening lines or the
  /// filled holes added is only a guess about where an ad of another finder begins or goes on. So
  /// when the skip holds such stretches next to other ads, the Undo is about them: only they are
  /// taken back, and the other ads are skipped again when the playhead reaches them, with an Undo
  /// of their own. That way a pull that started too early costs the listener no ad to hear, and
  /// the finder that was right is not blamed for it. A skip of such stretches alone, or with none
  /// of them, is taken back whole.
  public var takenBack: [FoundAd] {
    let all = [ad] + chained
    let cued = all.filter { $0.source == ShowTuning.openingLines || $0.source == ShowTuning.filledHoles }
    return cued.isEmpty || cued.count == all.count ? all : cued
  }
}
