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
    let sorted = ads.sorted { $0.start < $1.start }
    if let first = sorted.first(where: { $0.start - leadSeconds <= place && place < $0.end }) {
      var last = first
      for next in sorted where next.start > first.start && next != first {
        if next.start <= last.end + AdSkipper.chainGap && next.end > last.end { last = next }
      }
      return (max(place, AdSkipper.target(for: last, duration: duration)), first)
    }
    var to = place + jumpSeconds
    if let duration, duration.isFinite, duration > 0 { to = min(to, duration - endMargin) }
    return (max(place, to), nil)
  }
}
