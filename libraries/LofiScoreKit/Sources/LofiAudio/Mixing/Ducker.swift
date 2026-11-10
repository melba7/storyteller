import Foundation

/// How loud the music sits under the narrator.
public struct DuckingSettings: Sendable, Hashable, Codable {
    /// Music level while the narrator speaks, in dB relative to the voice. The plan's default
    /// is about 12 dB under. This is the "music volume" slider.
    public var bedLevelDB: Double = -12

    /// How much the music rises in a silence longer than ``gapThreshold`` (a chapter break,
    /// a long pause in the reading). 0 turns the lift off.
    public var gapLiftDB: Double = 4

    /// How long the narrator must be silent before the music rises.
    public var gapThreshold: TimeInterval = 1.5

    /// How long the rise takes.
    public var liftTime: TimeInterval = 1.5

    /// How fast the music settles back when the narrator speaks again.
    public var settleTime: TimeInterval = 0.4

    /// The narration's loudness, assumed, in LUFS. Audiobook masters usually sit around
    /// -18 to -20 LUFS. Together with each track's measured loudness this sets the bed level.
    public var voiceLoudnessLUFS: Double = -18

    public init() {}

    /// Gain that puts a track of `trackLoudness` LUFS at the bed level, capped at unity.
    public func bedGain(forTrackLoudness trackLoudness: Double) -> Double {
        min(1, Gain.linear(fromDB: voiceLoudnessLUFS + bedLevelDB - trackLoudness))
    }
}

/// Keeps the music at its bed level while the narrator speaks and lifts it a few dB in long
/// silences. A silence is only noticed after the fact (no new sentence has started), so
/// nothing here looks ahead.
public struct Ducker: Sendable, Hashable {
    /// Extra level above the bed, in dB.
    public private(set) var lift = Ramp(value: 0)
    /// When the current sentence's audio is expected to end, if known.
    public private(set) var voiceUntil: TimeInterval?
    public private(set) var isLifted = false

    public init() {}

    public func offsetDB(at time: TimeInterval) -> Double {
        lift.value(at: time)
    }

    public func isRamping(at time: TimeInterval) -> Bool {
        lift.isRunning(at: time)
    }

    /// A sentence started. `duration` is how long its audio lasts in wall-clock seconds
    /// (clip length divided by the playback rate), when the host knows it.
    public mutating func sentenceStarted(at time: TimeInterval, duration: TimeInterval?, settings: DuckingSettings) {
        voiceUntil = duration.map { time + max(0, $0) }
        if isLifted || lift.target != 0 {
            lift.go(to: 0, over: settings.settleTime, at: time, shape: .linear)
            isLifted = false
        }
    }

    /// The current sentence's audio ended, for hosts that report ends instead of durations.
    public mutating func sentenceEnded(at time: TimeInterval) {
        voiceUntil = time
    }

    /// When the music may next rise, if a silence is under way.
    public func gapCheckTime(settings: DuckingSettings) -> TimeInterval? {
        guard !isLifted, settings.gapLiftDB > 0, let voiceUntil else { return nil }
        return voiceUntil + settings.gapThreshold
    }

    /// Lifts the music if the narrator has been silent long enough by `time`.
    public mutating func checkGap(at time: TimeInterval, settings: DuckingSettings) {
        guard let due = gapCheckTime(settings: settings), time >= due - 1e-9 else { return }
        lift.go(to: settings.gapLiftDB, over: settings.liftTime, at: time, shape: .linear)
        isLifted = true
    }

    /// Back to the bed at once, forgetting the current sentence (pause, seek, new book).
    public mutating func reset(at time: TimeInterval) {
        lift.jump(to: 0, at: time)
        isLifted = false
        voiceUntil = nil
    }
}
