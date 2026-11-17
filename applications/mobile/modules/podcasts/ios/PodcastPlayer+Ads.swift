// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Skips the saved ads of the downloaded episode the player has loaded. It sets a boundary time
// observer at each ad's start and jumps to the ad's end when playback crosses it, so it works
// with the screen locked and no JavaScript. The rules (which ads, not after a seek, Undo) are
// `AdSkipper` in PodcastAds. A streamed episode is never skipped, because a stream can carry
// other ads than the download that was checked.

import AVFoundation
import Foundation
import PodcastAds
import PodcastDownloads

/// The listener's two switches, kept in the app's defaults so the player reads them with no
/// JavaScript running.
enum AdSkipDefaults {
  private static let adsKey = "podcasts.ads.skipAds"
  private static let plugsKey = "podcasts.ads.skipOwnPlugs"

  /// Both are on until the listener turns them off.
  static var settings: AdSkipSettings {
    get {
      let defaults = UserDefaults.standard
      return AdSkipSettings(
        skipAds: defaults.object(forKey: adsKey) as? Bool ?? true,
        skipOwnPlugs: defaults.object(forKey: plugsKey) as? Bool ?? true)
    }
    set {
      UserDefaults.standard.set(newValue.skipAds, forKey: adsKey)
      UserDefaults.standard.set(newValue.skipOwnPlugs, forKey: plugsKey)
    }
  }
}

@MainActor
final class PodcastAdSkipping {
  private unowned let owner: PodcastPlayer
  private var skipper = AdSkipper(file: nil, settings: AdSkipSettings())
  private var store: AdsStore?
  private var episodeId: String?
  private var observer: Any?

  init(_ owner: PodcastPlayer) { self.owner = owner }

  private var now: Double { ProcessInfo.processInfo.systemUptime }

  /// The listener's switches, with the loaded show's own choices where it has them (P5a).
  private var settings: AdSkipSettings {
    let show = owner.showState.settings
    return AdSkipDefaults.settings.overridden(skipAds: show.skipAds, skipOwnPlugs: show.skipPlugs)
  }

  // MARK: What the player tells us

  /// An episode was loaded, to start at `position`. Only a download has ads to skip.
  func begin(_ id: String, startingAt position: Double) {
    removeMarkers()
    episodeId = id
    store = nil
    skipper = AdSkipper(file: nil, settings: settings)
    if let downloads = PodcastDownloader.shared.store, let entry = downloads.entry(for: id),
      case .downloaded(_, let sha, _, _) = entry.state, let folder = try? downloads.folder(for: id)
    {
      store = AdsStore(folder: folder, sha256: sha)
      skipper.replace(file: store?.load(detector: PodcastAdFinder.detectorName))
    }
    skipper.seeked(to: position)
    setMarkers()
  }

  /// The playhead was moved by the listener, a lock screen button or Undo.
  func seeked(to position: Double) { skipper.seeked(to: position) }

  /// The ads file or the switches changed (ads were just found, or a switch was turned).
  func refresh() {
    guard episodeId != nil else { return }
    skipper.apply(settings: settings)
    skipper.replace(file: store?.load(detector: PodcastAdFinder.detectorName))
    setMarkers()
  }

  /// The listener tapped Undo on the note. False when there is nothing to undo any more.
  func undo() -> Bool {
    guard let ad = skipper.undo(now: now), let episodeId else { return false }
    store?.markUndone(detector: PodcastAdFinder.detectorName, adStart: ad.start)
    StatsStore.shared.undoAdSkip()
    owner.seek(to: ad.start)
    if !owner.wantsToPlay { owner.play() }
    owner.sink?("onAdUndone", ["episodeId": episodeId, "start": ad.start])
    return true
  }

  // MARK: Markers

  private func setMarkers() {
    removeMarkers()
    let times = skipper.boundaryTimes.map {
      NSValue(time: CMTime(seconds: $0, preferredTimescale: 600))
    }
    guard !times.isEmpty else { return }
    observer = owner.player.addBoundaryTimeObserver(forTimes: times, queue: .main) { [weak self] in
      Task { @MainActor in self?.reachedMarker() }
    }
  }

  private func removeMarkers() {
    if let observer { owner.player.removeTimeObserver(observer) }
    observer = nil
  }

  /// Playback crossed an ad's start: jump to its end, unless the listener got there by a seek.
  private func reachedMarker() {
    guard let episodeId, owner.wantsToPlay else { return }
    let rate = Double(owner.player.rate)
    var duration: Double?
    if let seconds = owner.player.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 {
      duration = seconds
    }
    guard
      let skip = skipper.reached(
        position: owner.position, rate: rate > 0 ? rate : 1, duration: duration, now: now)
    else { return }
    owner.noteSaved(.ads, audioSeconds: skip.target - owner.position)
    owner.player.seek(
      to: CMTime(seconds: skip.target, preferredTimescale: 600), toleranceBefore: .zero,
      toleranceAfter: .zero)
    owner.publish(positionOverride: skip.target)
    owner.sink?(
      "onAdSkipped",
      [
        "episodeId": episodeId, "start": skip.ad.start, "end": skip.ad.end,
        "length": skip.ad.end - skip.ad.start,
      ])
  }
}
