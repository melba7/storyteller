// LOFI-FORK: the opening words of each show, learned from its episodes (see FORK.md).
//
// One small file (`show-openings.json`), one entry per show and at most 200 shows. A show's
// opening is learned when two of its checked episodes share a run of 8 to 40 words in their first
// five minutes, outside every ad. To compare an episode with the next one, the entry also keeps
// that episode's words (at most 300) until an opening is learned or a newer episode has replaced
// them. An opening that three newer episodes in a row do not have is replaced by what the last
// two share, or dropped. `ShowOpening` finds it in a head and uses it. Foundation only.
import Foundation
import PodcastTranscripts

public struct ShowOpenings: Codable, Sendable, Equatable {
  public static let currentVersion = 1
  public static let fileName = "show-openings.json"

  /// How many shows are kept: the one recorded longest ago goes first.
  public static let mostShows = 200
  /// An episode with fewer words than this outside ads in its first five minutes says nothing.
  public static let fewestHeard = 30
  /// An opening that this many newer episodes in a row do not have is dropped.
  public static let missesToDrop = 3

  /// One show's entry.
  public struct Show: Codable, Sendable, Equatable {
    public var id: String
    /// The opening's words, normalised and one space apart. Nil until two episodes shared a run.
    public var opening: String?
    /// How many newer episodes in a row did not have the opening.
    public var misses: Int
    /// The episode that was learned from last: one episode is never learned from twice.
    public var episode: String
    /// The words of that episode outside ads (one string for each stretch between ads), kept
    /// only while the show has no opening or the opening was just missed.
    public var heard: [String]
  }

  public var version: Int
  /// The shows in the order they were last learned from, the oldest first.
  public var shows: [Show]

  public init() {
    version = Self.currentVersion
    shows = []
  }

  /// The words the show opens with, when they are known.
  public func opening(for show: String) -> String? {
    shows.first(where: { $0.id == show })?.opening
  }

  /// Learns from a checked episode: its final ads file and transcript. Nothing changes for a
  /// partial file, an episode that was learned from already, or one with too few words.
  public mutating func learn(
    from file: AdsFile, transcript: Transcript, show id: String, episode: String
  ) {
    guard file.coveredUntil == nil else { return }
    let early = ShowOpening.early(transcript.words, outside: file.ads)
    guard early.reduce(0, { $0 + $1.count }) >= Self.fewestHeard else { return }
    var show =
      shows.first(where: { $0.id == id })
      ?? Show(id: id, opening: nil, misses: 0, episode: "", heard: [])
    guard show.episode != episode else { return }
    show.episode = episode

    if let opening = show.opening {
      if ShowOpening.find(opening, in: transcript.words) != nil {
        show.misses = 0
        show.heard = []
      } else {
        show.misses += 1
        if show.misses >= Self.missesToDrop {
          // Replaced below by what this episode and the one before share, when they share a run.
          show.opening = nil
          show.misses = 0
        } else {
          show.heard = Self.kept(early)
        }
      }
    }
    if show.opening == nil {
      if let run = ShowOpening.sharedRun(show.heard.map(Self.words), early) {
        show.opening = run.joined(separator: " ")
        show.heard = []
      } else {
        show.heard = Self.kept(early)
      }
    }

    shows.removeAll { $0.id == id }
    shows.append(show)
    if shows.count > Self.mostShows { shows.removeFirst(shows.count - Self.mostShows) }
  }

  private static func kept(_ segments: [[String]]) -> [String] {
    segments.map { $0.joined(separator: " ") }
  }

  private static func words(_ text: String) -> [String] {
    text.split(separator: " ").map(String.init)
  }

  // MARK: The file

  /// What was saved at `url`, or nothing when there is no file, it cannot be read or it is of
  /// another version.
  public static func load(from url: URL) -> ShowOpenings {
    guard let data = try? Data(contentsOf: url),
      let saved = try? JSONDecoder().decode(ShowOpenings.self, from: data),
      saved.version == currentVersion
    else { return ShowOpenings() }
    return saved
  }

  /// Saves everything at `url`, making its folder first.
  public func save(to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(self).write(to: url, options: .atomic)
  }
}
