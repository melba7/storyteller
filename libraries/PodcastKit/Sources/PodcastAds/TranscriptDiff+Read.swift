// LOFI-FORK: reads the words out of a feed's transcript file (see FORK.md). Foundation only.
import Foundation

extension TranscriptDiff {
  /// The words of a transcript file, as they are compared (`KnownAds.normalise`): without the
  /// header, notes, cue numbers, times, tags and speaker labels of WebVTT and SubRip, the times
  /// and speakers of a Podcasting 2.0 JSON file, and the tags of HTML. `type` is the feed's
  /// MIME type; only "json" in it is read as JSON, anything else as lines of text. A file that
  /// cannot be read gives no words.
  public static func plainWords(_ file: String, type: String) -> [String] {
    let text = type.lowercased().contains("json") ? jsonText(file) : cueText(file)
    return text.split(whereSeparator: \.isWhitespace).compactMap { KnownAds.normalise(String($0)) }
  }

  /// The text of each segment of a Podcasting 2.0 JSON transcript: `{"segments": [{"body": ...}]}`.
  private static func jsonText(_ file: String) -> String {
    guard let root = try? JSONSerialization.jsonObject(with: Data(file.utf8)) as? [String: Any],
      let segments = root["segments"] as? [[String: Any]]
    else { return "" }
    return segments.compactMap { $0["body"] as? String }.joined(separator: " ")
  }

  private static let tag = try? NSRegularExpression(pattern: "<[^>]*>")
  private static let entity = try? NSRegularExpression(pattern: "&#?[A-Za-z0-9]+;")
  /// "Sam: ", "SPEAKER 2: " or "Dr. Jane Smith: " at the start of a line: up to three words.
  private static let label = try? NSRegularExpression(
    pattern: #"^[\p{L}\p{N}.'’_-]+(?: [\p{L}\p{N}.'’_-]+){0,2}:\s+"#)

  private static func remove(_ pattern: NSRegularExpression?, in text: String, with: String) -> String {
    pattern?.stringByReplacingMatches(
      in: text, range: NSRange(text.startIndex..., in: text), withTemplate: with) ?? text
  }

  /// The spoken text of WebVTT, SubRip, HTML or plain text.
  private static func cueText(_ file: String) -> String {
    let body = file.replacingOccurrences(of: "\u{FEFF}", with: "")
    let isVTT = body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("WEBVTT")
    let lines = body.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
    var spoken: [String] = []
    var inBlock = false
    for (number, line) in lines.enumerated() {
      if line.isEmpty {
        inBlock = false
        continue
      }
      // A WebVTT header, note, style or region runs to the next blank line.
      if isVTT {
        if line.hasPrefix("WEBVTT")
          || ["NOTE", "STYLE", "REGION"].contains(where: { line == $0 || line.hasPrefix($0 + " ") })
        {
          inBlock = true
        }
        if inBlock { continue }
      }
      // A time line, and the cue's number or name just before it.
      if line.contains("-->") || (number + 1 < lines.count && lines[number + 1].contains("-->")) {
        continue
      }
      var text = remove(tag, in: line, with: " ")
      for apostrophe in ["&#39;", "&apos;", "&rsquo;", "&#8217;"] {
        text = text.replacingOccurrences(of: apostrophe, with: "")
      }
      text = remove(entity, in: text, with: " ")
      spoken.append(remove(label, in: text.trimmingCharacters(in: .whitespaces), with: ""))
    }
    return spoken.joined(separator: " ")
  }
}
