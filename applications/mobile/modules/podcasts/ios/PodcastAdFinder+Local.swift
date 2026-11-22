// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The ad finder's own layers, which need no Apple model: the word rules and the small model the
// Mac trained (`LocalAds`), and the sounds the Mac taught, looked for in the downloaded file.
// Their ads go into the episode's ads files first, whatever the model can do afterwards. All of
// it runs in the finder's own background task, never on the main thread.
import Foundation
import PodcastAds
import PodcastAdsOnDevice
import PodcastTranscripts

extension PodcastAdFinder {
  // MARK: The local ads of an episode

  /// The ads the phone finds by itself in a whole transcript: the words (rules and the small
  /// model) and the sounds of the downloaded file, joined. No sponsor names are passed: the
  /// finder has no cheap way to the episode's notes (the head scan has them from the player).
  func localAds(_ id: String, ads: AdsStore, transcript: Transcript) -> [FoundAd] {
    let words = PodcastTeaching.shared.files.local.ads(
      transcript: transcript, episodeDuration: transcript.duration)
    return joined(id, words: words, sounds: soundLook(id, sha256: ads.sha256))
  }

  /// The same for a transcript that is still being made, or its head (`limit` seconds).
  func localAds(
    _ id: String, ads: AdsStore, partial: PartialTranscript, limit: Double?
  ) -> [FoundAd] {
    let words = PodcastTeaching.shared.files.local.ads(partial: partial, limit: limit)
    return joined(id, words: words, sounds: soundLook(id, sha256: ads.sha256))
  }

  /// Joins the two lists and notes in the diary how many came from each (the numbers only).
  private func joined(_ id: String, words: [FoundAd], sounds: [FoundAd]) -> [FoundAd] {
    PodcastTimeline.mark(id, "local finders: \(words.count) ads from words, \(sounds.count) from sounds")
    return AdJoin.join(words + sounds)
  }

  /// Adds the local ads to the episode's partial ads file. They never claim to cover any of the
  /// transcript (`coveredUntil` is how far the model got). True when the file changed.
  @discardableResult
  func addLocalToPartial(_ local: [FoundAd], ads: AdsStore, duration: Double) -> Bool {
    LocalAdsFile.addToPartial(
      local, store: ads, detector: Self.detectorName,
      detectorVersion: detector?.version ?? LocalAdsFile.localVersion,
      osVersion: ProcessInfo.processInfo.operatingSystemVersionString, duration: duration,
      covered: 0)
  }

  /// The playing episode's player skips from the ads files at once.
  func refreshIfPlaying(_ id: String) {
    guard lock.withLock({ urgent == id }) else { return }
    Task { @MainActor in PodcastPlayer.shared.adSkipping.refresh() }
  }

  /// The model, or nil when it cannot be asked now (this system has none, or it is off,
  /// downloading or not eligible).
  func askableDetector() -> AdDetector? {
    guard AppleAds.unavailable() == nil else { return nil }
    return detector
  }

  // MARK: The sounds of a downloaded file

  /// The ads the taught sounds find in the episode's file, read once in this launch for each
  /// download (by its SHA-256). Reads the file, so never from the main thread.
  func soundLook(_ id: String, sha256: String) -> [FoundAd] {
    if let known = lock.withLock({ soundLooks[sha256] }) { return known }
    guard let file = PodcastDownloader.shared.localFile(for: id) else { return [] }
    let found = PodcastTeaching.shared.soundAds(inFile: file)
    lock.withLock { soundLooks[sha256] = found }
    return found
  }

  /// A download that has no transcript yet: its sounds are looked for in the background, once in
  /// this launch, and what they find goes into its partial ads file. Returns at once.
  func lookForSounds(_ id: String, ads: AdsStore) {
    let begin = lock.withLock { () -> Bool in
      guard soundLooks[ads.sha256] == nil else { return false }
      return soundLooking.insert(ads.sha256).inserted
    }
    guard begin else { return }
    Task.detached(priority: .utility) { [self] in
      let found = soundLook(id, sha256: ads.sha256)
      lock.withLock { _ = soundLooking.remove(ads.sha256) }
      guard !found.isEmpty else { return }
      PodcastTimeline.mark(id, "local finders: 0 ads from words, \(found.count) from sounds")
      guard addLocalToPartial(found, ads: ads, duration: 0) else { return }
      refreshIfPlaying(id)
      scan()
    }
  }
}
