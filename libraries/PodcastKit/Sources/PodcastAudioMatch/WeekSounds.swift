// LOFI-FORK: this week's ad sounds, for the scorecard row that shows what sending them to the phone
// every hour would do (see FORK.md and SoundBank.swift). Foundation only.
//
// A test episode may learn only from the ads of episodes published at least a day and at most a week
// before it: that is what the phone would hold when the Mac sends the last week's sounds every hour
// (a sound from the same day, or from after the episode, would not be there yet). The ads of those
// episodes are in the sound bank (`sound-bank/<id>.json`), which holds each episode's marked stretches
// as frames; the library for one test episode is made from the banks of its window, and the
// episode's audio is then searched with it.
import Foundation

/// An episode of `episodes.json`, with the time it was published, in seconds.
public struct WeekEpisode: Sendable, Equatable {
  public var id: String
  public var published: Double?

  public init(id: String, published: Double?) {
    self.id = id
    self.published = published
  }
}

public enum WeekSounds {
  /// An episode may use the sounds of episodes published this long before it or earlier...
  public static let atLeast = 86_400.0
  /// ...and no earlier than this.
  public static let atMost = 7 * 86_400.0

  /// The ids of the episodes `target` may learn from, oldest first (a tie goes by id): those published
  /// from `atLeast` to `atMost` seconds before it. An episode with no date is in nobody's window, and
  /// learns from nothing.
  public static func window(for target: WeekEpisode, among episodes: [WeekEpisode]) -> [String] {
    guard let now = target.published, now.isFinite else { return [] }
    return episodes.compactMap { other -> (id: String, published: Double)? in
      guard let published = other.published, published.isFinite else { return nil }
      let before = now - published
      return before >= atLeast && before <= atMost ? (other.id, published) : nil
    }
    .sorted { ($0.published, $0.id) < ($1.published, $1.id) }.map(\.id)
  }

  /// The episodes of `episodes.json` in the teaching folder, with their dates. A row that has no id,
  /// and a missing or damaged file, give nothing; a missing or odd date is nil.
  public static func episodes(in folder: URL) -> [WeekEpisode] {
    guard let data = try? Data(contentsOf: folder.appendingPathComponent("episodes.json")),
      let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let list = root["episodes"] as? [Any]
    else { return [] }
    return list.compactMap { item in
      guard let row = item as? [String: Any], let id = row["id"] as? String, !id.isEmpty else { return nil }
      return WeekEpisode(id: id, published: (row["published"] as? NSNumber)?.doubleValue)
    }
  }

  /// The sounds of the ads in the banks of `target`'s window. An episode with no bank file adds
  /// nothing.
  public static func library(
    for target: WeekEpisode, among episodes: [WeekEpisode], in folder: URL
  ) -> AdSoundLibrary {
    var builder = AdSoundBuilder()
    for id in window(for: target, among: episodes) {
      if let stretches = SoundBank.load(episode: id, in: folder) {
        builder.add(episode: id, stretches: stretches)
      }
    }
    return builder.library(maxBytes: AdSoundLibrary.maxBytes)
  }

  /// Where the week's sounds play in the audio file of `target`, the hits worth skipping (as the
  /// phone's own sounds are: `OwnAdSounds.trusted`), in order of time.
  public static func spans(
    in audio: URL, for target: WeekEpisode, among episodes: [WeekEpisode], folder: URL
  ) -> [SoundSpan] {
    let library = library(for: target, among: episodes, in: folder)
    guard !library.sounds.isEmpty else { return [] }
    return OwnAdSounds.trusted(AdSoundFile.hits(in: audio, library: library)).compactMap { hit in
      guard hit.start.isFinite, hit.end.isFinite, hit.end > hit.start else { return nil }
      return SoundSpan(start: hit.start, end: hit.end, sort: hit.sort)
    }
  }
}
