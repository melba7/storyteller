import Foundation
import LofiAudio

/// Timings and levels for the atmosphere.
public struct AtmosphereConfig: Sendable, Hashable {
    /// Where a sound at "full" sits, in dB under a voice at ``voiceLoudnessLUFS``.
    /// The music's bed is 16 dB under; the atmosphere sits well below it.
    public var bedLevelDB: Double = -28
    public var voiceLoudnessLUFS: Double = -18
    /// A new place or new sounds fade in this long, the old ones out.
    public var sceneFade: TimeInterval = 6
    /// The same sound getting louder or softer.
    public var levelFade: TimeInterval = 4
    /// After a seek.
    public var quickFade: TimeInterval = 2.5
    /// Narrator starts, stops.
    public var fadeIn: TimeInterval = 3
    public var fadeOut: TimeInterval = 1
    /// When a chapter starts and its own scene is not known yet, the last chapter's sounds
    /// drop this far until the new chapter says where it is.
    public var chapterDipDB: Double = -8
    /// Least time between two changes of scene, unless the listener seeks.
    public var minDwell: TimeInterval = 20
    /// A scene the scorer was less sure of than this never replaces the one playing.
    public var minConfidence: Double = 0.35
    /// A scene this many sentences old with no newer one (a track scored only part way)
    /// fades to silence.
    public var maxLagSentences: Int = 80
    public var stopEngineAfterPause: TimeInterval = 120
    public var gainUpdateRate: Double = 30
    /// How long the music takes to step aside for a crowd, and to come back.
    public var musicYieldFade: TimeInterval = 4
    /// Routes where the atmosphere stays off (like the music's "off in the car").
    public var mutedRoutes: Set<OutputRoute> = []

    /// The level slider's range, in dB under the voice.
    public static let levelRange: ClosedRange<Double> = -40 ... -16

    public init() {}
}

/// What the atmosphere should sound like at the sentence being narrated.
public struct AtmosphereTarget: Sendable, Hashable {
    public var scene: StoryScene
    /// The scene came from an earlier chapter and the new one has not said where it is.
    public var dipped: Bool
    /// Global index of the entry that set the scene, if any.
    public var entryIndex: Int?
}

/// Decides, from the book's atmosphere track and the narrator's position, which scene
/// should be playing. Pure logic: no audio, no timers; the player asks it.
///
/// Spoiler safety: it reads only the newest entries at or before the sentence being
/// narrated, never one after it.
public struct AtmosphereDirector: Sendable {
    public var config: AtmosphereConfig
    public private(set) var track: AtmosphereTrack?
    /// The scene playing now (what the player last applied).
    public private(set) var applied = AtmosphereTarget(scene: .silent, dipped: false, entryIndex: nil)
    public private(set) var appliedAt: TimeInterval = -.infinity

    public init(config: AtmosphereConfig = AtmosphereConfig()) {
        self.config = config
    }

    public mutating func setTrack(_ track: AtmosphereTrack?) {
        self.track = track
        applied = AtmosphereTarget(scene: .silent, dipped: false, entryIndex: nil)
        appliedAt = -.infinity
    }

    /// The scene the track gives for `globalIndex`: the newest confident entry at or
    /// before it, within ``AtmosphereConfig/maxLagSentences``.
    public func target(at globalIndex: Int) -> AtmosphereTarget {
        guard let track else { return AtmosphereTarget(scene: .silent, dipped: false, entryIndex: nil) }
        let earlier = track.entries(before: globalIndex + 1)
        var found: AtmosphereTrack.Entry?
        for entry in earlier.reversed() {
            if globalIndex - entry.globalIndex > config.maxLagSentences { break }
            if entry.scene.confidence >= config.minConfidence {
                found = entry
                break
            }
        }
        guard let entry = found else { return AtmosphereTarget(scene: .silent, dipped: false, entryIndex: nil) }
        let chapterStart = track.chapterStart(atOrBefore: globalIndex)
        let dipped = chapterStart.map { entry.globalIndex < $0 } ?? false
        return AtmosphereTarget(scene: entry.scene, dipped: dipped, entryIndex: entry.globalIndex)
    }

    public enum Step: Sendable, Hashable {
        /// Nothing to do.
        case hold
        /// Change to this scene, fading over this long.
        case change(AtmosphereTarget, fade: TimeInterval)
        /// Only the chapter dip changed.
        case dip(Bool)
        /// A change is due but the dwell is not over; ask again at this time.
        case wait(until: TimeInterval)
    }

    /// What to do now that `globalIndex` is being narrated. `seek` waives the dwell.
    public mutating func step(at globalIndex: Int, now: TimeInterval, seek: Bool = false) -> Step {
        let next = target(at: globalIndex)
        if next.scene.soundsLike(applied.scene) {
            guard next.dipped != applied.dipped else { return .hold }
            applied.dipped = next.dipped
            applied.entryIndex = next.entryIndex
            return .dip(next.dipped)
        }
        if !seek, now - appliedAt < config.minDwell {
            return .wait(until: appliedAt + config.minDwell)
        }
        let placeChanged = next.scene.placeID != applied.scene.placeID || next.scene.sounds != applied.scene.sounds
        let fade = seek ? config.quickFade : (placeChanged ? config.sceneFade : config.levelFade)
        applied = next
        appliedAt = now
        return .change(next, fade: fade)
    }

    /// Forgets the scene playing (book closed), so the next step starts fresh.
    public mutating func reset() {
        applied = AtmosphereTarget(scene: .silent, dipped: false, entryIndex: nil)
        appliedAt = -.infinity
    }
}
