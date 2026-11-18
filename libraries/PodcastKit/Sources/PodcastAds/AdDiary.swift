// LOFI-FORK: the ad finder's diary, the steps it took and the errors it met (see FORK.md).
//
// The diary is for Mo: it shows why an ad was missed, for example what the head scan and the
// model did in the first minute of a stream. It is `ad-diary.jsonl` beside the skip log, one JSON
// object to a line with `"kind":"diary"`, the newest 500 lines. It holds a time, a short episode
// id and a short mark, and never words of the episode, addresses or keys. It stays on the phone
// and leaves it only inside the copy the listener sends with "Send skip log". These are the
// rules and the file's text; the app writes the file. Foundation only.
import Foundation

public enum AdDiary {
  /// The most lines the diary keeps. The oldest go first.
  public static let maxLines = 500
  /// The diary's file name, beside the skip log.
  public static let fileName = "ad-diary.jsonl"
  /// A mark is cut to this many characters.
  static let maxWhatLength = 160
  /// A word of a mark longer than this is left out: it is more likely a key than a word.
  static let maxWordLength = 80
  /// How many characters of an episode's id a line keeps.
  static let idLength = 8

  private struct Line: Codable {
    var episode: String
    var kind: String
    var time: Double
    var what: String
  }

  private struct KindOnly: Decodable { var kind: String? }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }()

  /// One diary line, without its line break: when (seconds since 1970, to the millisecond), the
  /// episode's short id and the mark. The mark is made safe by `clean`.
  public static func line(at time: Double, episodeId: String, what: String) -> String {
    let plain = episodeId.filter { $0.isLetter || $0.isNumber || $0 == "-" }
    let line = Line(
      episode: String(plain.prefix(idLength)), kind: "diary",
      time: (time * 1000).rounded() / 1000, what: clean(what))
    guard let data = try? encoder.encode(line) else { return "" }
    return String(decoding: data, as: UTF8.self)
  }

  /// A mark as one short line of plain words. The words with a slash (an address or a path),
  /// an at sign or `www.` in them, and the very long ones, are left out, so a system error's
  /// text cannot carry an address or a key into the diary.
  static func clean(_ what: String) -> String {
    let kept = what.split(whereSeparator: { $0.isWhitespace }).filter { word in
      word.count <= maxWordLength && !word.contains("/") && !word.contains("@")
        && !word.lowercased().hasPrefix("www.")
    }
    let text = String(kept.joined(separator: " ").prefix(maxWhatLength))
      .trimmingCharacters(in: .whitespaces)
    return text.isEmpty ? "(nothing)" : text
  }

  /// The newest `maxLines` lines of the text, each ending with a line break. Blank lines go.
  public static func trimmed(_ text: String, maxLines: Int = maxLines) -> String {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
      .suffix(max(0, maxLines))
    return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
  }

  /// The text with `line` added and trimmed. A line that says what the last line says (the same
  /// episode, the same mark) is not added, so a step that repeats while the transcript grows
  /// does not push the first minutes out of the diary.
  public static func appending(
    _ line: String, to text: String, maxLines: Int = maxLines
  ) -> String {
    guard !line.isEmpty else { return trimmed(text, maxLines: maxLines) }
    if let last = text.split(separator: "\n").last, sameStep(String(last), line) {
      return trimmed(text, maxLines: maxLines)
    }
    return trimmed(text + "\n" + line, maxLines: maxLines)
  }

  private static func sameStep(_ first: String, _ second: String) -> Bool {
    let decoder = JSONDecoder()
    guard let one = try? decoder.decode(Line.self, from: Data(first.utf8)),
      let two = try? decoder.decode(Line.self, from: Data(second.utf8))
    else { return false }
    return one.episode == two.episode && one.what == two.what
  }

  /// Whether a line of a log file is a diary line (`"kind":"diary"`, with or without a space).
  public static func isDiaryLine(_ line: String) -> Bool {
    guard line.contains("diary"),
      let found = try? JSONDecoder().decode(KindOnly.self, from: Data(line.utf8))
    else { return false }
    return found.kind == "diary"
  }

  /// The text of the copy that is sent: the skip log's lines, then the diary's. The skip log
  /// holds no diary line, and if it did, they would not be doubled.
  public static func shared(skipLog: String, diary: String) -> String {
    let skips = skipLog.split(separator: "\n", omittingEmptySubsequences: true)
      .filter { !isDiaryLine(String($0)) }
    let notes = diary.split(separator: "\n", omittingEmptySubsequences: true)
    let all = skips + notes
    return all.isEmpty ? "" : all.joined(separator: "\n") + "\n"
  }

  /// What went wrong, for a mark: the error's type name and case name, never its text, which
  /// can hold words of the episode or an address. A failure that the detector made out of a
  /// model error carries the names of that error (`AdModelFailure.classify`).
  public static func note(for error: Error) -> String {
    if let ours = error as? AdDetectorError {
      switch ours {
      case .tooLong: return "a part was too long for the model"
      case .refused: return "the model refused a part"
      case .unavailable(let reason): return "model unavailable: \(reason.reason)"
      case .failed(let text):
        guard let names = AdModelFailure.namesIn(text) else { return "the model failed" }
        return "the model failed: \(names.typeName) \(names.caseName)"
      }
    }
    let names = AdModelFailure.names(of: error)
    return "\(names.typeName) \(names.caseName)"
  }
}
