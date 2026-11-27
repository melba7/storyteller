// LOFI-FORK: the Skip ad button's rule (see FORK.md). Plain values, no AVFoundation.
import Foundation

/// Where the Skip ad button takes the listener.
public enum AdSkipNow {
  /// An ad counts as the one to leave from this long before its start, so a tap just before an
  /// ad that the listener hears coming skips it.
  public static let leadSeconds = 2.0
  /// With no ad there, the button jumps this far ahead.
  public static let jumpSeconds = 30.0
  /// ... and never to within this long of the end of the episode.
  public static let endMargin = 1.0

  /// Like `target(position:duration:ads:)` for an ads file (nil when the episode has none): all
  /// its ads, cut short by the listener's trims, with undone ones and every kind included.
  public static func target(
    position: Double, duration: Double?, file: AdsFile?
  ) -> (to: Double, known: FoundAd?) {
    let trims = file?.trims ?? []
    let ads = (file?.ads ?? []).map { $0.trimmed(by: trims) }.filter { $0.end > $0.start }
    return target(position: position, duration: duration, ads: ads)
  }

  /// The place to go from `position`. When the playhead is inside one of `ads` (from
  /// `leadSeconds` before its start to its end), that is the end of the ad and of the ads that
  /// follow it within half a second, and `known` is the first of them. Otherwise it is
  /// `jumpSeconds` ahead, at most `endMargin` before the end of the episode. It is never behind
  /// the playhead. `ads` are all the ads of the episode's best ads file, whatever the switches
  /// say and whether or not a skip of them was undone: a listener who taps Skip ad wants out.
  public static func target(
    position: Double, duration: Double?, ads: [FoundAd]
  ) -> (to: Double, known: FoundAd?) {
    let place = position.isFinite ? position : 0
    if let (first, chained) = holder(of: place, in: ads) {
      let last = chained.last ?? first
      return (max(place, AdSkipper.target(for: last, duration: duration)), first)
    }
    var to = place + jumpSeconds
    if let duration, duration.isFinite, duration > 0 { to = min(to, duration - endMargin) }
    return (max(place, to), nil)
  }

  /// The ad that holds `place` (from `leadSeconds` before its start to its end) and the ads that
  /// follow it within half a second, in order. Nil when no ad holds it.
  static func holder(of place: Double, in ads: [FoundAd]) -> (FoundAd, [FoundAd])? {
    let sorted = ads.sorted { $0.start < $1.start }
    guard let first = sorted.first(where: { $0.start - leadSeconds <= place && place < $0.end })
    else { return nil }
    var chained: [FoundAd] = []
    var end = first.end
    for next in sorted where next.start > first.start && next != first {
      if next.start <= end + AdSkipper.chainGap && next.end > end {
        chained.append(next)
        end = next.end
      }
    }
    return (first, chained)
  }

  /// An automatic skip counts as "just made" for this long, and a tap within `justAfterReach` of
  /// its target is the listener catching up with it, not asking for another skip.
  public static let justSkippedSeconds = 3.0
  public static let justAfterReach = 3.0
  /// A tap this far before the last skip's target still counts as catching up with it.
  public static let justBeforeReach = 0.5

  /// What a tap on Skip ad does.
  public enum Action: Equatable, Sendable {
    /// An ad was just skipped and the playhead is still at its end: stay where the playhead is.
    case nothing(at: Double)
    /// The playhead is in a known ad: skip it like an automatic skip, with its Undo.
    case skip(AdSkip)
    /// No ad is known there: go to this place and note a miss.
    case miss(to: Double)
  }

  /// Whether a tap at `place` is the listener catching up with the skip just made.
  static func isJustAfter(_ place: Double, lastSkip: AdSkip?, age: Double) -> Bool {
    guard let lastSkip, age <= justSkippedSeconds else { return false }
    return place >= lastSkip.target - justBeforeReach && place < lastSkip.target + justAfterReach
  }

  /// What the tap does at `position`, by the episode's ads `file` (nil when it has none), the
  /// switches, and the last skip (`lastSkip`, made `lastSkipAge` seconds ago, nil when none).
  /// A known ad is skipped whatever the switches say. A jump ahead that lands inside an ad the
  /// switches skip (and that was not undone) goes to the end of that ad instead.
  public static func decide(
    position: Double, duration: Double?, file: AdsFile?, settings: AdSkipSettings,
    lastSkip: AdSkip?, lastSkipAge: Double
  ) -> Action {
    let place = position.isFinite ? position : 0
    if isJustAfter(place, lastSkip: lastSkip, age: lastSkipAge) { return .nothing(at: place) }
    let trims = file?.trims ?? []
    let ads = (file?.ads ?? []).map { $0.trimmed(by: trims) }.filter { $0.end > $0.start }
    if let (first, chained) = holder(of: place, in: ads) {
      let target = AdSkipper.target(for: chained.last ?? first, duration: duration)
      return .skip(AdSkip(ad: first, target: max(place, target), chained: chained))
    }
    let ahead = target(position: place, duration: duration, ads: []).to
    let landing = AdSkipper(file: file, settings: settings).landing(for: ahead, duration: duration)
    return .miss(to: landing)
  }
}
