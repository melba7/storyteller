// LOFI-FORK: an episode's chapters (see FORK.md). Plain values, no AVFoundation.
import Foundation

/// One chapter of an episode.
public struct Chapter: Sendable, Equatable {
  /// Seconds from the start of the episode.
  public var start: Double
  /// Seconds, when the source says where the chapter ends. Otherwise it ends where the next
  /// one starts (or at the end of the episode).
  public var end: Double?
  public var title: String
  /// A picture's web address (the feed's `img`).
  public var imageURL: String?
  /// A picture's bytes (the file's `APIC` frame). The app saves them and shows the file.
  public var imageData: Data?
  /// A web page about the chapter.
  public var url: String?

  public init(
    start: Double, end: Double? = nil, title: String, imageURL: String? = nil,
    imageData: Data? = nil, url: String? = nil
  ) {
    self.start = start
    self.end = end
    self.title = title
    self.imageURL = imageURL
    self.imageData = imageData
    self.url = url
  }

  /// The key a chapter is known by when the listener's skip choices are saved: its start in
  /// milliseconds. It is stable as long as the chapter's start does not move.
  public var key: Int {
    guard start.isFinite else { return 0 }
    return Int((min(max(start, 0), ChapterList.maxStart) * 1000).rounded())
  }
}

public enum ChapterList {
  /// No episode is longer than this many seconds (about 115 days); a chapter that starts later is
  /// a bad file's, and a start this large must never reach an integer conversion.
  public static let maxStart = 10_000_000.0

  /// Puts chapters in order: drops any that start before 0, at no time or past `maxStart`, keeps the first of
  /// two that start at the same moment, and gives a chapter with no title the name "Chapter n".
  public static func tidy(_ chapters: [Chapter]) -> [Chapter] {
    var seen = Set<Int>()
    let sorted = chapters.filter { $0.start.isFinite && $0.start >= 0 && $0.start <= maxStart }
      .sorted { $0.start < $1.start }
      .filter { seen.insert($0.key).inserted }
    return sorted.enumerated().map { index, chapter in
      var chapter = chapter
      chapter.title = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
      if chapter.title.isEmpty { chapter.title = "Chapter \(index + 1)" }
      if let end = chapter.end, !(end.isFinite && end > chapter.start) { chapter.end = nil }
      return chapter
    }
  }

  /// The feed's chapters are preferred; the file's are used when the feed has none. A feed
  /// chapter with no picture takes the picture of a file chapter that starts within a second.
  public static func choose(feed: [Chapter], file: [Chapter]) -> [Chapter] {
    guard !feed.isEmpty else { return file }
    return feed.map { chapter in
      guard chapter.imageURL == nil, chapter.imageData == nil,
        let match = file.first(where: { abs($0.start - chapter.start) <= 1 && $0.imageData != nil })
      else { return chapter }
      var chapter = chapter
      chapter.imageData = match.imageData
      return chapter
    }
  }
}

/// The Podcasting 2.0 JSON chapters file (`application/json+chapters`).
public enum ChapterJSON {
  /// Reads the file. Anything that is not a chapters file gives none. Chapters with `toc` set
  /// to false are silent markers and are left out, as the format asks.
  public static func parse(_ data: Data) -> [Chapter] {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let list = root["chapters"] as? [Any]
    else { return [] }
    var chapters: [Chapter] = []
    for case let entry as [String: Any] in list {
      guard let start = number(entry["startTime"]) else { continue }
      if let toc = entry["toc"] as? Bool, !toc { continue }
      chapters.append(
        Chapter(
          start: start, end: number(entry["endTime"]), title: entry["title"] as? String ?? "",
          imageURL: web(entry["img"]), url: web(entry["url"])))
    }
    return ChapterList.tidy(chapters)
  }

  /// A number, or a number written as text.
  private static func number(_ value: Any?) -> Double? {
    if let number = value as? Double { return number.isFinite ? number : nil }
    if let text = value as? String, let number = Double(text.trimmingCharacters(in: .whitespaces)) {
      return number.isFinite ? number : nil
    }
    return nil
  }

  /// An http or https address, or nil.
  private static func web(_ value: Any?) -> String? {
    guard let text = (value as? String)?.trimmingCharacters(in: .whitespaces),
      let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    else { return nil }
    return text
  }
}
