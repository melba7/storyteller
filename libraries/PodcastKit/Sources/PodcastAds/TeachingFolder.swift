// LOFI-FORK: reads a Mac teaching folder (episodes, transcripts and the ads Claude marked) for the
// scorecard (see FORK.md). Foundation only.
import Foundation
import PodcastTranscripts

/// A stretch the teacher marked, in seconds.
public struct TeachingTruth: Sendable, Equatable {
  public var start: Double
  public var end: Double
  /// "sponsor", "network_promo", "host_ask" or "intro_credits".
  public var sort: String

  public init(start: Double, end: Double, sort: String) {
    self.start = start
    self.end = end
    self.sort = sort
  }
}

/// One marked episode of the teaching folder.
public struct TeachingEpisode: Sendable, Equatable {
  public var id: String
  public var feed: String
  public var show: String
  public var title: String
  public var transcript: Transcript
  /// The stretches marked with high or medium confidence.
  public var truth: [TeachingTruth]
  /// The stretches marked with low confidence: they count neither as ad nor as show.
  public var maybe: [TeachingTruth]
  /// Whether the small model was never trained on this episode.
  public var onShelf: Bool
  /// Whether the episode is in the sealed exam (`exam.json`): it is left out of every run unless
  /// the run asks for the exam.
  public var onExam: Bool
  /// The episode's length in `episodes.json`, when it has one above zero.
  public var seconds: Double?

  /// The episode's length as the end-of-episode feature of the word model sees it, by the one
  /// rule the Mac and the phone share: `seconds` when it is a number above zero, otherwise the
  /// start of the last line.
  public var episodeLength: Double {
    if let seconds, seconds.isFinite, seconds > 0 { return seconds }
    return transcript.lines.last?.start ?? 0
  }

  public init(
    id: String, feed: String, show: String, title: String, transcript: Transcript,
    truth: [TeachingTruth], maybe: [TeachingTruth], onShelf: Bool, seconds: Double? = nil,
    onExam: Bool = false
  ) {
    self.seconds = seconds
    self.id = id
    self.feed = feed
    self.show = show
    self.title = title
    self.transcript = transcript
    self.truth = truth
    self.maybe = maybe
    self.onShelf = onShelf
    self.onExam = onExam
  }
}

/// Why the teaching folder cannot be used at all.
public struct TeachingFolderError: Error, LocalizedError, Equatable {
  public var message: String
  public var errorDescription: String? { message }
}

/// Reads one value of a list and keeps nil when it is of the wrong shape, so one bad entry does
/// not fail the whole list.
struct Lossy<Value: Decodable>: Decodable {
  var value: Value?
  init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

/// A segment of a label file. Any field of the wrong type is nil.
struct LabelSegment: Decodable {
  var sort: String?
  var start: Double?
  var end: Double?
  var confidence: String?

  private enum Keys: String, CodingKey { case sort, start, end, confidence }

  init(from decoder: Decoder) throws {
    let box = try decoder.container(keyedBy: Keys.self)
    sort = try? box.decode(String.self, forKey: .sort)
    start = try? box.decode(Double.self, forKey: .start)
    end = try? box.decode(Double.self, forKey: .end)
    confidence = try? box.decode(String.self, forKey: .confidence)
  }
}

struct LabelFile: Decodable { var segments: [Lossy<LabelSegment>] }

public enum TeachingFolder {
  /// How long the last line of a text file lasts when the episode's length is not known.
  static let lastLineSeconds = 5.0

  /// A transcript from the text file's lines (`[H:MM:SS.t] text`). A line ends where the next
  /// one starts; the last one ends at `duration`, or 5 seconds after its start when that is
  /// unknown or earlier. Each line's words are spread evenly over the line, because the text
  /// file has no word times. Lines that do not match, or have no text, are skipped.
  public static func transcript(fromText text: String, duration: Double?) -> Transcript {
    let pattern = try? NSRegularExpression(pattern: #"^\[(\d+):(\d{2}):(\d{2}(?:\.\d+)?)\]\s*(.*)$"#)
    var found: [(start: Double, text: String)] = []
    for raw in text.split(whereSeparator: \.isNewline) {
      let line = raw.trimmingCharacters(in: .whitespaces)
      let range = NSRange(line.startIndex..., in: line)
      guard let match = pattern?.firstMatch(in: line, range: range) else { continue }
      func part(_ n: Int) -> String { Range(match.range(at: n), in: line).map { String(line[$0]) } ?? "" }
      guard let hours = Double(part(1)), let minutes = Double(part(2)), let seconds = Double(part(3))
      else { continue }
      let spoken = part(4).trimmingCharacters(in: .whitespaces)
      if !spoken.isEmpty { found.append((hours * 3600 + minutes * 60 + seconds, spoken)) }
    }
    var lines: [TranscriptLine] = []
    var words: [TranscriptWord] = []
    for (index, item) in found.enumerated() {
      let end: Double
      if index + 1 < found.count {
        end = found[index + 1].start
      } else if let duration, duration > item.start {
        end = duration
      } else {
        end = item.start + lastLineSeconds
      }
      lines.append(TranscriptLine(start: item.start, end: end, text: item.text))
      let pieces = item.text.split(whereSeparator: \.isWhitespace).map(String.init)
      let step = (end - item.start) / Double(max(pieces.count, 1))
      for (n, piece) in pieces.enumerated() {
        words.append(
          TranscriptWord(
            text: piece, start: item.start + Double(n) * step, end: item.start + Double(n + 1) * step))
      }
    }
    let identity = TranscriptIdentity(
      locale: "en-US", recogniser: "teaching-folder", recogniserVersion: "1", osVersion: "", sha256: "")
    return Transcript(
      identity: identity, duration: max(duration ?? 0, lines.last?.end ?? 0), lines: lines,
      words: words)
  }

  // MARK: Episodes

  /// The episodes that have both a transcript and a label, in the order of `episodes.json`.
  /// `notes` gets one plain sentence for each file that could not be read.
  public static func episodes(
    in folder: URL, labels: String = "labels", notes: inout [String]
  ) throws -> [TeachingEpisode] {
    guard let data = try? Data(contentsOf: folder.appendingPathComponent("episodes.json")) else {
      throw TeachingFolderError(message: "There is no episodes.json in \(folder.path).")
    }
    guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let entries = root["episodes"] as? [Any]
    else { throw TeachingFolderError(message: "episodes.json is not in the expected shape.") }
    let shelf = shelfIds(in: folder)
    let exam = try examIds(in: folder)
    var result: [TeachingEpisode] = []
    for case let entry as [String: Any] in entries {
      guard let id = entry["id"] as? String, !id.isEmpty, !id.contains("/"), !id.contains("..") else {
        notes.append("An entry of episodes.json has no usable id, so it was skipped.")
        continue
      }
      let textURL = folder.appendingPathComponent("transcripts/\(id).txt")
      let labelURL = folder.appendingPathComponent("\(labels)/\(id).json")
      let files = FileManager.default
      guard files.fileExists(atPath: textURL.path), files.fileExists(atPath: labelURL.path) else {
        continue
      }
      guard let text = try? String(contentsOf: textURL, encoding: .utf8) else {
        notes.append("The transcript of \(id) could not be read, so the episode was skipped.")
        continue
      }
      let seconds = (entry["seconds"] as? NSNumber).map(\.doubleValue).flatMap {
        $0.isFinite && $0 > 0 ? $0 : nil
      }
      let transcript = transcript(fromText: text, duration: seconds)
      guard !transcript.lines.isEmpty else {
        notes.append("The transcript of \(id) has no lines, so the episode was skipped.")
        continue
      }
      guard let labelData = try? Data(contentsOf: labelURL),
        let label = try? JSONDecoder().decode(LabelFile.self, from: labelData)
      else {
        notes.append("The label of \(id) could not be read, so the episode was skipped.")
        continue
      }
      var truth: [TeachingTruth] = []
      var maybe: [TeachingTruth] = []
      for case let segment? in label.segments.map(\.value) {
        guard let sort = segment.sort, AdKind(sort: sort) != nil, let start = segment.start,
          let end = segment.end, start.isFinite, end.isFinite, end > start
        else { continue }
        let stretch = TeachingTruth(start: start, end: end, sort: sort)
        switch segment.confidence {
        case "high", "medium": truth.append(stretch)
        case "low": maybe.append(stretch)
        default: continue
        }
      }
      result.append(
        TeachingEpisode(
          id: id, feed: (entry["feed"] as? String) ?? "", show: (entry["show"] as? String) ?? "",
          title: (entry["title"] as? String) ?? "", transcript: transcript, truth: truth,
          maybe: maybe, onShelf: shelf.contains(id), seconds: seconds,
          onExam: exam.contains(id)))
    }
    return result
  }

  private static func shelfIds(in folder: URL) -> Set<String> {
    guard let data = try? Data(contentsOf: folder.appendingPathComponent("shelf.json")),
      let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let ids = root["episodes"] as? [Any]
    else { return [] }
    return Set(ids.compactMap { $0 as? String })
  }

  /// The ids in `exam.json` (`{"episodes": ["id", ...]}`). No file means no exam. A file that
  /// cannot be read is a set-up problem, because ignoring it would let exam episodes into the
  /// scores that must not see them.
  static func examIds(in folder: URL) throws -> Set<String> {
    let url = folder.appendingPathComponent("exam.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    guard let data = try? Data(contentsOf: url),
      let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let ids = root["episodes"] as? [Any], ids.allSatisfy({ $0 is String })
    else { throw TeachingFolderError(message: "exam.json is not in the expected shape.") }
    return Set(ids.compactMap { $0 as? String })
  }

  // MARK: Library and habits

  /// The taught ads of `ad-library.json` as remembered ads whose show is the feed address.
  /// Empty when there is no such file.
  public static func library(in folder: URL, now: Date) -> KnownAds {
    guard let data = try? Data(contentsOf: folder.appendingPathComponent(AdLibraryFile.fileName))
    else { return KnownAds() }
    return MacFiles.library(data: data, now: now, showOf: MacFiles.feedAsShow)
  }

  /// The library to score with, and the name of the file it came from. When only the shelf
  /// episodes are scored, `ad-library-score.json` (the library built without the shelf's ads)
  /// is read if it exists; otherwise, and for `--all`, `ad-library.json`.
  public static func library(
    in folder: URL, now: Date, scoringShelf: Bool
  ) -> (known: KnownAds, file: String) {
    let score = "ad-library-score.json"
    if scoringShelf, let data = try? Data(contentsOf: folder.appendingPathComponent(score)) {
      return (MacFiles.library(data: data, now: now, showOf: MacFiles.feedAsShow), score)
    }
    return (library(in: folder, now: now), AdLibraryFile.fileName)
  }

  /// The habits of `habits.json` with the feed address as the show's id. Empty when there is no
  /// such file.
  public static func habits(in folder: URL) -> ShowHabits {
    guard let data = try? Data(contentsOf: folder.appendingPathComponent("habits.json")) else {
      return ShowHabits()
    }
    return MacFiles.habits(data: data, showOf: MacFiles.feedAsShow) ?? ShowHabits()
  }
}
