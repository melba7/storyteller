// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The first minutes of a stream, checked for ads while the rest still downloads. As soon as
// about 15 seconds of audio are on disk the start of the file is copied to a small file, cut at
// a whole MP3 frame, and transcribed by an analyzer that was made ready ahead; the copy grows in
// steps (15, 30, 60 seconds, then every 30) to about 3 minutes. After each step the text rules
// (AdHeadRules) run at once, and after the 30, 60, 120 and 180 second steps the on-device model
// is asked, with a session that was asked to prewarm when play started and, after each answer,
// another one for the next time. At the 30 second step only its sure answers count (an unsure
// one waits for the 60 second step). The ads found are saved as the episode's partial ads file,
// which the player already reads, and the player is told to read it again.
//
// The file is not whole, so there is no SHA-256 to name the ads by. Until the download is filed
// they are kept under a made-up name ("stream-<episode>"), which `adsStore` gives the player;
// when the file is filed they are saved again under its real hash (`filed`). Whatever goes wrong
// here (no speech model, a file that is not MP3, an error) only ends the scan: the normal path
// transcribes and checks the file once it is whole.
import Foundation
import PodcastAds
import PodcastAdsOnDevice
import PodcastDownloads
import PodcastSpeech
import PodcastTranscripts

final class PodcastStreamHead: @unchecked Sendable {
  /// Seconds of audio after which each step ends.
  static let targets = AdHeadRules.steps
  /// The steps after which the model is asked.
  static let modelSteps = AdHeadRules.modelSteps

  let episodeId: String
  private let store: DownloadStore
  private let lock = NSLock()
  private var language: String?
  private var sponsors: [SponsorName] = []
  private var source: URL?
  private var key: String
  private var isFiled = false
  private var stopped = false
  private var started = false
  private var scanDone = false
  /// The first look at the stream's start is done (the 15 second step's rules and the memory of
  /// ads have answered), whether or not it found an ad. A look that found none leaves no ads file.
  private var firstLookDone = false
  private var waiters: [() -> Void] = []
  private var found: [FoundAd] = []
  private var covered = 0.0
  /// What the listener undid and trimmed, kept here because filing the download wipes the
  /// stream's file.
  private var undone: [UndoneAd] = []
  private var trims: [AdTrim] = []
  private var detectorVersion = "1"
  /// The ads the phone remembers, found in the words so far (PodcastStreamHead+Memory.swift).
  let memory = HeadMemory()
  /// The words the show opens with, found in the words so far (PodcastStreamHead+Opening.swift).
  let opening = HeadOpening()
  private var task: Task<Void, Never>?
  private let feed: AsyncStream<Int64>.Continuation
  private let arrivals: AsyncStream<Int64>

  init(episodeId: String, store: DownloadStore) {
    self.episodeId = episodeId
    self.store = store
    key = "stream-" + episodeId
    var continuation: AsyncStream<Int64>.Continuation!
    arrivals = AsyncStream(Int64.self, bufferingPolicy: .bufferingNewest(1)) { continuation = $0 }
    feed = continuation
  }

  // MARK: What the download tells us

  func setLanguage(_ language: String?) { lock.withLock { self.language = language } }

  /// The advertisers the episode's notes name, which the quick rules also look for.
  func setSponsors(_ names: [SponsorName]) { lock.withLock { sponsors = names } }

  /// The staging file exists: the scan can begin.
  func begin(staged: URL) {
    let go = lock.withLock { () -> Bool in
      guard !started, !stopped else { return false }
      started = true
      source = staged
      return true
    }
    guard go else { return }
    discardEarlierStream()
    task = Task.detached(priority: .userInitiated) { [self] in
      await run()
      scanEnded()
    }
  }

  /// Runs `work` once the head scan is over (finished, stopped, failed, or never started), or
  /// after `timeout` seconds, whichever comes first. The transcriber of the filed episode waits
  /// for this, so two analyzers and two model sessions do not work on the same first minutes.
  func afterScan(timeout: Double, _ work: @escaping @Sendable () -> Void) {
    let once = RunOnce(work)
    let waiting = lock.withLock { () -> Bool in
      guard started, !scanDone else { return false }
      waiters.append { once.run() }
      return true
    }
    guard waiting else { return once.run() }
    Task.detached {
      try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
      once.run()
    }
  }

  /// Whether the scan has said what matters for the start: its first look is done (also when it
  /// found no ad, which saves no file), or it is over (finished, stopped or failed). Play does
  /// not wait for a stream like that again.
  var hasChecked: Bool { lock.withLock { firstLookDone || scanDone } }

  private func scanEnded() {
    let (ads, reached) = lock.withLock { (found, covered) }
    reportScanEnded(ads: ads, reached: reached)
    let release = lock.withLock { () -> [() -> Void] in
      scanDone = true
      defer { waiters = [] }
      return waiters
    }
    for wake in release { wake() }
  }

  /// A stream of this episode that failed part-way leaves its "stream-<episode>" file behind, with
  /// ads from a request that may have carried other inserted ads. This stream starts clean; only
  /// what the listener undid or trimmed is kept.
  private func discardEarlierStream() {
    lock.withLock {
      guard let folder = try? store.folder(for: episodeId) else { return }
      let ads = AdsStore(folder: folder, sha256: key)
      absorbMarks(ads.loadPartial(detector: PodcastAdFinder.detectorName))
      ads.discardPartial(detector: PodcastAdFinder.detectorName)
    }
  }

  /// Adds the undone ads and the trims of a file (the caller holds the lock). For one ad the
  /// earlier end of a trim stays.
  private func absorbMarks(_ file: AdsFile?) {
    for item in file?.undone ?? [] where !undone.contains(item) { undone.append(item) }
    for trim in file?.trims ?? [] { trims.add(trim) }
  }

  /// Reads the Undo list and the trims from the stream's file. The loader calls it just before the
  /// download is filed, which removes the folder with that file.
  func rememberUndone() {
    lock.withLock {
      guard let folder = try? store.folder(for: episodeId) else { return }
      absorbMarks(
        AdsStore(folder: folder, sha256: key).loadPartial(detector: PodcastAdFinder.detectorName))
    }
  }

  /// The listener found the skip of an ad too far. The trim goes into the head's own list, so
  /// every later write of the stream's ads keeps it, and it is written now under the lock the
  /// scan's own write (`persist`) holds from its read to the end of its write, so neither can
  /// overwrite the other. The store's call reaches a final ads file too, once there is one. False
  /// when nothing was written (the stream was stopped or its download is gone): the player then
  /// writes it into its own store, so a skip the listener marked after a stream failure is kept.
  func markTrimmed(_ trim: AdTrim) -> Bool {
    lock.withLock {
      trims.add(trim)
      return marksStore()?.markTrimmed(detector: PodcastAdFinder.detectorName, trim) ?? false
    }
  }

  /// The listener undid the skip of `ad`: kept and written as `markTrimmed` does it.
  func markUndone(_ ad: FoundAd) -> Bool {
    lock.withLock {
      let item = UndoneAd(start: ad.start, end: ad.end)
      if !undone.contains(item) { undone.append(item) }
      return marksStore()?.markUndone(detector: PodcastAdFinder.detectorName, adStart: ad.start)
        ?? false
    }
  }

  /// The store a mark is written to (the caller holds the lock). Nil once the stream was stopped
  /// or its download removed, so nothing makes the folder again.
  private func marksStore() -> AdsStore? {
    guard !stopped, store.entry(for: episodeId) != nil,
      let folder = try? store.folder(for: episodeId)
    else { return nil }
    return AdsStore(folder: folder, sha256: key)
  }

  /// The file on disk is now this long.
  func noteBytes(_ available: Int64) { feed.yield(available) }

  /// The download is over (whole or not): no more bytes come.
  func noMoreBytes() { feed.finish() }

  /// The listener moved on or removed the download.
  func stop() {
    let running = lock.withLock { () -> Task<Void, Never>? in
      stopped = true
      return task
    }
    running?.cancel()
    feed.finish()
  }

  /// The download was filed under `sha`. What was found is saved again under that name, and the
  /// scan reads the filed file from now on.
  func filed(sha: String, file: URL?) {
    lock.withLock {
      key = sha
      isFiled = true
      if let file { source = file }
    }
    persist()
  }

  /// The ads store the player should read for this stream: the filed hash once there is one,
  /// else the made-up name.
  var adsStore: AdsStore? {
    guard let folder = try? store.folder(for: episodeId) else { return nil }
    return AdsStore(folder: folder, sha256: lock.withLock { key })
  }

  // MARK: The scan

  private func run() async {
    let id = episodeId
    let locale = LocalePick.identifier(
      feedLanguage: lock.withLock { language }, phone: Locale.preferredLanguages.first ?? "en-US")
    guard let speech = AppleSpeech.makeHeadTranscriber(locale: locale) else {
      return PodcastTimeline.mark(id, "head scan: this phone has no speech recogniser")
    }
    // The model starts loading now, while the speech model does.
    let detector = Self.warmDetector()
    lock.withLock { detectorVersion = detector?.version ?? "1" }
    PodcastTimeline.mark(id, "model prewarm asked")
    do {
      try await speech.prepare()
      PodcastTimeline.mark(id, "speech analyzer ready")
      try await scan(speech, detector)
    } catch is CancellationError {
    } catch {
      // The error's type name and case name for the diary, not its words.
      PodcastTimeline.mark(id, "head scan ended: \(AdDiary.note(for: error))")
    }
    await speech.finish()
  }

  private func scan(_ speech: HeadTranscribing, _ warm: PrewarmableAdDetector?) async throws {
    var detector = warm
    var iterator = arrivals.makeAsyncIterator()
    var available: Int64 = 0
    var ended = false
    var fed = 0.0
    var rate = 16_000.0  // bytes of audio (the ID3 tag not counted) per second, learned from a cut
    var learned = false
    var tries = 0
    var tag = 0  // bytes of ID3 tag before the audio (cover art can make it large)
    var waitFor: Int64 = 0  // at least this many bytes are waited for
    var modelAds: [FoundAd] = []
    var first = true
    var told = false  // the player is told once, after the first step
    var steps = HeadSteps(steps: Self.targets)
    while let target = steps.target {
      try Task.checkCancellation()
      let need = max(Int64(tag) + Int64(target * rate) + 4096, waitFor)
      while available < need, !ended {
        if let next = await iterator.next() { available = next } else { ended = true }
      }
      if first, available > 0 { first = false; PodcastTimeline.mark(episodeId, "first bytes on disk") }
      let want = ended ? available : min(available, need + 65_536)
      guard want > 0, let data = await readPrefix(Int(want)) else {
        return PodcastTimeline.mark(episodeId, "head scan: the file cannot be read")
      }
      let cut: Mp3Prefix.Cut
      switch Mp3Prefix.look(data, complete: ended, maxSeconds: target) {
      case .cut(let found):
        cut = found
      case .needMore(let start):
        // A tag that is not whole yet, or no frame yet: wait for more bytes, up to 2 MB of audio.
        tag = max(tag, start ?? 0)
        guard !ended, tag < 20 << 20, available - Int64(tag) < 2 << 20 else {
          return PodcastTimeline.mark(episodeId, "head scan: no MP3 audio found")
        }
        waitFor = available + 32_768
        continue
      case .notMp3:
        return PodcastTimeline.mark(episodeId, "head scan: the file is not an MP3")
      }
      tag = cut.audioStart
      // The byte rate of the audio is learned from the first cut, whichever way the guess was
      // wrong, and again whenever a cut falls short. The cut is held to the step's target, so a
      // lean file (32 kbit/s) never feeds the model far more than a step.
      let short = cut.seconds < target - 3 && !ended
      if short || (!learned && cut.seconds >= 5) {
        rate = Double(cut.bytes - cut.audioStart) / max(cut.seconds, 1) * 1.03
        learned = true
      }
      if short {
        // The file holds less audio than guessed: wait for more bytes.
        tries += 1
        guard tries <= 4 else {
          return PodcastTimeline.mark(episodeId, "head scan: the audio does not come at a steady rate")
        }
        continue
      }
      guard cut.seconds > fed + 1 else {
        if ended { return }
        steps.advance()
        continue
      }
      tries = 0
      PodcastTimeline.mark(episodeId, "head audio on disk: \(Int(cut.seconds)) s, \(cut.bytes) bytes")
      let temp = FileManager.default.temporaryDirectory.appendingPathComponent(
        "head-\(episodeId)-\(UUID().uuidString).mp3")
      try data.prefix(cut.bytes).write(to: temp)
      defer { try? FileManager.default.removeItem(at: temp) }
      let words = try await speech.extend(file: temp, from: fed, to: cut.seconds)
      fed = cut.seconds
      PodcastTimeline.mark(episodeId, "head transcript: \(words.count) words to \(Int(fed)) s")
      SkipLogWords.note(words, for: episodeId)

      let lines = LineRule.lines(from: words)
      let transcript = Self.transcript(words: words, lines: lines, duration: fed)
      // The ads the phone remembers come first; an ad that opens at the end of the words moves
      // the next step to where it should end.
      let remembered = memory.look(in: words, episodeId: episodeId)
      if let jump = remembered.jumpTo { steps.jump(to: jump, reached: fed) }
      // The show's own opening words, when this show has some: where they start, the show begins.
      let begun = opening.look(in: words, episodeId: episodeId)
      let startedRules = Date()
      let sponsors = lock.withLock { self.sponsors }
      let ranges = AdHeadRules.find(lines: AdChunker.number(lines), sponsors: sponsors)
      let ruleAds = AdCleanup.run(ranges: ranges, transcript: transcript)
      PodcastTimeline.mark(
        episodeId,
        "rules: \(ruleAds.count) ads in \(Int(Date().timeIntervalSince(startedRules) * 1000)) ms")
      save(AdHeadRules.merge(remembered.ads + ruleAds + modelAds), covered: fed)
      // The first look is done: the player may start (it waits for this, PodcastPlayer+StartHold).
      if !told {
        told = true
        lock.withLock { firstLookDone = true }
        if begun { reportShowBegan() } else { reportVerdict() }
      }

      let warmOne: AdDetector? = detector
      if Self.modelSteps.contains(target), let model = warmOne ?? AppleAds.makeDetector() {
        detector = nil  // a warm session is used once
        let startedModel = Date()
        do {
          let piece = TranscriptPiece(lines: AdChunker.number(lines))
          let answer = try await model.findAds(in: piece)
          // At the first model step only the sure answers count; the next step hears more.
          modelAds = AdCleanup.run(
            ranges: AdHeadRules.counted(answer, atStep: target), transcript: transcript)
          PodcastTimeline.mark(
            episodeId,
            "model: \(modelAds.count) ads in \(Int(Date().timeIntervalSince(startedModel) * 1000)) ms")
          save(AdHeadRules.merge(remembered.ads + ruleAds + modelAds), covered: fed)
        } catch {
          // The error's type name and case name for the diary, not its words.
          PodcastTimeline.mark(episodeId, "model: no answer (\(AdDiary.note(for: error)))")
        }
        // The next model step gets a session that is made and asked to prewarm now.
        if Self.modelSteps.contains(where: { $0 > target }) { detector = Self.warmDetector() }
      }
      steps.advance()
    }
  }

  /// A model session for one request, made now and asked to prewarm. Nil when there is no model.
  private static func warmDetector() -> PrewarmableAdDetector? {
    let detector = AppleAds.makeWarmDetector()
    detector?.prewarm()
    return detector
  }

  private static func transcript(
    words: [TranscriptWord], lines: [TranscriptLine], duration: Double
  ) -> Transcript {
    Transcript(
      identity: TranscriptIdentity(
        locale: "", recogniser: "SpeechTranscriber", recogniserVersion: "1",
        osVersion: ProcessInfo.processInfo.operatingSystemVersionString, sha256: ""),
      duration: duration, lines: lines, words: words)
  }

  /// The first `count` bytes of the file, or nil. The staging file is moved when the download
  /// is filed, so a read that misses is tried once more at the new place.
  private func readPrefix(_ count: Int) async -> Data? {
    for attempt in 0..<2 {
      if attempt > 0 { try? await Task.sleep(nanoseconds: 150_000_000) }
      guard let url = lock.withLock({ source }), let handle = try? FileHandle(forReadingFrom: url)
      else { continue }
      defer { try? handle.close() }
      if let data = try? handle.read(upToCount: count) { return data }
    }
    return nil
  }

  // MARK: Saving

  private func save(_ ads: [FoundAd], covered reached: Double) {
    lock.withLock {
      found = opening.shorten(ads)
      covered = max(covered, reached)
    }
    persist()
  }

  /// Writes the partial ads file, joined with what is already in it (once the download is
  /// filed, the ad finder may have saved its own), and tells the player when the ads changed.
  private func persist() {
    let changed = lock.withLock { () -> Bool in
      // The lock is held to the end of the write, so a stop (which deletes the folder after it)
      // never meets a write; a download that was removed meanwhile has no entry, and nothing
      // makes its folder again.
      guard !stopped, store.entry(for: episodeId) != nil, let folder = try? store.folder(for: episodeId)
      else { return false }
      let ads = AdsStore(folder: folder, sha256: key)
      let name = PodcastAdFinder.detectorName
      let before = ads.loadPartial(detector: name)
      absorbMarks(before)
      // The opening is applied last: an earlier step's longer pre-roll is on disk too.
      let merged = opening.shorten(
        AdHeadRules.merge(found + memory.withoutOutdated(before?.ads ?? [])))
      guard !merged.isEmpty || before != nil else { return false }
      var file = AdsFile(
        sha256: key, detector: name, detectorVersion: detectorVersion,
        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        duration: max(before?.duration ?? 0, covered), ads: merged,
        coveredUntil: max(before?.coveredUntil ?? 0, covered), refusedPieces: before?.refusedPieces)
      file.undone = undone
      file.trims = trims.isEmpty ? nil : trims
      guard before?.ads != merged else { return false }
      do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try ads.savePartial(file)
        return true
      } catch {
        return false
      }
    }
    guard changed else { return }
    PodcastTimeline.mark(episodeId, "player told to read the ads")
    Task { @MainActor in PodcastPlayer.shared.adSkipping.refresh() }
  }
}

/// Runs a closure at most once, from whichever caller comes first.
private final class RunOnce: @unchecked Sendable {
  private let lock = NSLock()
  private var work: (@Sendable () -> Void)?
  init(_ work: @escaping @Sendable () -> Void) { self.work = work }
  func run() {
    let go = lock.withLock { () -> (@Sendable () -> Void)? in
      defer { work = nil }
      return work
    }
    go?()
  }
}
