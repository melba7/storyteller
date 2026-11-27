// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Skips the saved ads of the downloaded episode the player has loaded. It sets a boundary time
// observer at each ad's start and jumps to the ad's end when playback crosses it, so it works
// with the screen locked and no JavaScript. The rules (which ads, not after a seek, Undo) are
// `AdSkipper` in PodcastAds. A streamed episode is never skipped, because a stream can carry
// other ads than the download that was checked. An episode that plays through its own download
// (PodcastStreamDownload) is the same file, so its ads are skipped once the download is filed.
// The questions about stretches it is not sure of are asked in PodcastPlayer+Ask.swift.

import AVFoundation
import Foundation
import PodcastAds
import PodcastDownloads
import PodcastTranscripts

@MainActor
final class PodcastAdSkipping {
  // Not private: the answers to questions (PodcastPlayer+Ask.swift) skip and note like any skip.
  // Only `skipper` is writable from there (a skip is noted on it); the rest is read.
  unowned let owner: PodcastPlayer
  var skipper = AdSkipper(file: nil, settings: AdSkipSettings())
  private(set) var store: AdsStore?
  private(set) var episodeId: String?
  private var observer: Any?
  /// The last skip that was counted and noted in this episode (see `jump`).
  private var lastNoted = NotedSkip()
  /// The questions of the loaded episode, announced when the playhead enters one.
  private let asking: PodcastAsking

  init(_ owner: PodcastPlayer) {
    self.owner = owner
    asking = PodcastAsking(owner)
  }

  var now: Double { ProcessInfo.processInfo.systemUptime }

  /// Whether any sort of ad is skipped for the loaded show (the sponsor, plug, promo or credits
  /// switch, under the show's own choices).
  var skipsAds: Bool { settings.skipsAnySort }

  /// Whether an ads file was saved for the loaded download (checked, with or without ads).
  var hasSavedAds: Bool { store?.best(detector: PodcastAdFinder.detectorName) != nil }

  /// The head scan of the stream the loaded episode plays through, while it does.
  private var streamHead: PodcastStreamHead? {
    guard let loader = owner.streamDownload, loader.episodeId == episodeId else { return nil }
    return loader.head
  }

  /// The listener's switches, with the loaded show's own choices where it has them (P5a). Not
  /// private: the tap on skip forward (PodcastPlayer+Tap.swift) decides with the same switches.
  var settings: AdSkipSettings {
    let show = owner.showState.settings
    return AdSkipDefaults.settings.overridden(skipAds: show.skipAds, skipOwnPlugs: show.skipPlugs)
  }

  // MARK: What the player tells us

  /// An episode was loaded, to start at `position`. Only a download has ads to skip. When the
  /// listener `chosen` the place (Play from on an ad row, a bookmark, a search result), an ad
  /// that holds it is played, as after a seek.
  func begin(_ id: String, startingAt position: Double, chosen: Bool = false) {
    removeMarkers()
    episodeId = id
    lastNoted = NotedSkip()
    skipper = AdSkipper(file: nil, settings: settings)
    store = Self.downloadedStore(id)
    let saved = store?.best(detector: PodcastAdFinder.detectorName)
    skipper.replace(file: saved)
    asking.begin(id, file: saved)
    // The start is the app's choice, not a seek by the listener, so an ad that begins later is
    // still skipped, and one that holds the start is skipped now.
    var skip: AdSkip?
    if chosen {
      skipper.seeked(to: position)
    } else {
      skip = skipper.started(at: position, duration: owner.currentDuration, now: now)
    }
    setMarkers()
    if let skip { jump(skip, from: position) }
  }

  /// The finished episode starts over at `position` (Play on a finished episode): like a load,
  /// the start is the app's choice, so the ad that holds it is skipped.
  func startedOver(at position: Double) {
    guard episodeId != nil else { return }
    lastNoted = NotedSkip()
    if let skip = skipper.started(at: position, duration: owner.currentDuration, now: now) {
      jump(skip, from: position)
    }
  }

  /// Where a move of the playhead to `position` lands without landing inside an ad that is
  /// skipped (the end of that ad, else `position`).
  func landing(for position: Double) -> Double {
    skipper.landing(for: position, duration: owner.currentDuration)
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
      sendAdsChange()
    }
    PodcastSkipLogger.shared.seeked(to: position, knownAds: skipper.ads)
    skipper.seeked(to: position)
  }

  /// Tells the app that the loaded episode's saved ads changed (a trim), so the seek bar's marks
  /// and the ads list read the file again.
  private func sendAdsChange() {
    guard let episodeId,
      let object = PodcastAdFinder.shared.all().first(where: { $0["episodeId"] as? String == episodeId })
    else { return }
    owner.sink?("onAdsChange", object)
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
    let saved = store?.best(detector: PodcastAdFinder.detectorName)
    let leave = skipper.replace(
      file: saved, playhead: playhead, duration: owner.currentDuration, now: now)
    setMarkers()
    asking.update(saved, episode: episodeId)
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
    // The ads that were skipped with it (an ad and then the hosts' plug) are undone too. When the
    // skip holds stretches of the opening lines or the filled holes next to other ads, only those
    // are taken back (`AdSkip.takenBack`): the playhead goes to the first of them and the other
    // ads are skipped again when it reaches them. A skip that a tap carried over a hole takes no
    // ad back: the playhead goes to the hole (`carriedFrom`) and the note blames no finder.
    let back = skip.takenBack
    let ad = back.first ?? skip.ad
    let carriedFrom = skip.carriedFrom
    let wasCarried = carriedFrom != nil
    for undone in back {
      if streamHead?.markUndone(undone) != true {
        store?.markUndone(detector: PodcastAdFinder.detectorName, adStart: undone.start)
      }
    }
    StatsStore.shared.undoAdSkip()
    StatsStore.shared.countAd(.undone)
    // An ad the listener did not want skipped is forgotten by the memory too, so it is not found
    // again by its words in the next episode. The finder that made each ad hears of it (and the
    // guard of its show). Both wait in the finder's queue behind a yes that is still learned.
    let heard = owner.streamDownload?.head.memory.words ?? []
    for undone in back {
      PodcastAdFinder.shared.forgetUndone(
        episodeId, start: undone.start, end: undone.end, heard: heard, source: undone.source)
    }
    PodcastSkipLogger.shared.undone()
    // What the skip put on the tally is what comes off it: only the seconds really jumped. The
    // note names the finder of the ad; an ad that was confirmed by a tap has lost that name.
    note(
      .undone, start: carriedFrom ?? ad.start, end: back.last?.end ?? skip.end,
      kind: wasCarried ? nil : ad.kind, seconds: lastNoted.takeCounted(),
      by: wasCarried || ad.source == AdAsking.source ? nil : ad.source)
    owner.seek(to: carriedFrom ?? ad.start)
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
    // While a seek is on its way the clock still reads the old place: the seek's landing looks
    // again, and a skip made from the old place could be made twice.
    guard episodeId != nil, owner.wantsToPlay, !owner.seekPending else { return }
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
  func jump(_ skip: AdSkip, from place: Double? = nil) {
    guard let episodeId else { return }
    let from = place ?? owner.position
    PodcastTimeline.firstSkip(episodeId)
    owner.noteSaved(.ads, audioSeconds: skip.target - from)
    PodcastSkipLogger.shared.skipped(skip, episodeId: episodeId)
    // An ad that was left in progress and then found again longer is the same ad: it is counted
    // and noted once. The seconds are what this leave took out of the listening.
    if lastNoted.isNew(episode: episodeId, start: skip.ad.start, end: skip.end) {
      StatsStore.shared.countAd(.skipped)
      let jumped = AdTally.seconds(from: from, to: skip.target)
      note(.skipped, start: skip.ad.start, end: skip.end, kind: skip.ad.kind, seconds: jumped)
      lastNoted.counted(seconds: jumped)
    }
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
  func note(
    _ what: PhoneNote.What, start: Double, end: Double?, kind: AdKind?, seconds: Double = 0,
    by: String? = nil
  ) {
    guard let episodeId else { return }
    PodcastAdNotes.shared.record(
      what, episode: episodeId, show: owner.current?.showId, start: start, end: end, kind: kind,
      seconds: seconds, by: by)
  }

  /// The listener tapped Skip ad. Says where the playhead went and whether an ad was known
  /// there. Nil when nothing is loaded. What it does is `AdSkipNow.decide`: nothing right after
  /// an automatic skip (the playhead is at its end), a skip of the known ad the playhead is in
  /// and the ads that follow it, also after a hole of 15 seconds or less (one jump with its note,
  /// stats and Undo, as an automatic skip), or a jump 30 seconds ahead that notes a miss. The jump
  /// is the player's own move, so it is no seek of the listener's: it cannot save a trim of an
  /// earlier ad and it leaves an end-of-chapter sleep timer alone. Where no ad is known and the
  /// playhead is inside a question the phone asked (PodcastPlayer+Ask.swift) the tap is the answer
  /// "yes" instead of a miss. With `onlyInAd`, only the skip of a known ad is made and any other
  /// tap does nothing and gives nil (the answer "yes" to a question that an ad has covered since).
  func skipAdNow(onlyInAd: Bool = false) -> (to: Double, known: Bool)? {
    guard let episodeId, owner.current != nil else { return nil }
    let place = owner.place
    let recent = skipper.lastSkip
    let action = AdSkipNow.decide(
      position: place, duration: owner.currentDuration,
      file: store?.best(detector: PodcastAdFinder.detectorName), settings: settings,
      lastSkip: recent?.skip, lastSkipAge: recent.map { now - $0.at } ?? .infinity)
    switch action {
    case .nothing(let at):
      if onlyInAd { return nil }
      return (at, true)
    case .skip(let skip):
      skipper.noteSkip(skip, now: now)
      jump(skip, from: place)
      return (skip.target, true)
    case .miss(let to):
      if onlyInAd { return nil }
      if let ask = asking.live(at: place),
        answerQuestion(episodeId: episodeId, start: ask.start, isAd: true)
      {
        return (owner.place, true)
      }
      note(.missed, start: place, end: to, kind: nil)
      owner.movePlayheadByPlayer(to: to)
      return (to, false)
    }
  }
}
