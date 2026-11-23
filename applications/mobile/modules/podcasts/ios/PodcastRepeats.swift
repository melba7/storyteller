// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// What the phone remembers of a show's last episodes, so what comes back in the next one can be
// found. By words: `Podcasts/repeat-words.json` (PodcastAds' RepeatedWords, the hashes of every
// run of five words, never the words; up to about 7 MB). By sound: one file for each show under
// `Library/Caches/Podcasts/prints/` (PodcastAudioMatch's ShowPrints, about 69 KB an hour for each
// of three episodes), a cache that iOS may clear and that is made again from the next episode.
// A missing, damaged or too big file reads as empty. Everything is read and written only from a
// background task, never on the main actor. The types are pure; this class adds the locks and the
// files. `PodcastLearned` keeps which episodes were learned from already.
import Foundation
import PodcastAds
import PodcastAudioMatch
import PodcastDownloads
import PodcastTranscripts

final class PodcastRepeats: @unchecked Sendable {
  static let shared = PodcastRepeats(wordsURL: defaultWords, printsFolder: defaultPrints)

  static var defaultWords: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Podcasts", isDirectory: true)
      .appendingPathComponent(RepeatedWords.fileName)
  }

  static var defaultPrints: URL {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Podcasts", isDirectory: true)
      .appendingPathComponent("prints", isDirectory: true)
  }

  /// The mark that scrambles an anchor so it matches nothing (a print is a cache of hashes).
  private static let scramble: UInt32 = 0xA5A5_A5A5

  private let wordsURL: URL
  private let printsFolder: URL
  private let lock = NSLock()
  private var words: RepeatedWords?

  init(wordsURL: URL, printsFolder: URL) {
    self.wordsURL = wordsURL
    self.printsFolder = printsFolder
  }

  // MARK: By words

  /// The stretches of the episode that an older episode of the show said too, as unsure ads.
  func findWords(
    show: String, episode: String, lines: [TranscriptLine], duration: Double, already: [FoundAd],
    now: Date = Date()
  ) -> [FoundAd] {
    lock.withLock {
      currentWords().find(
        show: show, episode: episode, lines: lines, duration: duration, now: now, already: already)
    }
  }

  /// Remembers what the episode said, once it was looked at. Written before the lock is let go.
  func rememberWords(
    show: String, episode: String, lines: [TranscriptLine], now: Date = Date()
  ) {
    changeWords { $0.remember(show: show, episode: episode, lines: lines, now: now) }
  }

  /// The listener said the stretch is not an ad, or undid a skip made from it.
  func denyWords(
    show: String, lines: [TranscriptLine], start: Double, end: Double, now: Date = Date()
  ) {
    changeWords { $0.deny(show: show, lines: lines, start: start, end: end, now: now) }
  }

  private func changeWords(_ change: (inout RepeatedWords) -> Void) {
    lock.withLock {
      let before = currentWords()
      var next = before
      words = nil  // so the change does not copy the whole memory twice
      change(&next)
      words = next
      guard next != before else { return }
      do {
        try FileManager.default.createDirectory(
          at: wordsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try next.data.write(to: wordsURL, options: .atomic)
      } catch {
        NSLog("Podcasts: the repeated words could not be saved: \(error)")
      }
    }
  }

  /// The caller holds the lock. The file is read up to its limit plus one byte.
  private func currentWords() -> RepeatedWords {
    if let words { return words }
    let loaded = Self.read(wordsURL, limit: RepeatedWords.maxFileBytes).map {
      RepeatedWords.read($0)
    }
    words = loaded ?? RepeatedWords()
    return words ?? RepeatedWords()
  }

  // MARK: By sound

  /// The prints of the show's other episodes, to scan `episode` against. Nothing when the show
  /// has none. Using them counts as touching the show's file, so it is the last to be dropped.
  func olderPrints(show: String, excluding episode: String) -> [EpisodePrint] {
    lock.withLock {
      guard let shelf = readShow(show) else { return [] }
      touch(file(for: show))
      return shelf.prints(excluding: episode)
    }
  }

  /// Keeps this episode's print among the show's newest three, then drops the shows that no
  /// longer fit the shelf's limits (60 shows, about 12 MB).
  func storePrint(_ print: EpisodePrint, show: String) {
    lock.withLock {
      let shelf = (readShow(show) ?? ShowPrints()).adding(print)
      write(shelf, show: show)
      evict()
    }
  }

  /// The listener said a repeated stretch is not an ad: the anchors of the show's prints that
  /// are the hashes of `frames` are scrambled, so those bytes repeat nothing from now on.
  func forgetSound(show: String, frames: [MP3Frame]) {
    let hashes = Set(frames.map { UInt32(truncatingIfNeeded: $0.hash) })
    guard !hashes.isEmpty else { return }
    lock.withLock {
      guard let shelf = readShow(show) else { return }
      var changed = false
      let prints = shelf.prints.map { print -> EpisodePrint in
        var made = print
        made.anchors = print.anchors.map { hashes.contains($0) ? $0 ^ Self.scramble : $0 }
        changed = changed || made.anchors != print.anchors
        return made
      }
      guard changed else { return }
      write(ShowPrints(prints: prints.reversed()), show: show)
    }
  }

  // MARK: The print files

  /// A show's file: its name is the show's SHA-256, so the id can hold anything.
  private func file(for show: String) -> URL {
    printsFolder.appendingPathComponent(Sha256Stream.hash(of: Data(show.utf8)) + ".bin")
  }

  private func readShow(_ show: String) -> ShowPrints? {
    Self.read(file(for: show), limit: ShowPrints.maxBytes).map { ShowPrints(data: $0) }
  }

  private func write(_ shelf: ShowPrints, show: String) {
    do {
      try FileManager.default.createDirectory(at: printsFolder, withIntermediateDirectories: true)
      try shelf.data().write(to: file(for: show), options: .atomic)
    } catch {
      NSLog("Podcasts: the prints of a show could not be saved: \(error)")
    }
  }

  private func touch(_ url: URL) {
    try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
  }

  /// Deletes the files of the shows `PrintShelf` says no longer fit.
  private func evict() {
    let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
    guard
      let urls = try? FileManager.default.contentsOfDirectory(
        at: printsFolder, includingPropertiesForKeys: keys)
    else { return }
    let entries = urls.filter { $0.pathExtension == "bin" }.map { url -> PrintShelf.Entry in
      let values = try? url.resourceValues(forKeys: Set(keys))
      return PrintShelf.Entry(
        show: url.deletingPathExtension().lastPathComponent, bytes: values?.fileSize ?? 0,
        touched: values?.contentModificationDate?.timeIntervalSince1970 ?? 0)
    }
    for gone in PrintShelf.evictions(entries) {
      try? FileManager.default.removeItem(at: printsFolder.appendingPathComponent(gone + ".bin"))
    }
  }

  /// A file's bytes up to `limit` plus one (so a file over the limit is known, and reads as
  /// empty in the type's reader), or nil when there is no file.
  private static func read(_ url: URL, limit: Int) -> Data? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    return try? handle.read(upToCount: limit + 1)
  }
}

/// Which episodes were learned from already, for what must be learned once for each episode: the
/// phone's own sound prints (a second learning would count the same ad as seen again) and the
/// show's habits. `Podcasts/finder-learned.json`, the newest 400 episodes of each kind.
final class PodcastLearned: @unchecked Sendable {
  static let shared = PodcastLearned(url: defaultURL)

  enum Kind: String, CaseIterable { case own, habits }

  static var defaultURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Podcasts", isDirectory: true)
      .appendingPathComponent("finder-learned.json")
  }

  static let most = 400

  private let url: URL
  private let lock = NSLock()
  private var lists: [String: [String]]?

  init(url: URL) { self.url = url }

  /// True the first time it is asked for this episode and kind, and noted on disk before it
  /// returns; false after that.
  func firstTime(_ kind: Kind, episode: String) -> Bool {
    lock.withLock {
      var all = current()
      var list = all[kind.rawValue] ?? []
      guard !list.contains(episode) else { return false }
      list.append(episode)
      all[kind.rawValue] = Array(list.suffix(Self.most))
      lists = all
      do {
        try FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(all).write(to: url, options: .atomic)
      } catch {
        NSLog("Podcasts: the learned episodes could not be saved: \(error)")
      }
      return true
    }
  }

  /// The caller holds the lock.
  private func current() -> [String: [String]] {
    if let lists { return lists }
    var loaded: [String: [String]] = [:]
    if let data = try? Data(contentsOf: url),
      let saved = try? JSONDecoder().decode([String: [String]].self, from: data)
    {
      loaded = saved.mapValues { Array($0.suffix(Self.most)) }
    }
    lists = loaded
    return loaded
  }
}
