// LOFI-FORK: the phone's own notes of how a show starts, as the Mac's habits (see FORK.md).
//
// `ShowStarts` is what the phone saw itself: for each show whether its last five checked episodes
// opened with an ad and where that opening ended. This puts it in the shape of `ShowHabits`, so a
// show the Mac never sampled is waited for and looked at the same way as one it did. The counts,
// the middle value with its rounding to a tenth and the 20 second join of ads are the Mac's
// (`teach_habits.py`). The window is not: the phone's opening is an ad that starts before 30
// seconds (`ShowStarts.window`, as its bit has always been), the Mac's is a first block of ads that
// starts at or before 90 seconds. So an episode whose first ad starts at 30 to 90 seconds counts as
// opening with an ad on the Mac and not on the phone. Where the Mac has an entry for a show, its
// entry is the one used. Foundation only.
import Foundation

extension ShowStarts.Show {
  /// The show as the Mac's habits file would say it: how many episodes were checked, how many of
  /// them opened with an ad, and the middle value of where those openings ended, rounded to a
  /// tenth of a second. An ending that is not known is left out, and nil when none is known.
  public func habits() -> ShowHabits.Show {
    let ends = zip(results, knownEnds).compactMap { pair in
      pair.0 ? ShowStarts.believed(pair.1) : nil
    }
    return ShowHabits.Show(
      id: id, episodes: results.count, opensWithAd: results.filter { $0 }.count,
      openingEnds: Self.middle(of: ends).map(Self.tenths))
  }

  /// The middle value, or the mean of the two middle ones for an even count, as the Mac's `median`.
  private static func middle(of values: [Double]) -> Double? {
    let ordered = values.sorted()
    guard !ordered.isEmpty else { return nil }
    let half = ordered.count / 2
    return ordered.count % 2 == 1 ? ordered[half] : (ordered[half - 1] + ordered[half]) / 2
  }

  /// `value` rounded to one decimal the way Python's `round(value, 1)` does it, which the Mac
  /// uses: the exact value decides, and an exact half goes to the even tenth (40.25 gives 40.2).
  private static func tenths(_ value: Double) -> Double {
    Double(String(format: "%.1f", value)) ?? value
  }
}

extension ShowStarts {
  /// Everything the phone saw itself, in the shape of the Mac's habits. A show with no checked
  /// episode says nothing and is left out.
  public func habits() -> ShowHabits {
    var habits = ShowHabits()
    habits.shows = shows.filter { !$0.results.isEmpty }.map { $0.habits() }
    return habits
  }
}

extension ShowHabits {
  /// These habits (the Mac's) with the phone's own for the shows the Mac has no entry for. The
  /// Mac's entry wins where it has one whose numbers are possible; a show it has nothing usable
  /// for gets the phone's entry, but only when that entry says the show opened with an ad. A show
  /// that never did is left to `ShowStarts.startsClean` (five clean episodes), as before, so Play
  /// never stops holding the start earlier than it did. The Mac's shows come first, in their
  /// order, and a show the phone lists twice is listed once.
  public func merged(with own: ShowHabits) -> ShowHabits {
    var merged = ShowHabits()
    merged.shows = shows.filter(\.isSound)
    var known = Set(merged.shows.map(\.id))
    for show in own.shows where show.isSound && show.opensWithAd > 0 {
      if known.insert(show.id).inserted { merged.shows.append(show) }
    }
    return merged
  }
}
