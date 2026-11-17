import Foundation

/// A podcast as its RSS feed describes it: the show and its episodes in feed order.
public struct PodcastFeed: Sendable, Equatable {
  public var title: String
  public var author: String?
  /// Plain text: the feed's HTML is stripped.
  public var description: String
  public var imageURL: URL?
  public var link: URL?
  public var language: String?
  /// The `itunes:category` names: each top-level category once, in feed order, and each
  /// subcategory after them as "Top › Sub". Empty when the feed names none.
  public var categories: [String]
  public var episodes: [FeedEpisode]

  public init(
    title: String, author: String? = nil, description: String = "", imageURL: URL? = nil,
    link: URL? = nil, language: String? = nil, categories: [String] = [],
    episodes: [FeedEpisode] = []
  ) {
    self.title = title
    self.author = author
    self.description = description
    self.imageURL = imageURL
    self.link = link
    self.language = language
    self.categories = categories
    self.episodes = episodes
  }
}

/// A `podcast:transcript` tag (Podcasting 2.0): where an episode's transcript can be read.
public struct FeedTranscript: Sendable, Equatable {
  public var url: URL
  /// The MIME type as the feed wrote it, lower case ("application/json", "text/vtt").
  public var type: String
  public var language: String?
  /// "captions" and the like; nil when the feed has none.
  public var rel: String?

  public init(url: URL, type: String, language: String? = nil, rel: String? = nil) {
    self.url = url
    self.type = type
    self.language = language
    self.rel = rel
  }
}

/// One episode that has audio to play.
public struct FeedEpisode: Sendable, Equatable {
  /// The feed's own id for the episode. Falls back to the audio address when the feed has none.
  public var guid: String
  public var title: String
  public var published: Date?
  public var durationSeconds: Double?
  /// Plain text: the show notes with their HTML stripped.
  public var notes: String
  public var audioURL: URL
  public var audioType: String
  public var audioBytes: Int64?
  public var imageURL: URL?
  public var season: Int?
  public var number: Int?
  /// Every `podcast:transcript` tag, in feed order.
  public var transcripts: [FeedTranscript]

  public init(
    guid: String, title: String, published: Date? = nil, durationSeconds: Double? = nil,
    notes: String = "", audioURL: URL, audioType: String, audioBytes: Int64? = nil,
    imageURL: URL? = nil, season: Int? = nil, number: Int? = nil,
    transcripts: [FeedTranscript] = []
  ) {
    self.guid = guid
    self.title = title
    self.published = published
    self.durationSeconds = durationSeconds
    self.notes = notes
    self.audioURL = audioURL
    self.audioType = audioType
    self.audioBytes = audioBytes
    self.imageURL = imageURL
    self.season = season
    self.number = number
    self.transcripts = transcripts
  }
}

/// Why a feed could not be read. The message is shown to the listener as it is.
public enum FeedError: Error, LocalizedError, Equatable {
  case notAFeed

  public var errorDescription: String? {
    switch self {
    case .notAFeed: return "This link isn't a podcast feed."
    }
  }
}
