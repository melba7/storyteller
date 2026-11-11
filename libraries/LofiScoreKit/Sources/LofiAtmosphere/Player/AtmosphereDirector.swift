import Foundation
import LofiAudioCore

/// Timings and levels for the atmosphere.
public struct AtmosphereConfig: Sendable, Hashable {
    /// Where a sound at "full" sits, in dB under a voice at ``voiceLoudnessLUFS``.
    /// 10 under is a scene that can be heard while the narrator is speaking; at 16 under it
    /// was only there in the gaps (see ``levelRange`` for how far the slider goes).
    public var bedLevelDB: Double = -10
    /// The most a quiet recording is turned up to reach its level, as a linear gain
    /// (6 is 15.5 dB). A recording was only ever turned down before, so a quiet one (a
    /// running tap at -35 LUFS) stayed far under the level the slider asked for.
    public var maxGain: Double = 6
    public var voiceLoudnessLUFS: Double = -18
    /// How much is going on, from 0 (only the scene's main sound, the rest cut) to 1 (every
    /// sound the scene has, the quieter ones at their full level, the biggest lifts in the
    /// gaps between sentences). It is a dial next to the volume: turn it down for a calmer
    /// scene without turning the whole atmosphere down.
    public var intensity: Double = 0.75
    /// At intensity 0 the sounds behind the scene's main one sit this far lower.
    public var secondaryCutDB: Double = 6
    /// In a gap in the narration longer than ``gapLiftDelay`` (a paragraph break, a chapter
    /// end, the narrator drawing breath) the atmosphere comes forward by up to this much
    /// (times the intensity), rising over ``gapLiftRise`` and settling back over
    /// ``gapLiftFall`` when the next sentence starts. Ordinary gaps between sentences are
    /// shorter than the delay, so the bed does not pump.
    public var gapLiftDB: Double = 4
    public var gapLiftDelay: TimeInterval = 0.7
    public var gapLiftRise: TimeInterval = 0.6
    public var gapLiftFall: TimeInterval = 0.25
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
    /// A swell or hush (``StoryScene/Moment``): the narrator pauses this long after the
    /// sentence, while the new sound rises (by ``swellBoostDB``, over ``swellRise``) or the
    /// old one is cut, then the sound settles under the voice over ``swellRelease``.
    public var holdSeconds: TimeInterval = 0.8
    public var swellBoostDB: Double = 8
    public var swellRise: TimeInterval = 0.5
    public var swellRelease: TimeInterval = 3
    /// Pauses are rare: at least this long apart, and never this soon after the narrator
    /// starts or the listener seeks.
    public var minTimeBetweenHolds: TimeInterval = 120
    public var noHoldAfterStart: TimeInterval = 10
    /// One-off sounds (``AtmosphereTrack/Cue``), when turned on: this far above a sound at
    /// "full" (still well under the voice), at least this far apart, never this soon after
    /// the narrator starts or the listener seeks, and at most this far into their sentence.
    public var oneShotBoostDB: Double = 10
    public var minTimeBetweenOneShots: TimeInterval = 30
    public var noOneShotAfterStart: TimeInterval = 3
    public var maxOneShotDelay: TimeInterval = 8
    /// A one-off sound still playing when the listener jumps is faded out this fast.
    public var oneShotCut: TimeInterval = 0.3
    /// Scene transitions (``SceneTransition``): when the track does not say how the story
    /// moved from one place to the next, infer a plain one (a door between indoors and
    /// out, a vehicle boarded) from the two scenes.
    public var inferTransitions = true
    /// A sound fully muffled (behind a shut door, under water) is also this much quieter.
    public var muffleCutDB: Double = 9
    /// A transition's one-off sounds (the door, the engine) skip the usual spacing between
    /// one-off sounds, but never play this soon after the narrator starts or the listener seeks.
    public var noTransitionSoundAfterStart: TimeInterval = 1.5
    /// A scene this many sentences old with no newer one (a track scored only part way)
    /// fades to silence.
    public var maxLagSentences: Int = 80
    public var stopEngineAfterPause: TimeInterval = 120
    public var gainUpdateRate: Double = 30
    /// How long the music takes to step aside for a crowd, and to come back.
    public var musicYieldFade: TimeInterval = 4
    /// Routes where the atmosphere stays off (like the music's "off in the car").
    public var mutedRoutes: Set<OutputRoute> = []

    /// The level slider's range, in dB under the voice. The default (10 under) is a
    /// scene that is heard under a narrator on a phone's speaker; 24 under could not be
    /// heard at all, and 16 under only between sentences. The top (level with the voice)
    /// is for a listener who wants the scene as present as the voice; sounds made of voices still sit a further 3 to 4 dB down with the speech
    /// band filtered.
    public static let levelRange: ClosedRange<Double> = -40 ... 0
    public static let intensityRange: ClosedRange<Double> = 0 ... 1

    /// How many of a scene's sounds play at `intensity`: 1 at 0, all ``StoryScene/maxLayers`` at 1.
    public static func layersKept(intensity: Double) -> Int {
        let clamped = min(1, max(0, intensity.isFinite ? intensity : 0))
        return max(1, min(StoryScene.maxLayers, Int((1 + clamped * Double(StoryScene.maxLayers - 1)).rounded())))
    }

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

    /// What to do now that `globalIndex` is being narrated. `seek` waives the dwell, and so
    /// does a swell or hush that starts at this sentence.
    public mutating func step(at globalIndex: Int, now: TimeInterval, seek: Bool = false) -> Step {
        let next = target(at: globalIndex)
        if next.scene.soundsLike(applied.scene) {
            guard next.dipped != applied.dipped else { return .hold }
            applied.dipped = next.dipped
            applied.entryIndex = next.entryIndex
            return .dip(next.dipped)
        }
        // A swell, hush or transition starting at this very sentence does not wait: it is
        // the story's own change of sound, and belongs right after this sentence.
        let isMoment = (next.scene.moment != nil || next.scene.transition != nil) && next.entryIndex == globalIndex
        if !seek, !isMoment, now - appliedAt < config.minDwell {
            return .wait(until: appliedAt + config.minDwell)
        }
        let placeChanged = next.scene.placeID != applied.scene.placeID
            || Set(next.scene.layers.map(\.key)) != Set(applied.scene.layers.map(\.key))
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
