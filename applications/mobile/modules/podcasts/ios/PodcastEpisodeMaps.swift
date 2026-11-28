// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The Mac's episode maps on the phone. The Mac marks an episode on its own copy and writes a small
// map of that copy (`Podcasts/maps/<id>.json` in the linked folder, named in the episode's entry of
// `ahead-ads.json`). When the phone plays another download of the episode (a stream as it arrives,
// or the publisher's file), the map is fetched by the app, kept in `Podcasts/teaching/maps/`, and
// the phone's own audio is lined up against it: the Mac's marks are carried over to the frame and
// the stretches only the phone's copy has are ads too. What comes out are ads of the finder
// "ahead", so they are skipped, undone and shown as the Mac's marks always were. A copy that does
// not line up gives nothing, and the phone's own finders work as before. Every rule is in
// PodcastKit (`EpisodeMap`, `EpisodeMapAligner`, `AheadAds.carried`); this file reads the files.
// It reads audio, so it is never called from the main thread.
import Foundation
import PodcastAds
import PodcastAudioMatch
import PodcastDownloads

/// Follows one audio file with the map of its episode. The file may still be growing.
final class MapFollowing: @unchecked Sendable {
  private let lock = NSLock()
  private var name: String?
  private var follower: EpisodeMapFollower?

  /// What the map at `mapFile` gives for the bytes `file` holds now, or nil when the map or the
  /// file cannot be read. Only the bytes that are new since the last call are read.
  func carry(mapFile: URL, file: URL, complete: Bool) -> MapCarry? {
    lock.withLock { () -> MapCarry? in
      if name != mapFile.lastPathComponent || follower == nil {
        guard let data = try? Data(contentsOf: mapFile), let map = EpisodeMap(data: data) else {
          return nil
        }
        follower = EpisodeMapFollower(map: map)
        name = mapFile.lastPathComponent
      }
      guard var following = follower, let handle = try? FileHandle(forReadingFrom: file) else {
        return nil
      }
      defer { try? handle.close() }
      do {
        try handle.seek(toOffset: UInt64(following.bytesFed))
        while let data = try handle.read(upToCount: 1 << 20), !data.isEmpty {
          following.feed([UInt8](data))
        }
      } catch {
        return nil
      }
      follower = following
      return following.carry(complete: complete)
    }
  }
}

final class PodcastEpisodeMaps: @unchecked Sendable {
  static let shared = PodcastEpisodeMaps()

  static var folder: URL {
    PodcastTeaching.folder.appendingPathComponent(EpisodeMap.folder, isDirectory: true)
  }

  private let lock = NSLock()
  /// The downloaded file that was followed last, by its SHA-256.
  private var whole: (sha256: String, following: MapFollowing)?
  /// The skips the map gave for a downloaded file, by the file's SHA-256.
  private var skipsByFile: [String: [FoundAd]] = [:]

  private init() {}

  /// Where the phone keeps the map an entry names, or nil when the entry names no map or no
  /// copy. The file is named by the copy's SHA-256 (`EpisodeMap.fileName`), so when the Mac
  /// makes another copy of the episode its map is fetched and the old copy's map is not used.
  private static func file(_ entry: AheadEntry) -> URL? {
    guard entry.map != nil, let name = EpisodeMap.fileName(sha256: entry.copy?.sha256 ?? "")
    else { return nil }
    return folder.appendingPathComponent(name)
  }

  /// The episode's downloaded file and its SHA-256, or nil when it has none.
  private static func downloaded(_ episode: String) -> (file: URL, sha256: String)? {
    guard let entry = PodcastDownloader.shared.store?.entry(for: episode),
      case .downloaded(_, let sha, _, _) = entry.state,
      let file = PodcastDownloader.shared.localFile(for: episode)
    else { return nil }
    return (file, sha)
  }

  /// The map the app should fetch for this episode (`maps/<name>.json`, below `Podcasts/` of the
  /// linked folder), or nil: the Mac made none, the phone has the map of that copy already, or
  /// the phone has the Mac's own copy of the episode, whose marks need no map.
  func wanted(episode: String) -> String? {
    guard let entry = PodcastTeaching.shared.aheadEntry(episode: episode), let path = entry.map,
      let file = Self.file(entry), !FileManager.default.fileExists(atPath: file.path),
      Self.downloaded(episode)?.sha256 != entry.copy?.sha256
    else { return nil }
    return path
  }

  /// Keeps the map the app fetched for this episode. False when it is not a map, or not the map
  /// of the copy the episode's entry names.
  func install(episode: String, text: String) -> Bool {
    let data = Data(text.utf8)
    guard let entry = PodcastTeaching.shared.aheadEntry(episode: episode),
      let copy = entry.copy, let kept = Self.file(entry), let map = EpisodeMap(data: data),
      map.sha256 == copy.sha256
    else { return false }
    do {
      try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
      Self.removeOld()
      try data.write(to: kept, options: .atomic)
      return true
    } catch {
      NSLog("Podcasts: the episode map could not be saved: \(error)")
      return false
    }
  }

  /// Removes the maps that are older than the marks are kept.
  private static func removeOld() {
    let files = FileManager.default
    let oldest = Date().addingTimeInterval(-AheadFile.maxAgeDays * 86_400)
    for url in (try? files.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    {
      let changed = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate
      if let changed, changed < oldest { try? files.removeItem(at: url) }
    }
  }

  // MARK: What the map gives

  /// The ads the map gives for the episode's downloaded file, or for `staged` (a stream's file as
  /// it arrives, followed by `following`) while there is none: the Mac's marks in this copy's
  /// seconds and the stretches only this copy has. Empty when the episode has no map on the phone,
  /// the file is the Mac's own copy, or the copy does not line up with the map.
  func carried(episode: String, staged: URL? = nil, following: MapFollowing? = nil) -> [FoundAd] {
    guard let entry = PodcastTeaching.shared.aheadEntry(episode: episode),
      let mapFile = Self.file(entry), FileManager.default.fileExists(atPath: mapFile.path)
    else { return [] }
    let file = Self.downloaded(episode)
    if let file, file.sha256 == entry.copy?.sha256 { return [] }
    guard let source = file?.file ?? staged else { return [] }
    let follow = following ?? wholeFollowing(file?.sha256 ?? "")
    guard
      let carry = follow.carry(mapFile: mapFile, file: source, complete: file != nil),
      carry.lined
    else { return [] }
    let stretches =
      carry.marks.map { MapStretchAd(start: $0.start, end: $0.end, kind: $0.kind, from: $0.from) }
      + carry.unmatched.map { MapStretchAd(start: $0.start, end: $0.end) }
    return AheadAds.carried(stretches, entry: entry)
  }

  /// The follower of the downloaded file with this SHA-256, kept while that file is the last one
  /// looked at.
  private func wholeFollowing(_ sha256: String) -> MapFollowing {
    lock.withLock { () -> MapFollowing in
      if let whole, whole.sha256 == sha256 { return whole.following }
      let made = MapFollowing()
      whole = (sha256, made)
      return made
    }
  }

  /// The map's ads that skip on this episode, as the head scan of a stream takes the Mac's marks:
  /// of the sorts the listener skips, only where the finder "ahead" may skip on this show, at most
  /// unsure so the listener can undo them, and sorted by the Mac's settings. For a downloaded file
  /// they are remembered by its SHA-256 (`known(sha256:)`). Nil when iOS did not hold the time for
  /// the look, so what an earlier look gave still stands.
  func skips(episode: String, staged: URL? = nil, following: MapFollowing? = nil) -> [FoundAd]? {
    // No map on the phone: nothing is read and no guard mark is written.
    guard let entry = PodcastTeaching.shared.aheadEntry(episode: episode),
      let mapFile = Self.file(entry), FileManager.default.fileExists(atPath: mapFile.path)
    else { return [] }
    guard let show = EpisodeShows.shared.show(for: episode), !show.isEmpty else { return [] }
    let listener = PodcastAdFinder.listenerSwitches(forShow: show)
    guard listener.skipsAnySort else { return [] }
    let tuning = PodcastTeaching.shared.files.tuning
    let level = ShowTuning.stricter(
      PodcastFinderGuard.shared.mode(finder: FinderNames.ahead, show: show, episode: episode),
      tuning.level(forFinder: FinderNames.ahead, show: show))
    guard level == .skip else { return [] }
    let held = PodcastFinderGuard.shared.hold([FinderNames.ahead], episode: episode) { _ in
      self.carried(episode: episode, staged: staged, following: following)
    }
    guard let found = held else { return nil }
    let mine = found.filter { listener.allows($0.kind) }.map { ad -> FoundAd in
      var one = ad
      one.source = FinderNames.ahead
      one.confidence = min(ad.confidence, .unsure)
      return one
    }
    let skips = tuning.apply(to: mine, show: show).skip
    if let file = Self.downloaded(episode) { lock.withLock { skipsByFile[file.sha256] = skips } }
    return skips
  }

  /// The skips the map gave for the downloaded file with this SHA-256 in this launch.
  func known(sha256: String) -> [FoundAd] { lock.withLock { skipsByFile[sha256] ?? [] } }
}
