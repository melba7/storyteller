// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Where an episode's chapters come from: the feed's JSON chapters file, and the downloaded
// audio file (an MP3's ID3 chapter frames, read by PodcastChapters, or an M4A's chapter track,
// read by AVFoundation). Pictures that come as bytes are saved as small files so the app can
// show them by address. The rules (which source wins, which chapter is playing) are in
// PodcastChapters.

import AVFoundation
import Foundation
import PodcastChapters

enum PodcastChapterSource {
  /// A chapters file is a few kilobytes; this stops a wrong address from filling memory.
  static let maxJSONBytes = 2 * 1024 * 1024
  /// An ID3 tag with pictures can be large, but not this large.
  static let maxTagBytes = 32 * 1024 * 1024

  // MARK: The feed

  /// The feed's JSON chapters. Nothing when the address is bad, the server fails or the
  /// answer is not a chapters file.
  static func fromFeed(_ address: String) async -> [Chapter] {
    guard let url = URL(string: address), let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https", url.host != nil
    else { return [] }
    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.setValue("StorytellerLofi/1.0 podcast client", forHTTPHeaderField: "User-Agent")
    guard let (data, response) = try? await URLSession.shared.data(for: request),
      (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
      data.count <= maxJSONBytes
    else { return [] }
    return ChapterJSON.parse(data)
  }

  // MARK: The file

  /// The downloaded file's chapters: an ID3 tag first (MP3), then the file's own chapter track
  /// (M4A and the like).
  static func fromFile(_ file: URL) async -> [Chapter] {
    let id3 = id3Chapters(file)
    if !id3.isEmpty { return id3 }
    return await appleChapters(file)
  }

  private static func id3Chapters(_ file: URL) -> [Chapter] {
    guard let handle = try? FileHandle(forReadingFrom: file) else { return [] }
    defer { try? handle.close() }
    guard let header = try? handle.read(upToCount: 10),
      let length = ID3Chapters.tagLength(header: header), length <= maxTagBytes
    else { return [] }
    try? handle.seek(toOffset: 0)
    guard let data = try? handle.read(upToCount: length) else { return [] }
    return ID3Chapters.read(data)
  }

  private static func appleChapters(_ file: URL) async -> [Chapter] {
    let asset = AVURLAsset(url: file)
    guard
      let groups = try? await asset.loadChapterMetadataGroups(
        bestMatchingPreferredLanguages: Locale.preferredLanguages)
    else { return [] }
    var chapters: [Chapter] = []
    for group in groups {
      var title = ""
      var picture: Data?
      for item in group.items {
        if item.commonKey == .commonKeyTitle, let text = try? await item.load(.stringValue) {
          title = text
        } else if item.commonKey == .commonKeyArtwork, let data = try? await item.load(.dataValue) {
          picture = data
        }
      }
      let end = group.timeRange.end.seconds
      chapters.append(
        Chapter(
          start: group.timeRange.start.seconds, end: end.isFinite ? end : nil, title: title,
          imageData: picture))
    }
    return ChapterList.tidy(chapters)
  }

  // MARK: Pictures

  /// Saves each chapter's picture bytes as a file in the caches folder and gives the chapter
  /// the file's address instead. Chapters with a web address or no picture stay as they are.
  static func savingPictures(_ chapters: [Chapter], episodeId: String) -> [Chapter] {
    guard chapters.contains(where: { $0.imageData != nil }) else { return chapters }
    let safe = String(episodeId.filter { $0.isLetter || $0.isNumber || $0 == "-" })
    guard !safe.isEmpty,
      let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    else { return chapters.map(withoutBytes) }
    let folder = caches.appendingPathComponent("PodcastChapterArt", isDirectory: true)
      .appendingPathComponent(safe, isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return chapters.map { chapter in
      guard let data = chapter.imageData, chapter.imageURL == nil else { return withoutBytes(chapter) }
      let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
      let file = folder.appendingPathComponent("\(chapter.key).\(isPNG ? "png" : "jpg")")
      var saved = withoutBytes(chapter)
      if (try? data.write(to: file, options: .atomic)) != nil { saved.imageURL = file.absoluteString }
      return saved
    }
  }

  private static func withoutBytes(_ chapter: Chapter) -> Chapter {
    var chapter = chapter
    chapter.imageData = nil
    return chapter
  }
}
