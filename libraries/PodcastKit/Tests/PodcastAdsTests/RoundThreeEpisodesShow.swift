import Foundation

@testable import PodcastAds
@testable import PodcastTranscripts

/// The made show of the whole-round test: three episodes of one show whose transcripts are
/// built from numbers. Every talk word is told apart by its episode ("e2t41"), so a run of five
/// words repeats only where a passage is said again on purpose. The passages are:
///  - `plug`: the hosts' standing plug (80 words, 40 s), with no ad words in it. It is said in
///    all three episodes, a little differently each time.
///  - `quiz`: a standing segment opener (60 words, 30 s) that the listener does not call an ad.
///  - `sponsor`: a sponsor read with ad words, found by the word rules in every episode. It is
///    too short (13 s) to be remembered or to count as a repeat.
///  - `favour`: four lines that a made meaning model reads as the hosts asking for something.
enum RoundShow {
  static let feed = "round-show.test/feed"
  static let show = "round"
  static let now = Date(timeIntervalSince1970: 1_800_000_000)
  static let detector = "local"
  /// Seconds a word lasts, and words in a line of talk.
  static let step = 0.5
  static let perLine = 10

  /// The Mac's settings text for the show, read with the app's table of feeds.
  static func tuning(default block: String = "{}", show keys: String = "") -> ShowTuning {
    let text = #"{"version": 1, "default": \#(block), "shows": [{"feed": "\#(feed)"\#(keys)}]}"#
    return ShowTuning(text: text, showOf: MacFiles.table([FeedKey.key(feed): show]))
  }

  /// The settings that switch every new finder off, and the joints too.
  static let everythingOff = tuning(
    default: #"{"finders": {"own-sound": "off", "repeat-sound": "off", "repeat-words": "off", "meaning": "off"}, "joints": false}"#)

  struct Episode {
    var id: String
    var transcript: Transcript
    var places: [String: (start: Double, end: Double)] = [:]

    func start(_ name: String) -> Double { places[name]?.start ?? -1 }
    func end(_ name: String) -> Double { places[name]?.end ?? -1 }
  }

  /// A passage of `words` numbered words, ten to a line, with the words at `changed` read
  /// differently ("e2x7"): a host never reads a plug the same way twice.
  static func passage(_ tag: String, words: Int, id: String, changed: [Int] = []) -> [String] {
    var lines: [String] = []
    for from in stride(from: 0, to: words, by: perLine) {
      lines.append(
        (from..<min(from + perLine, words)).map { changed.contains($0) ? "\(id)x\($0)" : "\(tag)\($0)" }
          .joined(separator: " "))
    }
    return lines
  }

  static let sponsor = [
    "This episode is brought to you by Casper.",
    "Use code NAP for twenty percent off at casper.com slash nap.",
    "Thanks to Casper for supporting the show.",
  ]

  /// Lines a made meaning model calls the hosts asking for a favour (see `Made.table`).
  static let favour = [
    "Come and say hello on our forum, we read every message.",
    "Tell a friend about us, that is how we grow.",
    "Come and say hello on our forum, we read every message.",
    "Tell a friend about us, that is how we grow.",
  ]

  /// An episode made of `parts`: talk of `count` lines, or a named passage's lines.
  enum Part {
    case talk(lines: Int)
    case named(String, [String])
  }

  static func episode(_ id: String, _ parts: [Part]) -> Episode {
    var made = Episode(
      id: id,
      transcript: Transcript(
        identity: TranscriptIdentity(
          locale: "en-US", recogniser: "Fake", recogniserVersion: "1", osVersion: "26.0", sha256: id),
        duration: 0, lines: [], words: []))
    var lines: [TranscriptLine] = []
    var words: [TranscriptWord] = []
    var clock = 0.0
    var talk = 0
    func add(_ text: String) {
      let pieces = text.split(separator: " ").map(String.init)
      let from = clock
      for piece in pieces {
        words.append(TranscriptWord(text: piece, start: clock, end: clock + step))
        clock += step
      }
      lines.append(TranscriptLine(start: from, end: clock, text: text))
    }
    for part in parts {
      switch part {
      case .talk(let count):
        for _ in 0..<count {
          add((0..<perLine).map { "\(id)t\(talk * perLine + $0)" }.joined(separator: " "))
          talk += 1
        }
      case .named(let name, let texts):
        let from = clock
        texts.forEach(add)
        made.places[name] = (from, clock)
      }
    }
    made.transcript.duration = clock
    made.transcript.lines = lines
    made.transcript.words = words
    return made
  }

  static let one = episode(
    "e1",
    [
      .talk(lines: 30), .named("quiz", passage("quiz", words: 60, id: "e1")), .talk(lines: 20),
      .named("plug", passage("plug", words: 80, id: "e1")), .talk(lines: 20),
      .named("sponsor", sponsor), .talk(lines: 30),
    ])
  static let two = episode(
    "e2",
    [
      .talk(lines: 20), .named("plug", passage("plug", words: 80, id: "e2", changed: [7, 33])),
      .talk(lines: 30), .named("sponsor", sponsor), .talk(lines: 14), .named("favour", favour),
      .talk(lines: 6), .named("quiz", passage("quiz", words: 60, id: "e2", changed: [3])),
      .talk(lines: 30),
    ])
  static let three = episode(
    "e3",
    [
      .talk(lines: 40), .named("quiz", passage("quiz", words: 60, id: "e3", changed: [20])),
      .talk(lines: 30), .named("plug", passage("plug", words: 80, id: "e3", changed: [12, 55])),
      .talk(lines: 20), .named("sponsor", sponsor), .talk(lines: 25),
    ])
}
