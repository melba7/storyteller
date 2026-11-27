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
  ///
  /// A skip that a tap carried over holes takes no ad back. The listener chose to leave the ad,
  /// so the Undo is about the carry: the playhead goes to the first hole (`carriedFrom`), no ad is
  /// saved as undone and no finder is blamed. The ads behind the hole are skipped again when the
  /// playhead reaches them, with an Undo of their own.
  public var takenBack: [FoundAd] {
    guard holes.isEmpty else { return [] }
    let all = [ad] + chained
    let cued = all.filter { $0.source == ShowTuning.openingLines || $0.source == ShowTuning.filledHoles }
    return cued.isEmpty || cued.count == all.count ? all : cued
  }
}

extension AdSkip {
  /// The gaps longer than `AdSkipper.chainGap` between the ads of this skip, in order: the holes
  /// the skip carried over. A hole runs from the greatest end so far to the next ad's start.
  /// Ads that touch give none.
  public var holes: [(start: Double, end: Double)] {
    var result: [(start: Double, end: Double)] = []
    var end = ad.end
    for next in chained {
      if next.start > end + AdSkipper.chainGap { result.append((start: end, end: next.start)) }
      end = max(end, next.end)
    }
    return result
  }

  /// Where an Undo of this skip puts the playhead when a tap carried the skip over holes: the
  /// start of its first hole. Nil for every other skip.
  public var carriedFrom: Double? { holes.first?.start }
}
