// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The ads that are remembered by their words (PodcastAds' KnownAds), kept in
// `Podcasts/known-ads.json`. The file is read the first time something needs it, and only from a
// background task: the head scan, the ad finder and the queue below. A missing or broken file
// starts an empty memory. Undo comes from the main actor, so forgetting only queues its work.
// Finding also looks at the ads the Mac taught (PodcastTeaching's seeds), which are never kept in
// this file.
import Foundation
import PodcastAds
import PodcastDownloads
import PodcastTranscripts

final class PodcastKnownAds: @unchecked Sendable {
  static let shared = PodcastKnownAds()

  static var url: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Podcasts", isDirectory: true)
      .appendingPathComponent(KnownAds.fileName)
  }

  private let lock = NSLock()
  private var memory: KnownAds?
  private let queue = DispatchQueue(label: "PodcastKnownAds", qos: .utility)

  private init() {}

  /// Runs `work` on the memory, reading the file first when it has not been read. Never call it
  /// from the main thread.
  private func access<T>(_ work: (inout KnownAds) -> T) -> T {
    lock.withLock {
      var known = memory ?? KnownAds.load(from: Self.url)
      memory = nil  // so the change below does not copy the whole memory
      defer { memory = known }
      return work(&known)
    }
  }

  private static func save(_ known: KnownAds) {
    do {
      try known.save(to: url)
    } catch {
      NSLog("Podcasts: the remembered ads could not be saved: \(error)")
    }
  }

  /// The remembered ads of `show` that these words contain, and the ads the Mac taught (the seeds
  /// of PodcastTeaching). Where one of each is the same stretch, the one seen more often wins.
  func find(in words: [TranscriptWord], show: String) -> [KnownAdHit] {
    let seeds = PodcastTeaching.shared.files.seeds
    return access { $0.find(in: words, show: show, seeds: seeds) }
  }

  /// Remembers the sure ads of a final ads file (the one on disk, which holds what the listener
  /// undid and trimmed meanwhile).
  func learn(file: AdsFile, transcript: Transcript, show: String) {
    let trimmed = (file.trims ?? []).map(\.adStart)
    access { known in
      known.learn(from: file, transcript: transcript, show: show, trimmed: trimmed, now: Date())
      Self.save(known)
    }
  }

  /// The listener undid these ads of an episode: the remembered ads that are the same words are
  /// forgotten. `heard` are the words of a stream's head scan, used for the ads they reach; the
  /// others are looked up in the episode's transcript. It returns at once. Only the phone's own
  /// memory forgets: an ad the Mac taught is in the Mac's file (the seeds), which the phone does
  /// not change, so it is found again until the Mac stops teaching it.
  func forget(episodeId: String, ads: [(start: Double, end: Double)], heard: [TranscriptWord]) {
    queue.async { [self] in
      guard let show = EpisodeShows.shared.show(for: episodeId) else { return }
      // The words of each ad, read before the memory is locked: a transcript file can be large.
      var fromFile: [TranscriptWord]?
      let lists = ads.map { ad -> [TranscriptWord] in
        if (heard.last?.end ?? 0) >= ad.end { return heard }
        if fromFile == nil { fromFile = Self.transcriptWords(episodeId) }
        return fromFile ?? []
      }
      let forgotten = access { known -> Int in
        var count = 0
        for (ad, words) in zip(ads, lists) {
          count += known.forget(start: ad.start, end: ad.end, in: words, show: show)
        }
        if count > 0 { Self.save(known) }
        return count
      }
      if forgotten > 0 { PodcastTimeline.mark(episodeId, "memory: forgot \(forgotten)") }
    }
  }

  /// The words of the episode's transcript (whole, or as far as it is), or none.
  private static func transcriptWords(_ episodeId: String) -> [TranscriptWord] {
    guard let downloads = PodcastDownloader.shared.store,
      let (_, transcripts) = PodcastAdFinder.shared.stores(for: episodeId, in: downloads)
    else { return [] }
    return transcripts.loadTranscript()?.words ?? transcripts.loadPartial()?.words ?? []
  }
}

extension EpisodeShows {
  /// Which show each episode is of, noted when the player loads one or an episode joins Up Next.
  static let shared = EpisodeShows(
    url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Podcasts", isDirectory: true)
      .appendingPathComponent(EpisodeShows.fileName))
}
