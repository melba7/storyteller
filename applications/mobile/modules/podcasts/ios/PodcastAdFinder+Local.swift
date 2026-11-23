// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The ad finder's own layers, which need no Apple model: the word rules and the small model the
// Mac trained (`LocalAds`), and the sounds the Mac taught, looked for in the downloaded file.
// Their ads go into the episode's ads files first, whatever the model can do afterwards. All of
// it runs in the finder's own background task, never on the main thread.
import Foundation
import PodcastAds
import PodcastAdsOnDevice
import PodcastAudioMatch
import PodcastDownloads
import PodcastTranscripts

extension PodcastAdFinder {
  // MARK: The local ads of an episode

  /// The ads the phone finds by itself in a whole transcript: the words (rules and the small
  /// model) and the sounds of the downloaded file, joined. No sponsor names are passed: the
  /// finder has no cheap way to the episode's notes (the head scan has them from the player).
  /// The ads the memory knows (PodcastKnownAds) are joined with the words' ads, so they reach every
  /// file the local ads go into, as in the scorecard.
  func localAds(_ id: String, ads: AdsStore, transcript: Transcript) -> [FoundAd] {
    let words = PodcastTeaching.shared.files.local.ads(
      transcript: transcript, episodeDuration: transcript.duration)
    return joined(
      id, words: words + remembered(id, words: transcript.words),
      sounds: soundLook(id, sha256: ads.sha256))
  }

  /// The same for a transcript that is still being made, or its head (`limit` seconds).
  func localAds(
    _ id: String, ads: AdsStore, partial: PartialTranscript, limit: Double?
  ) -> [FoundAd] {
    let words = PodcastTeaching.shared.files.local.ads(partial: partial, limit: limit)
    let looked = limit.map { limit in partial.words.filter { $0.end <= limit } } ?? partial.words
    return joined(
      id, words: words + remembered(id, words: looked), sounds: soundLook(id, sha256: ads.sha256))
  }

  /// The ads the memory of ads finds whole in `words`, for the episode's show. None when the show
  /// is not known. An ad whose end is only a guess is left out.
  private func remembered(_ id: String, words: [TranscriptWord]) -> [FoundAd] {
    guard let show = EpisodeShows.shared.show(for: id) else { return [] }
    let use = KnownAdUse.from(PodcastKnownAds.shared.find(in: words, show: show), words: words)
    return use.ads.filter { !use.provisional.contains($0) }
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
  /// download (by its SHA-256). Reads the file, so never from the main thread. The same read
  /// also feeds the new sound finders when they may run (PodcastSoundPass), which keep what they
  /// found for the new finders' step (`addNewFinders`) and add nothing to this list.
  func soundLook(_ id: String, sha256: String) -> [FoundAd] {
    if let known = lock.withLock({ soundLooks[sha256] }) { return known }
    guard let file = PodcastDownloader.shared.localFile(for: id) else { return [] }
    let found = taughtSoundAds(id, sha256: sha256, file: file)
    lock.withLock { soundLooks[sha256] = found }
    return found
  }

  /// The taught sounds' ads: from the one pass when a new sound finder may run, else as before.
  private func taughtSoundAds(_ id: String, sha256: String, file: URL) -> [FoundAd] {
    guard let modes = newModes(id) else { return PodcastTeaching.shared.soundAds(inFile: file) }
    let pass = newSoundPass(id, modes: modes)
    guard !pass.consumers.subtracting([.mac]).isEmpty,
      let result = runSoundPass(id, sha256: sha256, file: file, pass: pass)
    else { return PodcastTeaching.shared.soundAds(inFile: file) }
    return NewAds.ads(ofSounds: result.mac)
  }

  /// What the sound pass is asked to do for this episode now.
  func newSoundPass(_ id: String, modes: NewModes) -> SoundPass {
    var pass = SoundPass()
    pass.mac = PodcastTeaching.shared.sounds
    pass.episode = id
    if modes.level(FinderNames.ownSound) != .off {
      pass.own = PodcastOwnSounds.shared.library(for: modes.show)
    }
    if modes.level(FinderNames.repeatSound) != .off {
      pass.older = PodcastRepeats.shared.olderPrints(show: modes.show, excluding: id)
      pass.wantsRepeats = true
      pass.printOf = (id, episodeDate(id))
    }
    pass.wantsJoints = modes.joints
    return pass
  }

  /// Reads the file once for every consumer in `pass`, with a guard mark on disk for each new
  /// finder that takes part and iOS holding time. The result is kept for this launch. Nil when
  /// the file cannot be read or no time was held.
  func runSoundPass(_ id: String, sha256: String, file: URL, pass: SoundPass) -> SoundPassResult? {
    var finders: [String] = []
    let wanted = pass.consumers
    if wanted.contains(.own) { finders.append(FinderNames.ownSound) }
    if wanted.contains(.repeats) || wanted.contains(.print) {
      finders.append(FinderNames.repeatSound)
    }
    if wanted.contains(.joints) { finders.append(FinderNames.joints) }
    let result = PodcastFinderGuard.shared.hold(finders, episode: id) { held -> SoundPassResult? in
      // A finder whose mark could not be written must not run.
      var allowed = pass
      if !held.finders.contains(FinderNames.ownSound) { allowed.own = AdSoundLibrary() }
      if !held.finders.contains(FinderNames.repeatSound) {
        allowed.older = []
        allowed.printOf = nil
      }
      if !held.finders.contains(FinderNames.joints) { allowed.wantsJoints = false }
      return allowed.run(file: file, stop: held.stop)
    }.flatMap { $0 }
    if let result {
      PodcastSoundPasses.shared.store(result, sha: sha256, stamp: soundStamp)
    }
    return result
  }

  /// What the new finders need of the file's one pass: the kept result, or a new pass when the
  /// first one did not run what is wanted now (the show was not known then).
  func soundResult(
    _ id: String, sha256: String, file: URL, modes: NewModes
  ) -> SoundPassResult? {
    let pass = newSoundPass(id, modes: modes)
    let needs = pass.consumers.subtracting([.mac])
    guard !needs.isEmpty else { return nil }
    if let known = PodcastSoundPasses.shared.result(sha: sha256, stamp: soundStamp, needs: needs) {
      return known
    }
    return runSoundPass(id, sha256: sha256, file: file, pass: pass)
  }

  var soundStamp: PodcastSoundPasses.Stamp {
    PodcastSoundPasses.Stamp(
      taught: PodcastTeaching.shared.soundsInstalls, own: PodcastOwnSounds.shared.revision)
  }

  /// When the episode was downloaded (what a print is dated by), else now.
  private func episodeDate(_ id: String) -> Double {
    if case .downloaded(_, _, _, let date)? = PodcastDownloader.shared.store?.entry(for: id)?.state
    {
      return date.timeIntervalSince1970
    }
    return Date().timeIntervalSince1970
  }

  /// A download that has no transcript yet: its sounds are looked for in the background, once in
  /// this launch, and what they find goes into its partial ads file. The files are read one after
  /// another, never several at once. Returns at once.
  func lookForSounds(_ id: String, ads: AdsStore) {
    let start = lock.withLock { () -> Bool in
      guard soundLooks[ads.sha256] == nil, soundLooking.insert(ads.sha256).inserted else {
        return false
      }
      soundQueue.append((id: id, ads: ads))
      guard !soundRunning else { return false }
      soundRunning = true
      return true
    }
    guard start else { return }
    Task.detached(priority: .utility) { [self] in
      while let next = nextSoundLook() { lookedForSounds(next.id, ads: next.ads) }
    }
  }

  /// The next file waiting to be read for sounds, or nil (and the reader stops) when none waits.
  private func nextSoundLook() -> (id: String, ads: AdsStore)? {
    lock.withLock {
      guard !soundQueue.isEmpty else {
        soundRunning = false
        return nil
      }
      return soundQueue.removeFirst()
    }
  }

  /// Reads one download's file for sounds and adds what they find to its partial ads file.
  private func lookedForSounds(_ id: String, ads: AdsStore) {
    let found = soundLook(id, sha256: ads.sha256)
    lock.withLock { _ = soundLooking.remove(ads.sha256) }
    guard !found.isEmpty else { return }
    PodcastTimeline.mark(id, "local finders: 0 ads from words, \(found.count) from sounds")
    guard addLocalToPartial(found, ads: ads, duration: 0) else { return }
    refreshIfPlaying(id)
    scan()
  }
}
