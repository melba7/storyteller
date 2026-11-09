import Foundation
import LofiDirector

/// Everything the player can be tuned with. The defaults follow the plan.
public struct ScoreConfig: Sendable, Hashable {
    /// The director's thresholds (smoothing, confirmation, dwell).
    public var director = DirectorConfig()

    /// Bed level and the lift in silences.
    public var ducking = DuckingSettings()

    /// Crossfade for a regular mood change. Long enough that the change is felt, not heard.
    public var gentleCrossfade: TimeInterval = 8
    /// Crossfade after a seek or a sudden jump (3 to 4 seconds).
    public var quickCrossfade: TimeInterval = 3.5
    /// Crossfade into the next track of the same mood when a track ends.
    public var rotationCrossfade: TimeInterval = 8

    /// Fade-in when the narrator starts playing.
    public var fadeIn: TimeInterval = 3
    /// Fade-out when the narrator pauses or the sleep timer fires.
    public var fadeOut: TimeInterval = 1
    /// Fade-out when the output route disappears (headphones pulled).
    public var routeLossFadeOut: TimeInterval = 0.1
    /// Stop the audio engine after this long paused, to save battery.
    public var stopEngineAfterPause: TimeInterval = 120

    /// On the first play after a book opens, wait up to this long for the first mood
    /// reading, so the music starts in the right mood instead of crossfading a moment later.
    public var startGrace: TimeInterval = 1.5

    /// Start mood crossfades on the outgoing track's next bar line when its tempo is known.
    public var alignToBars = true
    /// Never wait longer than this for a bar line, so a change lands close to the sentence
    /// that caused it.
    public var maxBarWait: TimeInterval = 2

    /// Gain updates per second while anything is fading. The plan asks for 30 or more.
    public var gainUpdateRate: Double = 60

    /// Overall music volume, 0...1, on top of the bed level.
    public var musicVolume: Double = 1

    /// Routes where the music stays off, such as `[.carPlay]` ("music off in the car").
    public var mutedRoutes: Set<OutputRoute> = []

    /// How many recently played tracks to avoid when choosing the next one.
    public var avoidRecentTracks = 3

    /// Give each book a theme per mood (``BookThemes``): when the music moves into a mood,
    /// it starts with that book's theme for it, so a mood the story comes back to sounds
    /// familiar. Tracks that follow in the same mood rotate as usual.
    public var bookThemes = true

    /// Seconds to wait before retrying when the engine will not start (during a call, say).
    public var engineRetryDelay: TimeInterval = 1
    public var engineRetryLimit = 5

    public init() {}

    func crossfadeDuration(for transition: MusicTransition) -> TimeInterval {
        switch transition {
        case .gentle: return gentleCrossfade
        case .quick: return quickCrossfade
        case .rotation: return rotationCrossfade
        }
    }
}

/// How the music moves to its next track.
public enum MusicTransition: String, Sendable, Hashable, Codable {
    case gentle
    case quick
    /// The next track of the same mood, because the current one is ending.
    case rotation

    init(_ transition: MoodDecision.Transition) {
        switch transition {
        case .gentle: self = .gentle
        case .quick: self = .quick
        }
    }
}
