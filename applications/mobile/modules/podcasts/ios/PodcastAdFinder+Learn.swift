// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// What the phone learns once an episode's final ads are on disk, and what it learns from the
// listener's answers: the memory of ads by words, the show's opening words, the phone's own sound
// prints, what the show's last episodes said and sounded like (to find what repeats), and the
// show's habits; and the guard's record of which finder was right. It all runs in the finder's own
// background task or on its own serial queue, never on the main thread. The two functions the
// player's question and Undo call (`learnAnswered`, `forgetUndone`) return at once.
import Foundation
import PodcastAds
import PodcastAudioMatch
import PodcastDownloads
import PodcastTranscripts

extension PodcastAdFinder {
  /// Serial, so two answers never learn at the same time.
  private static let answerQueue = DispatchQueue(label: "PodcastAdFinder.answers", qos: .utility)
  /// A transcript file larger than this is not read into memory for an answer.
  private static let mostTranscriptBytes = 64 << 20

  // MARK: After a final pass

  /// A final ads file was saved (with the new finders' ads in it). `trusted` is true for the
  /// model's own pass: only that one is learned into the memory of ads, the show's opening, the
  /// phone's sound prints and the show's habits, as before; what the show said and sounded like
  /// is remembered after any final pass, so the next episode can be compared with it.
  func learnAfterFind(
    _ id: String, ads store: AdsStore, transcript: Transcript, made: NewResult, trusted: Bool
  ) {
    if trusted {
      learnKnown(id, ads: store, finished: made.file, transcript: transcript, moved: made.moved)
      learnOpening(id, ads: store, finished: made.file, transcript: transcript)
    }
    guard let modes = made.modes else { return }
    rememberRepeats(id, ads: store, transcript: transcript, modes: modes)
    guard trusted else { return }
    let saved = store.load(detector: Self.detectorName) ?? made.file
    learnOwnSounds(id, saved, modes: modes, moved: made.moved, words: made.words)
    learnHabits(id, saved, transcript: transcript, modes: modes)
  }

  /// The sure ads of the saved file are remembered by their words, for the show, as before the
  /// new finders, with two changes. An ad whose borders a joint moved is learned as it was found,
  /// because the words between the joint and the found border are the show's. An ad over a
  /// stretch the listener said yes to is left out: `learnTapped` counted that stretch once
  /// already.
  func learnKnown(
    _ id: String, ads store: AdsStore, finished file: AdsFile, transcript: Transcript,
    moved: [NewAds.Moved]
  ) {
    guard let show = EpisodeShows.shared.show(for: id) else { return }
    var saved = store.load(detector: Self.detectorName) ?? file
    saved.ads = saved.ads.map { NewAds.restored($0, from: moved) }
    let counted =
      saved.ads.filter { $0.source == AdAsking.source }
      + (saved.asks ?? []).filter { $0.confidence != .guess }
    saved.ads.removeAll { ad in counted.contains { NewAds.overlap($0, ad) } }
    PodcastKnownAds.shared.learn(file: saved, transcript: transcript, show: show)
  }

  /// Remembers what the episode said (hashes of five-word runs) and what it sounded like (its
  /// print), so the show's next episode is compared with it. After the finders ran. The words are
  /// remembered on every pass; the print once for each episode, because a second one would replace
  /// the print that a "no" to a repeat had scrambled.
  private func rememberRepeats(
    _ id: String, ads store: AdsStore, transcript: Transcript, modes: NewModes
  ) {
    let words = modes.level(FinderNames.repeatWords) != .off
    let sound = modes.level(FinderNames.repeatSound) != .off
    let made =
      sound
      ? PodcastSoundPasses.shared.result(sha: store.sha256, stamp: soundStamp, needs: [.print])?
        .print : nil
    let print = PodcastLearned.shared.seen(.print, episode: id) ? nil : made
    guard words || print != nil else { return }
    let finders =
      (words ? [FinderNames.repeatWords] : []) + (print != nil ? [FinderNames.repeatSound] : [])
    let stored = PodcastFinderGuard.shared.hold(finders, episode: id) { held -> Bool in
      if words, held.finders.contains(FinderNames.repeatWords) {
        PodcastRepeats.shared.rememberWords(show: modes.show, episode: id, lines: transcript.lines)
      }
      guard let print, held.finders.contains(FinderNames.repeatSound) else { return false }
      PodcastRepeats.shared.storePrint(print, show: modes.show)
      return true
    }
    if stored == true { PodcastLearned.shared.note(.print, episode: id) }
  }

  /// The prints of the sure ads of the saved file (with the borders they were found with, not the
  /// ones the joint snap moved them to), once for each episode. Not the ads of the new finders
  /// (they are unsure), not an ad the listener undid or trimmed, not one the listener confirmed (it
  /// was learned with the answer). The found borders are used because a pull can add up to a
  /// minute of what came before the ad, as `learnKnown` does too. The episode is noted as learned
  /// from only when the learning ran: with no time held from iOS the next pass tries again.
  private func learnOwnSounds(
    _ id: String, _ saved: AdsFile, modes: NewModes, moved: [NewAds.Moved], words: [FoundAd]
  ) {
    guard modes.level(FinderNames.ownSound) != .off,
      let file = PodcastDownloader.shared.localFile(for: id),
      !PodcastLearned.shared.seen(.own, episode: id)
    else { return }
    let stretches = saved.ads.filter { ad in
      ad.confidence == .sure && ad.source != AdAsking.source && !saved.isUndone(ad)
        && !(saved.trims ?? []).contains {
          // The snap moved the saved ad's start; the pull is judged on the start it was found with.
          $0.adStart >= ad.start
            - NewAds.trimReach(for: NewAds.restored(ad, from: moved), words: words)
            && $0.adStart < ad.end
        }
        && !(saved.asks ?? []).contains { $0.confidence != .guess && NewAds.overlap($0, ad) }
    }.map { ad -> MarkedStretch in
      let found = NewAds.restored(ad, from: moved)
      return MarkedStretch(
        start: found.start, end: found.end, sort: Self.sort(of: ad.kind), who: ad.advertiser)
    }
    guard !stretches.isEmpty else { return }
    let added = PodcastFinderGuard.shared.hold([FinderNames.ownSound], episode: id) { _ -> Int in
      let frames = OwnAdSoundsFile.frames(in: file, stretches: stretches.map { ($0.start, $0.end) })
      return PodcastOwnSounds.shared.learn(
        show: modes.show, frames: frames, stretches: stretches, mac: PodcastTeaching.shared.sounds)
    }
    if added != nil { PodcastLearned.shared.note(.own, episode: id) }
    PodcastTimeline.mark(id, "own sounds: \(added ?? 0) learned from \(stretches.count) ads")
  }

  /// Notes whether the episode opened with an ad and where that ended, for the show's habits
  /// (`ShowStarts`), once for each episode. Not for an episode that was played through while it
  /// downloaded: its head scan noted the start already.
  private func learnHabits(_ id: String, _ saved: AdsFile, transcript: Transcript, modes: NewModes)
  {
    if PodcastDownloader.shared.store?.entry(for: id)?.playThrough == true { return }
    guard PodcastLearned.shared.firstTime(.habits, episode: id) else { return }
    PodcastShowStarts.shared.record(
      show: modes.show, ads: saved.ads.filter { !saved.isUndone($0) }, reached: transcript.duration)
  }

  // MARK: The listener's answers

  /// The listener answered a question (`source` is the finder that asked, nil when it had none).
  /// A yes: the stretch is remembered by its words, its sound is learned and the guard hears it
  /// was right. A no: the guard hears it was wrong, and a repeat of words or sound is forgotten.
  /// Returns at once.
  func learnAnswered(_ id: String, source: String?, start: Double, end: Double, isAd: Bool) {
    guard start.isFinite, end.isFinite, end > start else { return }
    Self.answerQueue.async { [self] in
      guard let show = EpisodeShows.shared.show(for: id), !show.isEmpty else {
        return PodcastTimeline.mark(id, "answer: the show is not known, nothing learned")
      }
      let finder = source.flatMap { FinderNames.answerable.contains($0) ? $0 : nil }
      let (store, transcripts) = answerStores(id)
      let transcript = transcripts.flatMap(loadTranscript)
      if isAd {
        if let finder { PodcastFinderGuard.shared.confirmed(finder: finder, show: show) }
        let ask = store?.asked(start: start, end: end, detector: Self.detectorName)
        let ad = FoundAd(
          start: start, end: end, kind: ask?.kind ?? .ad, advertiser: ask?.advertiser ?? "",
          confidence: .sure, firstWords: ask?.firstWords ?? "", source: AdAsking.source)
        // What `KnownAds.learnTapped` does: one ad counted, not the file's others.
        if let transcript {
          let one = AdsFile(
            sha256: transcript.identity.sha256, detector: AdAsking.source, detectorVersion: "",
            osVersion: "", duration: transcript.duration, ads: [ad])
          PodcastKnownAds.shared.learn(file: one, transcript: transcript, show: show)
        }
        learnSound(id, show: show, ad: ad)
        PodcastTimeline.mark(id, "answer: yes, learned (\(finder ?? "no finder"))")
      } else {
        if let finder { PodcastFinderGuard.shared.denied(finder: finder, show: show) }
        forget(
          id, show: show, start: start, end: end, transcript: transcript,
          words: finder == FinderNames.repeatWords, sound: finder == FinderNames.repeatSound)
        PodcastTimeline.mark(id, "answer: no, learned (\(finder ?? "no finder"))")
      }
    }
  }

  /// The listener undid the skip of the stretch from `start` to `end`: the phone forgets what it
  /// learned for it (the remembered ad by its words, its own sound prints, what a repeat of words
  /// or sound remembered), and the guard hears which finder's skip it was. `heard` are the words
  /// of a stream's head scan, `source` is the finder that made the ad as the player knows it: an
  /// episode that is still streamed has no ads file or audio file yet, so the guard is told by
  /// it, and what the phone's own sounds learned of the stretch is not forgotten then (that could
  /// be done once the download is filed). It waits in the queue behind a yes that is still being
  /// learned, so that the Undo comes after it. Returns at once.
  func forgetUndone(
    _ id: String, start: Double, end: Double, heard: [TranscriptWord], source: String?
  ) {
    guard start.isFinite, end.isFinite, end > start else { return }
    Self.answerQueue.async { [self] in
      guard let show = EpisodeShows.shared.show(for: id), !show.isEmpty else { return }
      PodcastKnownAds.shared.forget(episodeId: id, ads: [(start, end)], heard: heard)
      let (store, transcripts) = answerStores(id)
      let ad = store?.adOver(start: start, end: end, detector: Self.detectorName)
      let by = ad?.source ?? source
      if let by, FinderNames.answerable.contains(by) {
        PodcastFinderGuard.shared.undone(finder: by, show: show)
      }
      forget(
        id, show: show, start: start, end: end, transcript: transcripts.flatMap(loadTranscript),
        words: true, sound: true)
      PodcastTimeline.mark(id, "undo: forgot what was learned (\(by ?? "no finder"))")
    }
  }

  /// Whether a finder may work on this episode: neither the guard nor the Mac's settings switch
  /// it off.
  private func works(_ finder: String, show: String, episode: String) -> Bool {
    let guarded = PodcastFinderGuard.shared.mode(finder: finder, show: show, episode: episode)
    let settings = PodcastTeaching.shared.files.tuning.level(forFinder: finder, show: show)
    return ShowTuning.stricter(guarded, settings) != .off
  }

  /// Drops what was learned for a stretch: the prints of the phone's own sounds found in it, what
  /// the repeats of words and of sound remember of it. The file is read only when a finder that
  /// keeps something of sound works (it may be off by the Mac's settings or by the guard), and
  /// only the finders that are used are held.
  private func forget(
    _ id: String, show: String, start: Double, end: Double, transcript: Transcript?, words: Bool,
    sound: Bool
  ) {
    if words, let transcript {
      PodcastRepeats.shared.denyWords(show: show, lines: transcript.lines, start: start, end: end)
    }
    let own = works(FinderNames.ownSound, show: show, episode: id)
    let repeats = sound && works(FinderNames.repeatSound, show: show, episode: id)
    guard own || repeats, let file = PodcastDownloader.shared.localFile(for: id) else { return }
    let used = (own ? [FinderNames.ownSound] : []) + (repeats ? [FinderNames.repeatSound] : [])
    _ = PodcastFinderGuard.shared.hold(used, episode: id) { held in
      let frames = OwnAdSoundsFile.frames(in: file, stretches: [(start, end)])
      if held.finders.contains(FinderNames.ownSound) {
        PodcastOwnSounds.shared.forget(frames: frames, start: start, end: end)
      }
      if held.finders.contains(FinderNames.repeatSound) {
        PodcastRepeats.shared.forgetSound(show: show, frames: frames)
      }
    }
  }

  /// The sound of a stretch the listener confirmed is learned as a sure ad's is.
  private func learnSound(_ id: String, show: String, ad: FoundAd) {
    guard works(FinderNames.ownSound, show: show, episode: id),
      let file = PodcastDownloader.shared.localFile(for: id)
    else { return }
    let stretch = MarkedStretch(
      start: ad.start, end: ad.end, sort: Self.sort(of: ad.kind), who: ad.advertiser)
    _ = PodcastFinderGuard.shared.hold([FinderNames.ownSound], episode: id) { _ in
      let frames = OwnAdSoundsFile.frames(in: file, stretches: [(ad.start, ad.end)])
      PodcastOwnSounds.shared.learn(
        show: show, frames: frames, stretches: [stretch], mac: PodcastTeaching.shared.sounds)
    }
  }

  // MARK: Details

  /// The episode's ads store and transcript store, or nil when its download is gone.
  private func answerStores(_ id: String) -> (AdsStore?, TranscriptStore?) {
    guard let downloads = PodcastDownloader.shared.store,
      let (ads, transcripts) = stores(for: id, in: downloads)
    else { return (nil, nil) }
    return (ads, transcripts)
  }

  /// The transcript, unless its file is too large to hold in memory.
  private func loadTranscript(_ transcripts: TranscriptStore) -> Transcript? {
    let size = (try? FileManager.default.attributesOfItem(atPath: transcripts.transcriptURL.path))?[
      .size]
    guard let bytes = size as? Int, bytes <= Self.mostTranscriptBytes else { return nil }
    return transcripts.loadTranscript()
  }

  /// The word model's class of a kind of ad, which is how a sound is sorted.
  static func sort(of kind: AdKind) -> String {
    switch kind {
    case .ad: return "sponsor"
    case .promo: return "network_promo"
    case .ownPlug: return "host_ask"
    case .credits: return "intro_credits"
    }
  }
}

extension AdsStore {
  /// The saved file of the detector: the final one, else the partial one.
  fileprivate func saved(detector: String) -> AdsFile? {
    load(detector: detector) ?? loadPartial(detector: detector)
  }

  /// The question that was answered over this stretch (a yes keeps it in the file's questions),
  /// else the maybe (a confirmed one stays in the file's maybes).
  fileprivate func asked(start: Double, end: Double, detector: String) -> FoundAd? {
    let file = saved(detector: detector)
    return file?.asks?.first { $0.start < end && start < $0.end }
      ?? file?.maybes?.first { $0.start < end && start < $0.end }
  }

  /// The ad that the stretch lies over, whatever its confidence.
  fileprivate func adOver(start: Double, end: Double, detector: String) -> FoundAd? {
    saved(detector: detector)?.ads.first { $0.start < end && start < $0.end }
  }
}
