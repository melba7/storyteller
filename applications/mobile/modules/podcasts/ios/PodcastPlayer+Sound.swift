// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Voice boost and silence trimming on the one AVPlayer. The listener's choices (in the playback
// settings) and a show's own (in show-settings.json) give the strengths; a show's own wins.
//
// Boost is an audio mix with a tap on the item (VoiceBoostTap), made for a download and tried
// for a stream, where nothing is changed if the audio track can't be tapped.
//
// Trimming is for downloads only. The first time an episode with trimming on is loaded, its
// file is read once for its silent gaps (SilenceAnalyzer) and they are saved next to it. Then
// it works like ad skipping: boundary time observers at the gaps coming up, in a window of two
// minutes at a time, and a jump to the end of the gap when playback reaches one. The rules are
// PodcastPlayback's TrimSkipper. An ad's skip wins: gaps in or next to a sure ad are not trimmed.

import AVFoundation
import Foundation
import PodcastAds
import PodcastDownloads
import PodcastPlayback

/// The seconds trimming has saved, kept in the app's defaults so a stats screen can read them.
enum TrimSavingsStore {
  private static let key = "podcasts.trim.savedSeconds"

  static var seconds: Double { UserDefaults.standard.double(forKey: key) }

  static func add(_ saved: Double) {
    var savings = TrimSavings(seconds: seconds)
    savings.add(saved)
    UserDefaults.standard.set(savings.seconds, forKey: key)
  }
}

@MainActor
final class PodcastSound {
  /// How far ahead boundary observers are set, and how close to the window's end they are
  /// set again.
  private static let window = 120.0
  private static let refill = 15.0

  private unowned let owner: PodcastPlayer
  private var episodeId: String?
  private var silenceStore: SilenceStore?
  private var adsStore: AdsStore?
  private var file: URL?
  private var skipper = TrimSkipper(gaps: [], strength: .off)
  private var analyzing: Set<String> = []
  private var observer: Any?
  private var ticker: Any?
  private var windowStart = 0.0
  private var windowEnd = 0.0
  private var boostItem: AVPlayerItem?
  private var boostApplied: BoostStrength?
  private var boostTask: Task<Void, Never>?
  /// Where the episode was told to start, until the player's own clock has caught up.
  private var startHint: Double?

  init(_ owner: PodcastPlayer) { self.owner = owner }

  // MARK: The strengths

  var boostStrength: BoostStrength {
    .effective(
      show: owner.showState.settings.voiceBoost, listener: PlaybackSettingsStore.current.voiceBoost)
  }

  var trimStrength: TrimStrength {
    .effective(
      show: owner.showState.settings.trimSilence,
      listener: PlaybackSettingsStore.current.trimSilence)
  }

  // MARK: What the player tells us

  /// An episode was loaded, to start at `position`.
  func begin(_ id: String, startingAt position: Double) {
    startHint = position
    removeMarkers()
    episodeId = id
    skipper = TrimSkipper(gaps: [], strength: .off)
    silenceStore = nil
    adsStore = nil
    file = PodcastDownloader.shared.localFile(for: id)
    if let downloads = PodcastDownloader.shared.store, let entry = downloads.entry(for: id),
      case .downloaded(_, let sha, _, _) = entry.state, let folder = try? downloads.folder(for: id)
    {
      silenceStore = SilenceStore(folder: folder, sha256: sha)
      adsStore = AdsStore(folder: folder, sha256: sha)
    }
    boostItem = nil
    boostApplied = nil
    startTicker()
    refresh()
  }

  /// A choice changed (the listener's or the loaded show's), or the episode was just loaded.
  func refresh() {
    applyBoost()
    updateTrimming()
  }

  /// The playhead was moved by the listener or a lock screen button.
  func seeked(to position: Double) {
    startHint = nil
    skipper.seeked(to: position)
    setMarkers(from: position)
  }

  // MARK: Boost

  private func applyBoost() {
    guard let item = owner.player.currentItem else { return }
    let strength = boostStrength
    if boostItem === item, boostApplied == strength { return }
    boostItem = item
    boostApplied = strength
    boostTask?.cancel()
    boostTask = Task { @MainActor [weak self, weak item] in
      guard let item else { return }
      let mix = await VoiceBoostTap.audioMix(for: item.asset, strength: strength)
      // Only if this is still the item and the choice the listener wants.
      guard !Task.isCancelled, let self, self.owner.player.currentItem === item,
        self.boostApplied == strength
      else { return }
      item.audioMix = mix
    }
  }

  // MARK: Trimming

  private func updateTrimming() {
    guard trimStrength != .off, let silenceStore, let file, let id = episodeId else {
      skipper = TrimSkipper(gaps: [], strength: .off)
      removeMarkers()
      return
    }
    if let saved = silenceStore.load() {
      let ads = avoidedStretches()
      skipper = TrimSkipper(gaps: saved.gaps, strength: trimStrength, avoiding: ads)
      skipper.seeked(to: startHint ?? owner.position)
      setMarkers(from: startHint ?? owner.position)
    } else {
      skipper = TrimSkipper(gaps: [], strength: .off)
      removeMarkers()
      analyze(file: file, store: silenceStore, id: id)
    }
  }

  /// Reads the file once, in the background, then starts trimming if it is still wanted.
  private func analyze(file: URL, store: SilenceStore, id: String) {
    guard !analyzing.contains(id) else { return }
    analyzing.insert(id)
    Task { @MainActor [weak self] in
      do {
        _ = try await SilenceAnalyzer.analyze(file: file, store: store)
      } catch {
        NSLog("Podcasts: the silence of an episode could not be read: \(error)")
      }
      guard let self else { return }
      self.analyzing.remove(id)
      // A failed read is not tried again until the episode is loaded again.
      if self.episodeId == id, store.load() != nil { self.updateTrimming() }
    }
  }

  /// The sure ads, which the ad skipping owns.
  private func avoidedStretches() -> [ClosedRange<Double>] {
    guard let file = adsStore?.load(detector: PodcastAdFinder.detectorName) else { return [] }
    return file.ads.filter { $0.confidence == .sure && $0.end > $0.start }
      .map { $0.start...$0.end }
  }

  // MARK: Markers

  private func setMarkers(from position: Double) {
    removeMarkers()
    windowStart = position
    windowEnd = position + Self.window
    let times = skipper.boundaryTimes(after: position, window: Self.window).map {
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

  /// Once a second: sets the markers again when playback has moved on (or been moved by an ad
  /// skip) out of the window they cover.
  private func startTicker() {
    guard ticker == nil else { return }
    ticker = owner.player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
  }

  private func tick() {
    guard !skipper.trims.isEmpty else { return }
    startHint = nil
    let position = owner.position
    if position < windowStart || position > windowEnd - Self.refill { setMarkers(from: position) }
  }

  /// Playback crossed the start of a gap: jump to its end, unless the listener got there by a
  /// seek.
  private func reachedMarker() {
    guard owner.wantsToPlay else { return }
    let rate = Double(owner.player.rate)
    guard let trim = skipper.reached(position: owner.position, rate: rate > 0 ? rate : 1)
    else { return }
    owner.player.seek(
      to: CMTime(seconds: trim.target, preferredTimescale: 600), toleranceBefore: .zero,
      toleranceAfter: .zero)
    owner.publish(positionOverride: trim.target)
    // The time saved is the time it would have taken to play the gap, at the speed in use.
    TrimSavingsStore.add(trim.saved / max(1, owner.speed.value))
  }
}

@MainActor
extension PodcastPlayer {
  /// The app wrote the show settings again: takes the loaded show's sound choices from them
  /// and applies them now. Its speed, intro and outro stay as they were for this episode.
  func applyShowSound() {
    guard let showId = current?.showId else { return }
    let saved = ShowSettingsFile.load(from: ShowSettingsStore.url)[showId] ?? ShowPlaybackSettings()
    showState.settings.voiceBoost = saved.voiceBoost
    showState.settings.trimSilence = saved.trimSilence
    sound.refresh()
  }
}
