// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// The copies of episodes the Mac prepared (docs/PLAN.md, "Prepared episodes"). The app's
// JavaScript copies the file out of the linked folder; this side says which copies to take, checks
// a copy and installs it as the episode's download with the ads file made from the Mac's marks, and
// gives back a copy that was taken only for the list. Every decision is PodcastAds' PreparedCopies
// and PreparedInstall; this file reads what the phone knows and does what they say.
import AVFoundation
import Foundation
import PodcastAds
import PodcastDownloads

enum PodcastPrepared {
  /// What the app says of one episode: where it stands on the phone's list of next episodes
  /// (counted from 0, absent when it is not there), whether it was started, and its show.
  private struct Asked: Decodable {
    var id: String
    var listPlace: Int?
    var started: Bool?
    var showId: String?
    /// Anywhere in the listener's whole list of next episodes, also past the places taken.
    var stillListed: Bool?
  }

  // MARK: The plan

  /// `{"take": [{"id", "file", "sha256", "bytes", "fileExtension"}], "giveBack": ["<id>"]}` as JSON
  /// text, for the candidates (a JSON list of `Asked`). An empty plan for text that cannot be read.
  static func plan(json: String) async -> String {
    let empty = #"{"giveBack":[],"take":[]}"#
    guard let asked = try? JSONDecoder().decode([Asked].self, from: Data(json.utf8)) else {
      return empty
    }
    let playing = await MainActor.run { PodcastPlayer.shared.current?.id }
    let downloader = PodcastDownloader.shared
    var candidates: [PreparedCopies.Candidate] = []
    var shows: [String: String] = [:]
    for one in asked where !one.id.isEmpty {
      // An episode of a show whose ad skipping is off gets no copy: the Mac's marks are not used.
      // It still goes to the plan, with no listed copy, so a copy taken earlier is given back.
      var skips = true
      if let show = one.showId, !show.isEmpty {
        skips = PodcastAdFinder.listenerSwitches(forShow: show).skipsAnySort
        if skips { shows[one.id] = show }
      }
      let entry = downloader.store?.entry(for: one.id)
      candidates.append(
        PreparedCopies.Candidate(
          id: one.id, listPlace: one.listPlace, download: download(of: one.id, entry),
          started: one.started ?? false, inPlayer: playing == one.id,
          copyForListOnly: entry?.copyForList ?? false,
          listed: skips ? PodcastTeaching.shared.aheadEntry(episode: one.id)?.copy : nil,
          stillListed: one.stillListed ?? false))
    }
    let made = PreparedCopies.plan(candidates)
    var take: [[String: Any]] = []
    for id in made.take {
      guard let copy = candidates.first(where: { $0.id == id })?.listed,
        let ext = PreparedInstall.fileExtension(of: copy)
      else { continue }
      // The finder reads an episode's show by its id once the copy is installed.
      if let show = shows[id] { EpisodeShows.shared.remember(show, for: id) }
      take.append(
        ["id": id, "file": copy.file, "sha256": copy.sha256, "bytes": Double(copy.bytes),
         "fileExtension": ext])
    }
    let object: [String: Any] = ["take": take, "giveBack": made.giveBack]
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
      let text = String(data: data, encoding: .utf8)
    else { return empty }
    return text
  }

  /// What the phone has of the episode's audio, as the plan's rules know it.
  private static func download(of id: String, _ entry: DownloadEntry?) -> PreparedCopies.Download {
    let downloader = PodcastDownloader.shared
    if downloader.isPlayThrough(id) { return .moving }
    guard let entry else { return .none }
    switch entry.state {
    case .queued, .downloading: return .moving
    case .downloaded(_, let sha256, _, _):
      return downloader.localFile(for: id) == nil ? .none : .downloaded(sha256: sha256)
    case .failed: return .none
    }
  }

  // MARK: Installing

  /// Installs the file at `uri` as the episode's download when it is the copy the Mac lists for the
  /// episode: the size and the SHA-256 are checked here, and the copy is looked up again here, not
  /// taken from the app. Answers "installed" or why not in one word (`PreparedInstall.Refusal`,
  /// or "adsNotSaved", "unreadable", "failed"). The file at `uri` is moved into the downloads and
  /// is gone on success; on any answer the app removes what is left.
  static func install(episodeId: String, uri: String, address: String, forListOnly: Bool) async
    -> String
  {
    let downloader = PodcastDownloader.shared
    guard let store = downloader.store else { return "failed" }
    let listed = PodcastTeaching.shared.aheadEntry(episode: episodeId)
    let playing = await MainActor.run { PodcastPlayer.shared.current?.id == episodeId }
    if let refusal = PreparedInstall.early(
      listed: listed?.copy, inPlayer: playing, moving: isMoving(episodeId, store))
    {
      return refusal.rawValue
    }
    guard let entry = listed, let copy = entry.copy,
      let ext = PreparedInstall.fileExtension(of: copy)
    else { return "noCopy" }
    let existing = store.entry(for: episodeId)
    guard existing != nil || isWebAddress(address) else { return "failed" }

    let source = fileURL(from: uri)
    let bytes: Int64
    let sha256: String
    do {
      bytes = (try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int64) ?? 0
      // Only a file of the listed size is read through, so a wrong file costs nothing.
      if bytes == copy.bytes {
        sha256 = try await Task.detached(priority: .utility) { try FileHash.sha256(of: source) }
          .value
      } else {
        sha256 = ""
      }
    } catch {
      return "unreadable"
    }
    if let refusal = PreparedInstall.late(listed: copy, bytes: bytes, sha256: sha256) {
      return refusal.rawValue
    }
    // The ads file is made before the swap, so a copy with no ads file is not installed.
    guard let seconds = await duration(of: source),
      let ads = PreparedAds.file(
        for: entry, duration: seconds, detector: PodcastAdFinder.detectorName)
    else { return "unreadable" }

    let staged: URL
    do { staged = try store.stage(source, episodeId: episodeId) } catch { return "failed" }
    // The swap itself runs on the main actor, where the player loads files, so the episode cannot
    // be loaded between the last look and the swap.
    let done: DownloadEntry? = await MainActor.run {
      guard PodcastPlayer.shared.current?.id != episodeId, !isMoving(episodeId, store) else {
        try? FileManager.default.removeItem(at: staged)
        return nil
      }
      let before = store.entry(for: episodeId)
      do {
        if before == nil {
          try store.put(
            DownloadEntry(
              episodeId: episodeId, url: address, fileExtension: ext, state: .queued,
              automatic: true,
              copyForList: PreparedInstall.forList(existing: nil, forListOnly: forListOnly)))
        }
        return try store.install(
          episodeId: episodeId, staged: staged, sha256: sha256, fileExtension: ext, bytes: bytes,
          requireEntry: true)
      } catch {
        try? FileManager.default.removeItem(at: staged)
        if before == nil { _ = try? store.delete(episodeId: episodeId) }
        return nil
      }
    }
    guard let done else { return "failed" }
    // The old file's results are gone with its folder; the finder and the transcriber start over.
    if existing != nil { PodcastAdFinder.shared.removed(episodeId) }
    do {
      try AdsStore(folder: try store.folder(for: episodeId), sha256: sha256).save(ads)
    } catch {
      NSLog("Podcasts: the ads of a prepared copy could not be saved: \(error)")
      downloader.emit(done)
      PodcastTranscriber.shared.downloaded(episodeId)
      return "adsNotSaved"
    }
    downloader.emit(done)
    PodcastTranscriber.shared.downloaded(episodeId)
    return "installed"
  }

  // MARK: Giving back

  /// Removes the download of an episode whose copy was taken only for the list. False when the
  /// download is not such a copy, or the episode is in the player or being fetched.
  static func giveBack(episodeId: String) async -> Bool {
    await MainActor.run {
      let downloader = PodcastDownloader.shared
      guard let store = downloader.store, let entry = store.entry(for: episodeId),
        entry.copyForList, PodcastPlayer.shared.current?.id != episodeId,
        !isMoving(episodeId, store)
      else { return false }
      do {
        try downloader.remove(episodeId: episodeId)
        return true
      } catch {
        NSLog("Podcasts: a prepared copy could not be given back: \(error)")
        return false
      }
    }
  }

  // MARK: Helpers

  /// Whether the episode is being downloaded now, or fetched by the player as it plays.
  private static func isMoving(_ id: String, _ store: DownloadStore) -> Bool {
    PodcastDownloader.shared.isPlayThrough(id) || (store.entry(for: id)?.state.isActive ?? false)
  }

  private static func isWebAddress(_ address: String) -> Bool {
    guard let url = URL(string: address), let scheme = url.scheme?.lowercased() else {
      return false
    }
    return (scheme == "http" || scheme == "https") && url.host != nil
  }

  private static func fileURL(from uri: String) -> URL {
    if let url = URL(string: uri), url.isFileURL { return url }
    return URL(fileURLWithPath: uri)
  }

  /// The length of the audio file in seconds, or nil when it cannot be read.
  private static func duration(of file: URL) async -> Double? {
    let asset = AVURLAsset(
      url: file, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    guard let time = try? await asset.load(.duration), time.isNumeric else { return nil }
    let seconds = CMTimeGetSeconds(time)
    return seconds.isFinite && seconds > 0 ? seconds : nil
  }
}
