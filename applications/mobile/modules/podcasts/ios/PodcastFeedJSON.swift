// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
import Foundation
import PodcastFeed

/// A feed as plain JSON for the JavaScript side. Dates are milliseconds since 1970, addresses
/// are strings, and a value the feed does not have is left out (JavaScript reads it as null).
enum PodcastFeedJSON {
  static func object(_ feed: PodcastFeed) -> [String: Any] {
    var object: [String: Any] = [
      "title": feed.title,
      "description": feed.description,
      "categories": feed.categories,
      "people": feed.people.map(person),
      "funding": feed.funding.map { ["url": $0.url.absoluteString, "label": $0.label] },
      "episodes": feed.episodes.map(episode),
    ]
    if let author = feed.author { object["author"] = author }
    if let imageURL = feed.imageURL { object["imageUrl"] = imageURL.absoluteString }
    if let link = feed.link { object["link"] = link.absoluteString }
    if let language = feed.language { object["language"] = language }
    return object
  }

  static func episode(_ episode: FeedEpisode) -> [String: Any] {
    var object: [String: Any] = [
      "guid": episode.guid,
      "title": episode.title,
      "notes": episode.notes,
      "audioUrl": episode.audioURL.absoluteString,
      "audioType": episode.audioType,
    ]
    if let published = episode.published {
      object["publishedAt"] = (published.timeIntervalSince1970 * 1000).rounded()
    }
    if let seconds = episode.durationSeconds { object["durationSeconds"] = seconds }
    if let bytes = episode.audioBytes { object["audioBytes"] = Double(bytes) }
    if let imageURL = episode.imageURL { object["imageUrl"] = imageURL.absoluteString }
    if let season = episode.season { object["season"] = season }
    if let number = episode.number { object["number"] = number }
    if let chapters = episode.chaptersURL { object["chaptersUrl"] = chapters.absoluteString }
    object["people"] = episode.people.map(person)
    object["transcripts"] = episode.transcripts.map { transcript -> [String: Any] in
      var entry: [String: Any] = ["url": transcript.url.absoluteString, "type": transcript.type]
      if let language = transcript.language { entry["language"] = language }
      if let rel = transcript.rel { entry["rel"] = rel }
      return entry
    }
    return object
  }

  static func person(_ person: FeedPerson) -> [String: Any] {
    var entry: [String: Any] = ["name": person.name, "role": person.role, "group": person.group]
    if let imageURL = person.imageURL { entry["img"] = imageURL.absoluteString }
    if let link = person.link { entry["href"] = link.absoluteString }
    return entry
  }
}
