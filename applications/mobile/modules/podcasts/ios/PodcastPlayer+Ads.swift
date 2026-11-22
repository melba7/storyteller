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
import PodcastTranscripts

/// The listener's four switches, kept in the app's defaults so the player reads them with no
/// JavaScript running.
enum AdSkipDefaults {
  private static let adsKey = "podcasts.ads.skipAds"
  private static let plugsKey = "podcasts.ads.skipOwnPlugs"
  private static let promosKey = "podcasts.ads.skipPromos"
  private static let creditsKey = "podcasts.ads.skipCredits"

  /// Ads, the hosts' plugs and promos are on until the listener turns them off; credits are off
  /// until they turn them on.
  static var settings: AdSkipSettings {
    get {
      let defaults = UserDefaults.standard
      return AdSkipSettings(
        skipAds: defaults.object(forKey: adsKey) as? Bool ?? true,
        skipOwnPlugs: defaults.object(forKey: plugsKey) as? Bool ?? true,
        skipPromos: defaults.object(forKey: promosKey) as? Bool ?? true,
        skipCredits: defaults.object(forKey: creditsKey) as? Bool ?? false)
    }
    set {
      UserDefaults.standard.set(newValue.skipAds, forKey: adsKey)
      UserDefaults.standard.set(newValue.skipOwnPlugs, forKey: plugsKey)
      UserDefaults.standard.set(newValue.skipPromos, forKey: promosKey)
      UserDefaults.standard.set(newValue.skipCredits, forKey: creditsKey)
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

  /// Whether Skip ads is on for the loaded show.
  var skipsAds: Bool { settings.skipAds }

  /// Whether an ads file was saved for the loaded download (checked, with or without ads).
  var hasSavedAds: Bool { store?.best(detector: PodcastAdFinder.detectorName) != nil }

  /// The head scan of the stream the loaded episode plays through, while it does.
  private var streamHead: PodcastStreamHead? {
    guard let loader = owner.streamDownload, loader.episodeId == episodeId else { return nil }
    return loader.head
  }

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

  /// The playhead was moved by the listener, a lock screen button or Undo. A move back into the
  /// ad that was just skipped says the skip went too far: that ad ends there from now on. The
  /// trim is saved with the ads and counted; the skipper already uses it.
  func seeked(to position: Double) {
    if let trim = skipper.backSeek(to: position, now: now) {
      // A stream's ads file is written by its head scan too, so the head takes the trim first.
      if streamHead?.markTrimmed(trim) != true {
        store?.markTrimmed(detector: PodcastAdFinder.detectorName, trim)
      }
      StatsStore.shared.countAd(.tooFar)
      PodcastSkipLogger.shared.trimmed(trim)
      let kind = skipper.ads.first { $0.start == trim.adStart }?.kind
      note(.trimmed, start: trim.adStart, end: trim.end, kind: kind)
    }
    PodcastSkipLogger.shared.seeked(to: position, knownAds: skipper.ads)
    skipper.seeked(to: position)
  }

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
      if streamHead?.markUndone(undone) != true {
        store?.markUndone(detector: PodcastAdFinder.detectorName, adStart: undone.start)
      }
    }
    StatsStore.shared.undoAdSkip()
    StatsStore.shared.countAd(.undone)
    // An ad the listener did not want skipped is forgotten by the memory too, so it is not found
    // again by its words in the next episode.
    PodcastKnownAds.shared.forget(
      episodeId: episodeId, ads: ([ad] + skip.chained).map { (start: $0.start, end: $0.end) },
      heard: owner.streamDownload?.head.memory.words ?? [])
    PodcastSkipLogger.shared.undone()
    note(.undone, start: ad.start, end: skip.end, kind: ad.kind, seconds: skip.end - ad.start)
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
    StatsStore.shared.countAd(.skipped)
    PodcastSkipLogger.shared.skipped(skip, episodeId: episodeId)
    note(
      .skipped, start: skip.ad.start, end: skip.end, kind: skip.ad.kind,
      seconds: skip.end - skip.ad.start)
    owner.movePlayhead(to: skip.target)
    owner.publish(positionOverride: skip.target)
    owner.sink?(
      "onAdSkipped",
      [
        "episodeId": episodeId, "start": skip.ad.start, "end": skip.end,
        "length": skip.end - skip.ad.start, "kind": skip.ad.kind.rawValue,
      ])
  }

  /// Tells the Mac's notes and the tally what happened to the loaded episode's ads.
  private func note(
    _ what: PhoneNote.What, start: Double, end: Double?, kind: AdKind?, seconds: Double = 0
  ) {
    guard let episodeId else { return }
    PodcastAdNotes.shared.record(
      what, episode: episodeId, show: owner.current?.showId, start: start, end: end, kind: kind,
      seconds: seconds)
  }

  /// The listener tapped Skip ad. Goes to the end of the ad the playhead is in (or about to
  /// enter) and the ads that follow it at once, or 30 seconds ahead when no ad is known there,
  /// and says where and whether an ad was known. Nil when nothing is loaded.
  ///
  /// It moves the playhead as a listener's seek does (`PodcastPlayer.seek`), so the skipper is
  /// told. `seeked(to:)` then finds no way to read this as the listener going back into the
  /// ad: the target is never behind the playhead, and `backSeek` only trims a seek that lands
  /// before where the last skip landed and inside that skipped stretch, where a target at the
  /// end of an ad (already trimmed by the file's trims) or ahead of the playhead is not. The
  /// target is the end of the ads, so the ads it left are not "entered by the seek" and nothing
  /// skips again: the one case that plays an ad is a 30 second jump that lands inside another
  /// known ad, which the listener's own seek would do as well.
  func skipAdNow() -> (to: Double, known: Bool)? {
    guard episodeId != nil, owner.current != nil else { return nil }
    let place = owner.place
    let file = store?.best(detector: PodcastAdFinder.detectorName)
    let result = AdSkipNow.target(position: place, duration: owner.currentDuration, file: file)
    if let known = result.known {
      note(.skipped, start: known.start, end: result.to, kind: known.kind, seconds: result.to - place)
    } else {
      note(.missed, start: place, end: result.to, kind: nil)
    }
    owner.seek(to: result.to)
    return (result.to, result.known != nil)
  }
}
