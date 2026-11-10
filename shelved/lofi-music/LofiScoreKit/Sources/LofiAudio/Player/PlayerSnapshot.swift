import Foundation
import LofiDirector
import LofiScoreCore

/// Something the player did, for logs, the demo app and tests.
public enum PlayerEvent: Sendable, Hashable {
    case bookOpened(String)
    case bookClosed
    case moodChanged(MoodDecision)
    case trackStarted(trackID: String, mood: MoodBucket, deck: Deck, offset: TimeInterval)
    case crossfadeStarted(from: String?, to: String, transition: MusicTransition, duration: TimeInterval)
    case crossfadeReversed(toward: Deck)
    case crossfadeFinished(deck: Deck)
    /// The library had no playable track for `requested`, so a neighbouring mood was used.
    case fallback(requested: MoodBucket, used: MoodBucket)
    case engineStarted
    case engineStopped
    case engineRestarting(BackendRestartReason)
    case routeChanged(OutputRoute)
    case error(String)
}

/// The player's state at one moment, for the debug overlay and the demo app.
/// It only shows the present: nothing in it reveals moods ahead of the narration.
public struct PlayerSnapshot: Sendable {
    public struct DeckState: Sendable, Hashable {
        public var deck: Deck
        public var trackID: String?
        public var trackBucket: MoodBucket?
        public var mood: MoodBucket?
        /// The crossfader's share for this deck, 0...1.
        public var crossfadeGain: Double
        /// The track's loudness-matched bed gain.
        public var bedGain: Double
        public var position: TimeInterval?
        public var duration: TimeInterval
        public var isRunning: Bool
    }

    public var time: TimeInterval
    public var bookID: String?
    public var enabled: Bool
    public var narrating: Bool
    public var routeMuted: Bool
    public var engineRunning: Bool
    /// The mood the music is playing or crossfading to.
    public var musicMood: MoodBucket?
    public var activeDeck: Deck
    public var crossfadePosition: Double
    public var isCrossfading: Bool
    /// The play/pause fade, 0...1.
    public var transportGain: Double
    /// The lift above the bed level, in dB (0 while the narrator speaks).
    public var duckOffsetDB: Double
    /// A change waiting for a bar line or for the current crossfade.
    public var pendingMood: MoodBucket?
    public var decks: [DeckState]
    public var director: DirectorSnapshot
    public var recentDecisions: [MoodDecision]
    public var lastError: String?
}
