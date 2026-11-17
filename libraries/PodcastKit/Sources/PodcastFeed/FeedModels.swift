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
  /// The channel's `podcast:person` tags: at most `FeedLimits.people`.
  public var people: [FeedPerson]
  /// The channel's `podcast:funding` tags: at most `FeedLimits.funding`.
  public var funding: [FeedFunding]
  public var episodes: [FeedEpisode]

  public init(
    title: String, author: String? = nil, description: String = "", imageURL: URL? = nil,
    link: URL? = nil, language: String? = nil, categories: [String] = [],
    people: [FeedPerson] = [], funding: [FeedFunding] = [], episodes: [FeedEpisode] = []
  ) {
    self.title = title
    self.author = author
    self.description = description
    self.imageURL = imageURL
    self.link = link
    self.language = language
    self.categories = categories
    self.people = people
    self.funding = funding
    self.episodes = episodes
  }
}

/// How many `podcast:person` and `podcast:funding` tags are kept.
public enum FeedLimits {
  public static let people = 20
  public static let funding = 5
}

/// A `podcast:person` tag (Podcasting 2.0): someone who made the show or an episode.
public struct FeedPerson: Sendable, Equatable {
  public var name: String
  /// Lower case; "host" when the feed names none.
  public var role: String
  /// Lower case; "cast" when the feed names none.
  public var group: String
  /// A picture, only when it is an http(s) address.
  public var imageURL: URL?
  /// A page about the person, only when it is an http(s) address.
  public var link: URL?

  public init(
    name: String, role: String = "host", group: String = "cast", imageURL: URL? = nil,
    link: URL? = nil
  ) {
    self.name = name
    self.role = role
    self.group = group
    self.imageURL = imageURL
    self.link = link
  }
}

/// A `podcast:funding` tag (Podcasting 2.0): where to support the show.
public struct FeedFunding: Sendable, Equatable {
  public var url: URL
  /// The tag's text; empty when the feed has none.
  public var label: String

  public init(url: URL, label: String = "") {
    self.url = url
    self.label = label
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
  /// The `podcast:chapters` JSON file's address (Podcasting 2.0), when the feed has one.
  public var chaptersURL: URL?
  /// Every `podcast:person` tag of the episode: at most `FeedLimits.people`.
  public var people: [FeedPerson]

  public init(
    guid: String, title: String, published: Date? = nil, durationSeconds: Double? = nil,
    notes: String = "", audioURL: URL, audioType: String, audioBytes: Int64? = nil,
    imageURL: URL? = nil, season: Int? = nil, number: Int? = nil,
    transcripts: [FeedTranscript] = [], chaptersURL: URL? = nil, people: [FeedPerson] = []
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
    self.chaptersURL = chaptersURL
    self.people = people
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
