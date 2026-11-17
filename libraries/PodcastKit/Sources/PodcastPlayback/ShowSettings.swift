// LOFI-FORK: the podcast player's per-show rules (see FORK.md). Plain values, no AVFoundation.
import Foundation

/// The settings of one show that the player needs while the screen is locked, as the app's
/// JavaScript mirrors them into `show-settings.json`. The rest of a show's settings (what to
/// download, what to add to Up Next, archiving) only matter to the app while it runs.
public struct ShowPlaybackSettings: Sendable, Equatable, Codable {
  /// Seconds skipped at the start of every episode, 0 to 120.
  public var introSeconds: Double
  /// Seconds left unplayed at the end of every episode, 0 to 120.
  public var outroSeconds: Double
  /// The show's own speed, or nil to follow the player's speed.
  public var speed: Double?
  /// Nil follows the global switch.
  public var skipAds: Bool?
  public var skipPlugs: Bool?

  public init(
    introSeconds: Double = 0, outroSeconds: Double = 0, speed: Double? = nil,
    skipAds: Bool? = nil, skipPlugs: Bool? = nil
  ) {
    self.introSeconds = introSeconds
    self.outroSeconds = outroSeconds
    self.speed = speed
    self.skipAds = skipAds
    self.skipPlugs = skipPlugs
  }

  private enum Keys: String, CodingKey {
    case introSeconds, outroSeconds, speed, skipAds, skipPlugs
  }

  /// A missing key is the default, so a file from an older or newer app still reads.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: Keys.self)
    introSeconds = try c.decodeIfPresent(Double.self, forKey: .introSeconds) ?? 0
    outroSeconds = try c.decodeIfPresent(Double.self, forKey: .outroSeconds) ?? 0
    speed = try c.decodeIfPresent(Double.self, forKey: .speed)
    skipAds = try c.decodeIfPresent(Bool.self, forKey: .skipAds)
    skipPlugs = try c.decodeIfPresent(Bool.self, forKey: .skipPlugs)
  }
}

/// `show-settings.json`: the settings of each show by show id.
public enum ShowSettingsFile {
  /// The settings saved in `file`. A missing or unreadable file means no show has any.
  public static func load(from file: URL) -> [String: ShowPlaybackSettings] {
    guard let data = try? Data(contentsOf: file),
      let saved = try? JSONDecoder().decode([String: ShowPlaybackSettings].self, from: data)
    else { return [:] }
    return saved
  }

  /// The app writes the whole map every time, so a show whose settings were reset drops out.
  public static func decode(_ json: String) -> [String: ShowPlaybackSettings]? {
    try? JSONDecoder().decode([String: ShowPlaybackSettings].self, from: Data(json.utf8))
  }

  public static func save(_ settings: [String: ShowPlaybackSettings], to file: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(settings).write(to: file, options: .atomic)
  }
}

/// What a show's settings do to the start, the speed and the end of an episode.
public enum ShowRules {
  /// The most the intro or the outro may skip.
  public static let maxSkip = 120.0
  /// The outro never ends an episode sooner than this after the intro's end.
  public static let minimumBody = 5.0

  /// A skip length as a number of seconds from 0 to 120 (not a number is 0).
  public static func clampedSkip(_ seconds: Double) -> Double {
    guard seconds.isFinite else { return 0 }
    return min(maxSkip, max(0, seconds))
  }

  /// The speed to play at: the show's own when it has one, else the player's.
  public static func speed(show: Double?, player: Speed) -> Speed {
    guard let show, show.isFinite else { return player }
    return Speed.clamped(show)
  }

  /// Where an episode starts: where `ResumeRule` says, but not inside the intro. Resuming
  /// past the intro is left alone. An intro that would reach the end of the episode does
  /// nothing.
  public static func start(
    savedPosition: Double, duration: Double?, played: Bool, intro: Double
  ) -> Double {
    let resume = ResumeRule.start(savedPosition: savedPosition, duration: duration, played: played)
    let skip = clampedSkip(intro)
    guard skip > 0 else { return resume }
    if let duration, duration.isFinite, duration > 0, skip >= duration - ResumeRule.nearEnd {
      return resume
    }
    return max(resume, skip)
  }

  /// The place where the outro begins and the episode ends early, or nil when there is no
  /// outro to skip, the length is not known, or the outro would swallow the episode. It is
  /// kept at least `minimumBody` seconds after the intro's end.
  public static func outroStart(duration: Double?, outro: Double, intro: Double = 0) -> Double? {
    let skip = clampedSkip(outro)
    guard skip > 0, let duration, duration.isFinite, duration > 0 else { return nil }
    let end = max(duration - skip, clampedSkip(intro) + minimumBody)
    return end < duration ? end : nil
  }

  /// Whether the episode should end now: the outro's start is known and reached.
  public static func shouldEnd(position: Double, outroStart: Double?) -> Bool {
    guard let outroStart, position.isFinite else { return false }
    return position >= outroStart
  }
}
