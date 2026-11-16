import Foundation

// The small readers behind FeedParser: show notes as plain text, durations and dates.

extension FeedParser {
  // MARK: Notes

  private static let breakingTags = try! NSRegularExpression(
    pattern: "<br\\s*/?>|</(?:p|li|div|h[1-6]|tr|blockquote)\\s*>", options: [.caseInsensitive])
  private static let anyTag = try! NSRegularExpression(
    pattern: "<!--.*?-->|</?[A-Za-z][^>]*>", options: [.dotMatchesLineSeparators])
  private static let entity = try! NSRegularExpression(
    pattern: "&(#[xX][0-9A-Fa-f]+|#[0-9]+|[A-Za-z][A-Za-z0-9]*);")

  private static let namedEntities: [String: String] = [
    "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
    "ndash": "–", "mdash": "—", "hellip": "…", "lsquo": "‘", "rsquo": "’",
    "ldquo": "“", "rdquo": "”", "copy": "©", "reg": "®", "trade": "™",
    "bull": "•", "middot": "·", "euro": "€", "pound": "£", "laquo": "«", "raquo": "»",
  ]

  /// Show notes as plain text: tags removed, entities decoded, `<br>`, `</p>` and `</li>` turned
  /// into line breaks and runs of blank lines collapsed to one.
  static func plainText(_ html: String) -> String {
    var text = replace(breakingTags, in: html, with: "\n")
    text = replace(anyTag, in: text, with: "")
    text = decodeEntities(text)
    text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(
      of: "\r", with: "\n")

    var lines: [String] = []
    for raw in text.components(separatedBy: "\n") {
      let line = raw.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\u{A0}" })
        .joined(separator: " ")
      if line.isEmpty && (lines.last?.isEmpty ?? true) { continue }
      lines.append(line)
    }
    while lines.last?.isEmpty == true { lines.removeLast() }
    return lines.joined(separator: "\n")
  }

  private static func replace(_ regex: NSRegularExpression, in text: String, with template: String)
    -> String
  {
    let range = NSRange(text.startIndex..., in: text)
    return regex.stringByReplacingMatches(
      in: text, options: [], range: range,
      withTemplate: NSRegularExpression.escapedTemplate(for: template))
  }

  /// Decodes common named entities and numeric ones in one pass. Anything it does not know stays as written.
  private static func decodeEntities(_ text: String) -> String {
    let whole = NSRange(text.startIndex..., in: text)
    var result = ""
    var last = text.startIndex
    for match in entity.matches(in: text, options: [], range: whole) {
      guard let all = Range(match.range, in: text), let body = Range(match.range(at: 1), in: text)
      else { continue }
      let name = String(text[body])
      guard let decoded = decode(entity: name) else { continue }
      result += text[last..<all.lowerBound]
      result += decoded
      last = all.upperBound
    }
    result += text[last...]
    return result
  }

  private static func decode(entity name: String) -> String? {
    if name.hasPrefix("#") {
      let digits = name.dropFirst()
      let value: UInt32?
      if digits.first == "x" || digits.first == "X" {
        value = UInt32(digits.dropFirst(), radix: 16)
      } else {
        value = UInt32(digits)
      }
      guard let value, let scalar = Unicode.Scalar(value) else { return nil }
      return value == 0xA0 ? " " : String(Character(scalar))
    }
    return namedEntities[name]
  }

  // MARK: Audio

  private static let audioExtensions: [String: String] = [
    "mp3": "audio/mpeg", "m4a": "audio/x-m4a", "aac": "audio/aac", "mp4": "audio/mp4",
    "ogg": "audio/ogg", "oga": "audio/ogg", "opus": "audio/ogg", "wav": "audio/wav",
    "flac": "audio/flac",
  ]

  /// An enclosure is audio when its type says so. A missing or generic type is trusted when the
  /// address ends in a known audio extension.
  static func looksLikeAudio(type: String, url: URL) -> Bool {
    if type.hasPrefix("audio/") { return true }
    if type.isEmpty || type == "application/octet-stream" || type == "binary/octet-stream" {
      return audioExtensions[url.pathExtension.lowercased()] != nil
    }
    return false
  }

  /// The type to store when the feed gave none.
  static func guessedType(_ url: URL) -> String {
    audioExtensions[url.pathExtension.lowercased()] ?? "audio/mpeg"
  }

  // MARK: Durations

  /// `HH:MM:SS`, `MM:SS` or plain seconds (decimals allowed). Anything else is nil.
  static func parseDuration(_ text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = trimmed.components(separatedBy: ":")
    guard (1...3).contains(parts.count) else { return nil }
    var total = 0.0
    for (index, part) in parts.enumerated() {
      let isLast = index == parts.count - 1
      let pattern = isLast ? "^[0-9]+(\\.[0-9]+)?$" : "^[0-9]+$"
      guard part.range(of: pattern, options: .regularExpression) != nil, let value = Double(part)
      else { return nil }
      total = total * 60 + value
    }
    return total
  }

  // MARK: Dates

  /// Reads RFC 822 dates and their usual variants, and ISO 8601 as a last try.
  /// Make one per feed: a date formatter is slow to create.
  final class DateParser {
    private let formats: [(twoDigitYear: Bool, formatter: DateFormatter)]
    private let iso = ISO8601DateFormatter()

    private static let zones: [String: String] = [
      "GMT": "+0000", "UT": "+0000", "UTC": "+0000", "Z": "+0000",
      "EST": "-0500", "EDT": "-0400", "CST": "-0600", "CDT": "-0500",
      "MST": "-0700", "MDT": "-0600", "PST": "-0800", "PDT": "-0700",
    ]

    init() {
      var formats: [(Bool, DateFormatter)] = []
      for twoDigitYear in [false, true] {
        for month in ["MMM", "MMMM"] {
          for seconds in [":ss", ""] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = "d \(month) \(twoDigitYear ? "yy" : "yyyy") HH:mm\(seconds) Z"
            formats.append((twoDigitYear, formatter))
          }
        }
      }
      self.formats = formats
    }

    func parse(_ text: String) -> Date? {
      var words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
      guard !words.isEmpty else { return nil }
      if let first = words.first, first.hasSuffix(",") { words.removeFirst() }  // "Mon,"
      if let date = iso.date(from: words.joined(separator: " ")) { return date }

      // Put the zone in the form `+hhmm`; no zone means UTC.
      if let zone = words.last {
        if zone.range(of: "^[+-][0-9]{2}:?[0-9]{2}$", options: .regularExpression) != nil {
          words[words.count - 1] = zone.replacingOccurrences(of: ":", with: "")
        } else if let offset = Self.zones[zone.uppercased()] {
          words[words.count - 1] = offset
        } else {
          words.append("+0000")
        }
      }
      let normalised = words.joined(separator: " ")
      let twoDigitYear =
        normalised.range(
          of: "^[0-9]{1,2} [A-Za-z]+ [0-9]{2} [0-9]", options: .regularExpression) != nil
      for (isTwoDigit, formatter) in formats where isTwoDigit == twoDigitYear {
        if let date = formatter.date(from: normalised) { return date }
      }
      return nil
    }
  }

  static func parseDate(_ text: String) -> Date? {
    DateParser().parse(text)
  }
}
