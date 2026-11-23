// LOFI-FORK: `podcast-teach score --dump FILE`: what the last row found for each scored episode,
// next to the marks, so other tools can work out the bar again (see FORK.md). Foundation only. It
// never holds transcript text.
import Foundation

enum AdScoreDump {
  private struct Stretch: Encodable {
    var start: Double
    var end: Double
    var sort: String
  }

  private struct Found: Encodable {
    var start: Double
    var end: Double
    var kind: AdKind
    var confidence: AdConfidence
    var source: String?
  }

  private struct Entry: Encodable {
    var id: String
    var feed: String
    var show: String
    var duration: Double
    var found: [Found]
    var truth: [Stretch]
    var maybe: [Stretch]
  }

  /// Writes one object for each episode to `url`. Throws when the file cannot be written.
  static func write(
    _ episodes: [TeachingEpisode], found: (TeachingEpisode) -> [FoundAd], to url: URL
  ) throws {
    func stretches(_ list: [TeachingTruth]) -> [Stretch] {
      list.map { Stretch(start: $0.start, end: $0.end, sort: $0.sort) }
    }
    let entries = episodes.map { episode in
      Entry(
        id: episode.id, feed: episode.feed, show: episode.show,
        duration: episode.transcript.duration,
        found: found(episode).map {
          Found(
            start: $0.start, end: $0.end, kind: $0.kind, confidence: $0.confidence,
            source: $0.source)
        },
        truth: stretches(episode.truth), maybe: stretches(episode.maybe))
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    try encoder.encode(entries).write(to: url, options: .atomic)
  }
}
