// LOFI-FORK: replays a stream played from the start with the player's own skip rules (see FORK.md
// and AdSkipping.swift). Foundation only.
import Foundation

/// What the phone knows about the ads at one wall second since the tap.
public struct StreamSnapshot: Equatable, Sendable {
  public var at: Double
  public var ads: [FoundAd]

  public init(at: Double, ads: [FoundAd]) {
    self.at = at
    self.ads = ads
  }
}

/// A jump the player made: out of the stretch from `from` to `to`, which was an ad of `kind`.
public struct StreamJump: Equatable, Sendable {
  public var from: Double
  public var to: Double
  public var kind: AdKind
}

public enum StreamReplay {
  /// A listener taps play on a stream at wall second 0, starts hearing it at `startsAt` and
  /// never touches the phone again. A real `AdSkipper` decides each jump, from the snapshots as
  /// they arrive and when the playhead crosses an ad's start. A jump costs `seek` seconds of
  /// silence. The replay ends at `duration`, the end of the episode. `snapshots` may be in any
  /// order.
  public static func play(
    snapshots rawSnapshots: [StreamSnapshot], startsAt: Double, duration: Double,
    settings: AdSkipSettings = AdSkipSettings(), seek: Double = 1.0
  ) -> [StreamJump] {
    guard duration > 0, startsAt.isFinite else { return [] }
    let snapshots = rawSnapshots.sorted { $0.at < $1.at }
    var next = 0
    var jumps: [StreamJump] = []
    // What was known when the playback started is in the file the player loads.
    var known: AdsFile?
    while next < snapshots.count, snapshots[next].at <= startsAt {
      known = file(snapshots[next].ads, duration: duration)
      next += 1
    }
    var skipper = AdSkipper(file: known, settings: settings)
    var wall = startsAt
    var head = 0.0
    func jump(_ skip: AdSkip) {
      guard skip.target > head else { return }
      jumps.append(StreamJump(from: head, to: skip.target, kind: skip.ad.kind))
      head = skip.target
      wall += seek
    }
    if let skip = skipper.started(at: 0, duration: duration, now: wall) { jump(skip) }
    var crossed = -Double.infinity  // the last marker that was handled
    while head < duration - 1e-9 {
      let marker = skipper.boundaryTimes.filter { $0 > crossed && $0 > head - 1e-9 }.min()
      let markerWall = marker.map { wall + max(0, $0 - head) } ?? .infinity
      let snapWall = next < snapshots.count ? snapshots[next].at : .infinity
      let endWall = wall + (duration - head)
      if min(markerWall, snapWall) >= endWall { break }
      if snapWall <= markerWall {
        head = min(duration, head + max(0, snapWall - wall))
        wall = max(wall, snapWall)
        let file = file(snapshots[next].ads, duration: duration)
        next += 1
        if let skip = skipper.replace(file: file, playhead: head, duration: duration, now: wall) {
          jump(skip)
        }
      } else if let marker {
        head = max(head, marker)
        wall = markerWall
        crossed = marker
        if let skip = skipper.reached(position: head, rate: 1, duration: duration, now: wall) {
          jump(skip)
        }
      }
    }
    return jumps
  }

  private static func file(_ ads: [FoundAd], duration: Double) -> AdsFile {
    AdsFile(
      sha256: "stream", detector: "stream", detectorVersion: "1", osVersion: "", duration: duration,
      ads: ads)
  }

  /// The jumps as found ads, for the bar to score exactly as it scores found ads.
  public static func asAds(_ jumps: [StreamJump]) -> [FoundAd] {
    jumps.map {
      FoundAd(
        start: $0.from, end: $0.to, kind: $0.kind, advertiser: "", confidence: .sure, firstWords: "")
    }
  }
}
