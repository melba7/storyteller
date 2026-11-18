// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The first minutes of a stream, checked for ads while the rest still downloads. As soon as
// about 30 seconds of audio are on disk the start of the file is copied to a small file, cut at
// a whole MP3 frame, and transcribed by an analyzer that was made ready ahead; the copy grows in
// 30 second steps to about 3 minutes. After each step the text rules (AdHeadRules) run at once,
// and after the 60 second step the on-device model is asked once, with a session that was asked
// to prewarm when play started. The ads found are saved as the episode's partial ads file, which
// the player already reads, and the player is told to read it again.
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
  static let targets: [Double] = [30, 60, 90, 120, 150, 180]
  /// The steps after which the model is asked.
  static let modelSteps: Set<Double> = [60, 180]

  let episodeId: String
  private let store: DownloadStore
  private let lock = NSLock()
  private var language: String?
  private var source: URL?
  private var key: String
  private var isFiled = false
  private var stopped = false
  private var started = false
  private var found: [FoundAd] = []
  private var covered = 0.0
  private var detectorVersion = "1"
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

  /// The staging file exists: the scan can begin.
  func begin(staged: URL) {
    let go = lock.withLock { () -> Bool in
      guard !started, !stopped else { return false }
      started = true
      source = staged
      return true
    }
    guard go else { return }
    task = Task.detached(priority: .userInitiated) { [self] in await run() }
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
    let detector = AppleAds.makeWarmDetector()
    detector?.prewarm()
    lock.withLock { detectorVersion = detector?.version ?? "1" }
    PodcastTimeline.mark(id, "model prewarm asked")
    do {
      try await speech.prepare()
      PodcastTimeline.mark(id, "speech analyzer ready")
      try await scan(speech, detector)
    } catch is CancellationError {
    } catch {
      PodcastTimeline.mark(id, "head scan ended: \(error)")
    }
    await speech.finish()
  }

  private func scan(_ speech: HeadTranscribing, _ warm: PrewarmableAdDetector?) async throws {
    var detector = warm
    var iterator = arrivals.makeAsyncIterator()
    var available: Int64 = 0
    var ended = false
    var fed = 0.0
    var rate = 16_000.0  // bytes of file per second of audio, learned from the first cut
    var tries = 0
    var tag = 0  // bytes of ID3 tag before the audio (cover art can make it large)
    var waitFor: Int64 = 0  // at least this many bytes are waited for
    var modelAds: [FoundAd] = []
    var first = true
    var index = 0
    while index < Self.targets.count {
      try Task.checkCancellation()
      let target = Self.targets[index]
      let need = max(Int64(target * rate) + 4096 + Int64(tag), waitFor)
      while available < need, !ended {
        if let next = await iterator.next() { available = next } else { ended = true }
      }
      if first, available > 0 { first = false; PodcastTimeline.mark(episodeId, "first bytes on disk") }
      let want = ended ? available : min(available, need + 65_536)
      guard want > 0, let data = await readPrefix(Int(want)) else {
        return PodcastTimeline.mark(episodeId, "head scan: the file cannot be read")
      }
      let cut: Mp3Prefix.Cut
      switch Mp3Prefix.look(data, complete: ended) {
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
      if cut.seconds < target - 3, !ended {
        // The file holds less audio than guessed: wait for more bytes.
        rate = Double(cut.bytes - cut.audioStart) / max(cut.seconds, 1) * 1.03
        tries += 1
        guard tries <= 4 else { return }
        continue
      }
      guard cut.seconds > fed + 1 else {
        if ended { return }
        index += 1
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

      let lines = LineRule.lines(from: words)
      let transcript = Self.transcript(words: words, lines: lines, duration: fed)
      let startedRules = Date()
      let ranges = AdHeadRules.find(lines: AdChunker.number(lines))
      let ruleAds = AdCleanup.run(ranges: ranges, transcript: transcript)
      PodcastTimeline.mark(
        episodeId,
        "rules: \(ruleAds.count) ads in \(Int(Date().timeIntervalSince(startedRules) * 1000)) ms")
      save(AdHeadRules.merge(ruleAds + modelAds), covered: fed)

      let warmOne: AdDetector? = detector
      if Self.modelSteps.contains(target), let model = warmOne ?? AppleAds.makeDetector() {
        detector = nil  // a warm session is used once
        let startedModel = Date()
        do {
          let piece = TranscriptPiece(lines: AdChunker.number(lines))
          let answer = try await model.findAds(in: piece)
          modelAds = AdCleanup.run(ranges: answer, transcript: transcript)
          PodcastTimeline.mark(
            episodeId,
            "model: \(modelAds.count) ads in \(Int(Date().timeIntervalSince(startedModel) * 1000)) ms")
          save(AdHeadRules.merge(ruleAds + modelAds), covered: fed)
        } catch {
          PodcastTimeline.mark(episodeId, "model: no answer (\(error))")
        }
      }
      index += 1
    }
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
      found = ads
      covered = max(covered, reached)
    }
    persist()
  }

  /// Writes the partial ads file, joined with what is already in it (once the download is
  /// filed, the ad finder may have saved its own), and tells the player when the ads changed.
  private func persist() {
    let changed = lock.withLock { () -> Bool in
      guard !stopped, let folder = try? store.folder(for: episodeId) else { return false }
      let ads = AdsStore(folder: folder, sha256: key)
      let name = PodcastAdFinder.detectorName
      let before = ads.loadPartial(detector: name)
      let merged = AdHeadRules.merge(found + (before?.ads ?? []))
      guard !merged.isEmpty || before != nil else { return false }
      var file = AdsFile(
        sha256: key, detector: name, detectorVersion: detectorVersion,
        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        duration: max(before?.duration ?? 0, covered), ads: merged,
        coveredUntil: max(before?.coveredUntil ?? 0, covered), refusedPieces: before?.refusedPieces)
      file.undone = before?.undone ?? []
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
