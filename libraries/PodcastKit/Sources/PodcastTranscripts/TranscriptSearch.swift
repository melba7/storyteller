// LOFI-FORK: the podcast transcripts' search rules (see FORK.md). Foundation only.
import Foundation

/// Finds the words a listener typed in the lines of transcripts.
///
/// Text is compared lower case, with accents folded, punctuation dropped and spaces
/// collapsed. A line matches when it holds the query's words as a phrase. When no line of the
/// episode does, a line matches when it holds all of the query's words.
public enum TranscriptSearch {
  /// A query shorter than this (after normalising) finds nothing.
  public static let minimumLength = 3
  public static let hitsPerEpisode = 3
  public static let hitsInAll = 50

  /// One matching line, with the lines around it for context ("" at the ends).
  public struct Hit: Sendable, Equatable {
    public var start: Double
    public var text: String
    public var before: String
    public var after: String
  }

  public struct EpisodeHits: Sendable, Equatable {
    public var episodeId: String
    public var hits: [Hit]
  }

  /// Lower case, accents folded, apostrophes dropped, other punctuation as a space, spaces
  /// collapsed and trimmed.
  public static func normalise(_ text: String) -> String {
    let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
      .lowercased()
    var kept = ""
    for character in folded {
      if character == "'" || character == "\u{2019}" || character == "\u{2018}" { continue }
      kept.append(character.isLetter || character.isNumber ? character : " ")
    }
    return kept.split(separator: " ").joined(separator: " ")
  }

  /// The hits in one episode's lines, in the order spoken, at most `hitsPerEpisode`.
  public static func search(_ query: String, in lines: [TranscriptLine]) -> [Hit] {
    let normalised = normalise(query)
    guard normalised.count >= minimumLength else { return [] }
    let words = normalised.split(separator: " ").map(String.init)
    let tokens = lines.map { normalise($0.text).split(separator: " ").map(String.init) }

    var matching = tokens.indices.filter { containsPhrase(tokens[$0], words) }
    if matching.isEmpty {
      matching = tokens.indices.filter { index in words.allSatisfy { tokens[index].contains($0) } }
    }
    return matching.prefix(hitsPerEpisode).map { index in
      Hit(
        start: lines[index].start,
        text: lines[index].text,
        before: index > 0 ? lines[index - 1].text : "",
        after: index + 1 < lines.count ? lines[index + 1].text : "")
    }
  }

  /// The hits of each episode that has any, stopping once `hitsInAll` are found.
  public static func search(
    _ query: String, episodes: [(id: String, lines: [TranscriptLine])]
  ) -> [EpisodeHits] {
    var found: [EpisodeHits] = []
    var count = 0
    for episode in episodes {
      let room = hitsInAll - count
      if room <= 0 { break }
      let hits = Array(search(query, in: episode.lines).prefix(room))
      if hits.isEmpty { continue }
      found.append(EpisodeHits(episodeId: episode.id, hits: hits))
      count += hits.count
    }
    return found
  }

  private static func containsPhrase(_ line: [String], _ words: [String]) -> Bool {
    guard !words.isEmpty, line.count >= words.count else { return false }
    for start in 0...(line.count - words.count)
    where Array(line[start..<(start + words.count)]) == words {
      return true
    }
    return false
  }
}
