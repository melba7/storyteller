// LOFI-FORK: how each ad skip ended, for the skip log (see FORK.md). Plain values, no
// AVFoundation. The player tells the watch what happened (a skip, Undo, a trim, a seek by the
// listener) and gets back the log entries that are finished. `now` is any steady clock in
// seconds, the same one the player gives `AdSkipper`.
import Foundation

public struct SkipWatch: Sendable {
  /// A skip with no complaint for this long is kept. It is the time `AdSkipper` allows for a trim.
  public static let settleSeconds = AdSkipper.tooFarSeconds
  /// A forward jump by the listener is at least this long and at most this long.
  public static let jumpSizes = 10.0...180.0
  /// This many forward jumps ...
  public static let jumpsForMissed = 3
  /// ... within this many seconds are logged as an ad that may have been missed.
  public static let jumpWindow = 60.0

  private struct Pending: Sendable {
    var skip: AdSkip
    var context: SkipContext
    var at: Double
  }

  private struct Jump: Sendable {
    var at: Double
    var from: Double
    var context: SkipContext
  }

  /// The last skip, waiting to see how it ends.
  private var pending: Pending?
  private var jumps: [Jump] = []

  public init() {}

  private mutating func finish(_ outcome: SkipOutcome) -> [SkipLogEntry] {
    guard let pending else { return [] }
    self.pending = nil
    return [
      SkipLogEntry(
        context: pending.context, start: pending.skip.ad.start, end: pending.skip.end,
        kind: pending.skip.ad.kind, confidence: pending.skip.ad.confidence, outcome: outcome)
    ]
  }

  /// The player skipped an ad. The skip before it, if it was still waiting, was kept: the player
  /// only watches the last skip for a trim or an Undo.
  public mutating func skipped(
    _ skip: AdSkip, context: SkipContext, now: Double
  ) -> [SkipLogEntry] {
    let earlier = finish(.kept)
    pending = Pending(skip: skip, context: context, at: now)
    return earlier
  }

  /// Time has passed: a skip that is more than `settleSeconds` old with no complaint is kept.
  public mutating func settle(now: Double) -> [SkipLogEntry] {
    guard let pending, now - pending.at > Self.settleSeconds else { return [] }
    return finish(.kept)
  }

  /// The listener undid the last skip.
  public mutating func undone() -> [SkipLogEntry] { finish(.undone) }

  /// `AdSkipper` found the listener went back into the last skip and made `trim`. It decides that,
  /// not this watch, so the trim is trusted whatever the time is.
  public mutating func trimmed(_ trim: AdTrim) -> [SkipLogEntry] {
    guard let pending else { return [] }
    return finish(.trimmed(seconds: max(0, pending.skip.target - trim.end)))
  }

  /// The listener moved the playhead from `from` to `to`. Call it after `trimmed` for the same
  /// seek: a trim has ended the skip already, so what is left is a seek back that is not a trim.
  /// `knownAds` are the ads the player knows, so a jump out of one is not a missed ad.
  public mutating func seeked(
    from: Double, to: Double, knownAds: [FoundAd], context: SkipContext, now: Double
  ) -> [SkipLogEntry] {
    var done = settle(now: now)
    if let pending, to < from, to < pending.skip.target {
      done += finish(.seekBack(seconds: from - to))
    }
    return done + forwardJump(from: from, to: to, knownAds: knownAds, context: context, now: now)
  }

  private mutating func forwardJump(
    from: Double, to: Double, knownAds: [FoundAd], context: SkipContext, now: Double
  ) -> [SkipLogEntry] {
    guard Self.jumpSizes.contains(to - from),
      !knownAds.contains(where: { $0.start <= from && from < $0.end })
    else { return [] }
    jumps.removeAll { now - $0.at > Self.jumpWindow || $0.context.episode != context.episode }
    jumps.append(Jump(at: now, from: from, context: context))
    guard jumps.count >= Self.jumpsForMissed, let first = jumps.first else { return [] }
    jumps = []
    var entry = SkipLogEntry(
      context: context, start: first.from, end: to, kind: nil, confidence: nil,
      outcome: .maybeMissed)
    entry.source = nil
    entry.tapToSkip = nil
    return [entry]
  }
}
