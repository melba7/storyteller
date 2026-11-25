// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// What the Mac taught the phone, kept in `Podcasts/teaching/`: the small model, the library of
// ads, the shows' habits, the table of feeds, the Mac's marks of the night before (and the table
// of episodes that tells which episode is which mark) and the sounds. It is read the first time
// something asks and again after each install, only from a background task: the head scan, the
// ad finder and the module's own async functions. A missing or broken file is simply nothing taught.
// The rules (the shapes of the files, the table, the state) are PodcastAds and PodcastAudioMatch.
import Foundation
import PodcastAds
import PodcastAudioMatch
import PodcastDownloads

/// What the Mac taught, read the first time it is asked and again after each install. Safe from any thread.
final class PodcastTeaching: @unchecked Sendable {
  static let shared = PodcastTeaching()

  static var folder: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Podcasts", isDirectory: true)
      .appendingPathComponent("teaching", isDirectory: true)
  }

  private struct Taught {
    var files: TeachingFiles
    var sounds: AdSoundLibrary
    /// What the app told of its episodes (guid, feed, title), to find an episode's Mac marks.
    var episodes: [String: AheadEpisodes.Facts]
  }

  private let lock = NSLock()
  private var taught: Taught?
  private var passes: AheadPasses?
  private var soundsInstallCount = 0

  private init() {}

  /// How many times a new sounds file was installed in this launch. The finder looks at it to know
  /// when the files it read for sounds are to be read again.
  var soundsInstalls: Int { lock.withLock { soundsInstallCount } }

  /// The model, the taught ads, the habits and the local finders made of them.
  var files: TeachingFiles { read().files }
  var sounds: AdSoundLibrary { read().sounds }

  /// What the folder holds, read when it has not been. The lock is held while reading, as in
  /// `PodcastKnownAds`, so two callers never read the same files twice.
  private func read() -> Taught {
    lock.withLock {
      if let taught { return taught }
      let folder = Self.folder
      let loaded = Taught(
        files: TeachingFiles.load(folder: folder, now: Date(), shows: TeachingShows.load(from: folder)),
        sounds: AdSoundLibrary.load(from: folder.appendingPathComponent(AdSoundLibrary.fileName)),
        episodes: AheadEpisodes.load(from: folder))
      taught = loaded
      return loaded
    }
  }

  /// Checks that the text is the file whose SHA-256 is `sha256`, and that it reads as the file
  /// `name`, then keeps it and notes it in the state. False when it was refused; the old file
  /// stays then.
  func install(name: String, text: String, sha256: String) -> Bool {
    let data = Data(text.utf8)
    let actual = Sha256Stream.hash(of: data)
    guard actual == sha256.lowercased() else { return false }
    return lock.withLock {
      let folder = Self.folder
      let kept =
        name == AdSoundLibrary.fileName
        ? AdSoundLibrary.install(data: data, folder: folder)
        : TeachingFiles.install(name: name, data: data, folder: folder)
      guard kept else { return false }
      if name == AdSoundLibrary.fileName { soundsInstallCount += 1 }
      var state = TeachingState.load(from: folder)
      state.record(name: name, sha256: actual, at: Date())
      do {
        try state.save(to: folder)
      } catch {
        NSLog("Podcasts: the teaching state could not be saved: \(error)")
      }
      taught = nil
      return true
    }
  }

  /// Saves which feed is which show (`{"<feed key>": "<show id>"}`). A text that is not such an
  /// object, or a table that is the one saved already, changes nothing. True when the table
  /// changed.
  @discardableResult
  func setShows(json: String) -> Bool {
    guard let table = TeachingShows.parse(json) else { return false }
    return lock.withLock {
      guard table != TeachingShows.load(from: Self.folder) else { return false }
      do {
        try TeachingShows.save(table, to: Self.folder)
        taught = nil
        return true
      } catch {
        NSLog("Podcasts: the table of shows could not be saved: \(error)")
        return false
      }
    }
  }

  /// The Mac's marks of the night before for an episode of the app (`ahead-ads.json`, found by the
  /// episode's guid, or its feed and title, from the table the app sent), or nil.
  func aheadEntry(episode: String, now: Date = Date()) -> AheadEntry? {
    let taught = read()
    return taught.files.aheadEntry(episode: episode, table: taught.episodes, now: now)
  }

  /// Saves what the app knows of its episodes (`{"<episode id>": {"feed", "guid", "title"}}`). A
  /// text that is not such an object, or a table that is the one saved already, changes nothing.
  /// True when the table changed. The files already read stay; only their table is replaced.
  func setAheadEpisodes(json: String) -> Bool {
    guard let table = AheadEpisodes.parse(json) else { return false }
    return lock.withLock {
      guard table != AheadEpisodes.load(from: Self.folder) else { return false }
      do {
        try AheadEpisodes.save(table, to: Self.folder)
        taught?.episodes = table
        return true
      } catch {
        NSLog("Podcasts: the table of episodes could not be saved: \(error)")
        return false
      }
    }
  }

  // MARK: What the ahead finder has looked at

  /// Whether the ahead finder has not looked at this episode yet with marks made at `marked`.
  func aheadPassNeeded(episode: String, marked: Double) -> Bool {
    lock.withLock { passesLoaded().needs(episode: episode, marked: marked) }
  }

  /// Notes that the ahead finder looked at this episode with marks made at `marked`, so the pass is
  /// not made again at the next start, and is made when newer marks come.
  func recordAheadPass(episode: String, marked: Double) {
    lock.withLock {
      var current = passesLoaded()
      current.record(episode: episode, marked: marked)
      passes = current
      do {
        try current.save(to: Self.folder)
      } catch {
        NSLog("Podcasts: the record of the Mac's marks could not be saved: \(error)")
      }
    }
  }

  /// The record, read when it has not been. Called with the lock held.
  private func passesLoaded() -> AheadPasses {
    if let passes { return passes }
    let loaded = AheadPasses.load(from: Self.folder)
    passes = loaded
    return loaded
  }

  /// `getTeachingState()`: the installed files, the model's numbers and how much was taught.
  func stateJSON() -> String {
    let taught = read()
    let folder = Self.folder
    let state = lock.withLock { TeachingState.load(from: folder) }
    return state.json(
      model: TeachingFiles.modelInfo(in: folder), library: taught.files.seeds.ads.count,
      habits: taught.files.habits.shows.count, sounds: taught.sounds.sounds.count)
  }

  // MARK: Sounds

  /// The taught sounds in the first bytes of a stream.
  func soundAds(in data: Data) -> [FoundAd] {
    Self.ads(AdSoundFile.hits(in: data, library: sounds))
  }

  /// The taught sounds in a downloaded file, which is read in pieces.
  func soundAds(inFile url: URL) -> [FoundAd] {
    Self.ads(AdSoundFile.hits(in: url, library: sounds))
  }

  /// A hit whose sort is not known is left out.
  private static func ads(_ hits: [AdSoundHit]) -> [FoundAd] {
    hits.compactMap {
      LocalAdsFile.soundAd(sort: $0.sort, who: $0.who, start: $0.start, end: $0.end)
    }
  }
}
