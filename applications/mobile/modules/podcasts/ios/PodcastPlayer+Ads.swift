// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Skips the saved ads of the downloaded episode the player has loaded. It sets a boundary time
// observer at each ad's start and jumps to the ad's end when playback crosses it, so it works
// with the screen locked and no JavaScript. The rules (which ads, not after a seek, Undo) are
// `AdSkipper` in PodcastAds. A streamed episode is never skipped, because a stream can carry
// other ads than the download that was checked. An episode that plays through its own download
// (PodcastStreamDownload) is the same file, so its ads are skipped once the download is filed.

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
    skipper = AdSkipper(file: nil, settings: settings)
    store = Self.downloadedStore(id)
    skipper.replace(file: store?.best(detector: PodcastAdFinder.detectorName))
    // The start is the app's choice, not a seek by the listener, so an ad that begins later is
    // still skipped, and one that holds the start is skipped now.
    let skip = skipper.started(at: position, duration: owner.currentDuration, now: now)
    setMarkers()
    if let skip { jump(skip, from: position) }
  }

  /// The playhead was moved by the listener, a lock screen button or Undo.
  func seeked(to position: Double) { skipper.seeked(to: position) }

  /// The ads file or the switches changed (ads were just found, or a switch was turned).
  func refresh() {
    guard let episodeId else { return }
    // An episode playing through its own download has a store once the download is filed, but
    // only for the file this download filed: another download of the episode (with other ads
    // inserted) is not the audio that is heard.
    // While it streams, the head scan's ads are under a made-up name; once filed, the real hash.
    if let loader = owner.streamDownload, loader.episodeId == episodeId,
      let found = loader.head.adsStore
    {
      store = found
    }
    skipper.apply(settings: settings)
    // An ad found while it plays, with the playhead inside it, is left at once (unless the
    // listener seeked into it, or it was undone). While a seek is on its way the playhead still
    // reads the old place, so nothing is left then; the seek's landing looks again.
    let playhead = owner.wantsToPlay && !owner.seekPending ? owner.position : nil
    let leave = skipper.replace(
      file: store?.best(detector: PodcastAdFinder.detectorName), playhead: playhead,
      duration: owner.currentDuration, now: now)
    setMarkers()
    if let leave { jump(leave) }
    // Silence trimming keeps out of the ads that are skipped, so it reads them again too.
    owner.sound.refresh()
  }

  /// The ads store of a downloaded episode, or nil while it is not downloaded. With `sha256`,
  /// only when the download is that file.
  private static func downloadedStore(_ id: String, sha256 expected: String? = nil) -> AdsStore? {
    guard let downloads = PodcastDownloader.shared.store, let entry = downloads.entry(for: id),
      case .downloaded(_, let sha, _, _) = entry.state, expected == nil || expected == sha,
      let folder = try? downloads.folder(for: id)
    else { return nil }
    return AdsStore(folder: folder, sha256: sha)
  }

  /// The listener tapped Undo on the note. False when there is nothing to undo any more.
  func undo() -> Bool {
    guard let skip = skipper.undoSkip(now: now), let episodeId else { return false }
    let ad = skip.ad
    // The ads that were skipped with it (an ad and then the hosts' plug) are undone too.
    for undone in [ad] + skip.chained {
      store?.markUndone(detector: PodcastAdFinder.detectorName, adStart: undone.start)
    }
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
    guard episodeId != nil, owner.wantsToPlay else { return }
    let rate = Double(owner.player.rate)
    var duration: Double?
    if let seconds = owner.player.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 {
      duration = seconds
    }
    guard
      let skip = skipper.reached(
        position: owner.position, rate: rate > 0 ? rate : 1, duration: duration, now: now)
    else { return }
    jump(skip)
  }

  /// Seeks to the end of the skipped ad (and the ones that follow it at once) and tells the app.
  private func jump(_ skip: AdSkip, from place: Double? = nil) {
    guard let episodeId else { return }
    PodcastTimeline.firstSkip(episodeId)
    owner.noteSaved(.ads, audioSeconds: skip.target - (place ?? owner.position))
    owner.movePlayhead(to: skip.target)
    owner.publish(positionOverride: skip.target)
    owner.sink?(
      "onAdSkipped",
      [
        "episodeId": episodeId, "start": skip.ad.start, "end": skip.end,
        "length": skip.end - skip.ad.start,
      ])
  }
}
