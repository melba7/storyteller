import Foundation
import LofiAudio
import LofiDirector
import LofiPlaceholders
import LofiScoreCore

/// Puts an offline run together: the narrator's voice where each sentence was spoken, the
/// rendered music underneath, at the levels the player assumes.
public enum OfflineMix {
    public struct Levels: Sendable, Hashable {
        /// The player sets the bed against a voice at this loudness (LUFS), so the voice is
        /// normalised to it before mixing.
        public var voiceLoudness: Double = -18
        /// The finished file is brought to this loudness (LUFS)...
        public var outputLoudness: Double = -16
        /// ...with peaks held under this level (dBFS) by a soft limiter.
        public var ceiling: Double = -1

        public init() {}
    }

    public struct Result: Sendable {
        public var audio: StereoBuffer
        /// Gain applied to the voice to bring it to ``Levels/voiceLoudness``, in dB.
        public var voiceGainDB: Double
        /// Loudness of the music alone as rendered, in LUFS.
        public var musicLoudness: Double
        /// Gain applied to the whole mix, in dB.
        public var outputGainDB: Double
        public var outputLoudness: Double
        public var outputPeak: Double
    }

    /// A mono voice track `frames` long with every clip's audio placed at its start time.
    /// Clips are cut at their recorded duration (a sentence stopped early stops here too).
    public static func voiceTrack(
        clips: [SpokenClip],
        sampleRate: Double,
        frames: Int,
        audio: (SpokenClip) -> [Float]?
    ) -> [Float] {
        var track = [Float](repeating: 0, count: frames)
        for clip in clips {
            guard let samples = audio(clip) else { continue }
            let start = Int((clip.start * sampleRate).rounded())
            let length = min(samples.count, Int((clip.duration * sampleRate).rounded()) + 1)
            guard start < frames, length > 0 else { continue }
            let end = min(frames, start + length)
            for index in start..<end {
                track[index] += samples[index - start]
            }
        }
        return track
    }

    /// Voice (mono, centred) plus music, levelled and limited.
    public static func mix(voice: [Float], music: StereoBuffer, levels: Levels = Levels()) -> Result {
        let frames = max(voice.count, music.frames)
        let rate = music.sampleRate

        // The voice as it will sound in the stereo mix: the same signal on both sides.
        let voiceLoudness = Loudness.integrated(channels: [voice, voice], sampleRate: rate)
        let voiceGainDB = voiceLoudness.isFinite ? levels.voiceLoudness - voiceLoudness : 0
        let voiceGain = Float(Gain.linear(fromDB: voiceGainDB))
        let musicLoudness = Loudness.integrated(music)

        var mixed = StereoBuffer(frames: frames, sampleRate: rate)
        for index in 0..<frames {
            let v = index < voice.count ? voice[index] * voiceGain : 0
            let left = index < music.frames ? music.left[index] : 0
            let right = index < music.frames ? music.right[index] : 0
            mixed.left[index] = v + left
            mixed.right[index] = v + right
        }

        let loudness = Loudness.integrated(mixed)
        let outputGainDB = loudness.isFinite ? levels.outputLoudness - loudness : 0
        mixed.scale(by: Float(Gain.linear(fromDB: outputGainDB)))
        let ceiling = Float(Gain.linear(fromDB: levels.ceiling))
        if mixed.samplePeak > ceiling * 0.7 {
            softLimit(&mixed, ceiling: ceiling)
        }
        return Result(
            audio: mixed,
            voiceGainDB: voiceGainDB,
            musicLoudness: musicLoudness,
            outputGainDB: outputGainDB,
            outputLoudness: Loudness.integrated(mixed),
            outputPeak: Loudness.truePeak(mixed)
        )
    }

    /// A soft knee above 70% of the ceiling, so peaks round off instead of clipping.
    static func softLimit(_ audio: inout StereoBuffer, ceiling: Float) {
        let knee = ceiling * 0.7
        let room = ceiling - knee
        func shape(_ x: Float) -> Float {
            let magnitude = abs(x)
            guard magnitude > knee else { return x }
            let shaped = knee + room * Float(tanh(Double((magnitude - knee) / room)))
            return x < 0 ? -shaped : shaped
        }
        for index in audio.left.indices {
            audio.left[index] = shape(audio.left[index])
            audio.right[index] = shape(audio.right[index])
        }
    }

    // MARK: - Timeline

    /// A plain-text account of the run to read along with the audio: chapters, the text
    /// side's readings, and when the music changed and to which track.
    public static func timeline(_ report: OfflineStoryRun.Report, story: DemoStory, library: MusicLibrary? = nil) -> String {
        enum Line {
            case chapter(Int)
            case reading(OfflineStoryRun.TimedReading)
            case decision(OfflineStoryRun.TimedDecision)
            case track(String, MoodBucket, Bool)
        }
        var lines: [(TimeInterval, Int, Line)] = []
        var order = 0
        func add(_ time: TimeInterval, _ line: Line) {
            lines.append((time, order, line))
            order += 1
        }
        var seenChapters = Set<Int>()
        for clip in report.clips {
            let chapter = story.sentences[clip.globalIndex].chapter
            if seenChapters.insert(chapter).inserted {
                add(clip.start, .chapter(chapter))
            }
        }
        for reading in report.readings {
            add(reading.time, .reading(reading))
        }
        for decision in report.decisions {
            add(decision.time, .decision(decision))
        }
        var lastTrack: String?
        for timed in report.events {
            if case let .trackStarted(trackID, mood, _, _) = timed.event, trackID != lastTrack {
                add(timed.time, .track(trackID, mood, lastTrack == nil))
                lastTrack = trackID
            }
        }
        lines.sort { ($0.0, $0.1) < ($1.0, $1.1) }

        func title(of trackID: String) -> String {
            guard let track = library?.tracks.first(where: { $0.id == trackID }) else { return trackID }
            return (track.file as NSString).lastPathComponent
        }

        // Where the text turns to a new mood, by the story's own labels, to show how long
        // the music took to follow.
        var clipStart: [Int: TimeInterval] = [:]
        for clip in report.clips where clipStart[clip.globalIndex] == nil {
            clipStart[clip.globalIndex] = clip.start
        }
        let turns = story.sentences.filter { sentence in
            sentence.globalIndex == 0 || story.sentences[sentence.globalIndex - 1].mood != sentence.mood
        }
        func follow(_ timed: OfflineStoryRun.TimedDecision) -> (index: Int, seconds: TimeInterval)? {
            guard let turn = turns.last(where: { turn in
                turn.mood == timed.decision.bucket && (clipStart[turn.globalIndex] ?? .infinity) <= timed.time + 1e-9
            }), let start = clipStart[turn.globalIndex] else { return nil }
            return (turn.globalIndex, timed.time - start)
        }

        var text = "\(story.title): offline render\n"
        text += "Times are minutes:seconds into the file. \"text\" is the mood the text side read (shown when "
        text += "it changes); \"music\" is when the music was told to change.\n\n"
        var shownReading: MoodBucket?
        for (time, _, line) in lines {
            let stamp = clock(time)
            switch line {
            case let .chapter(index):
                text += "\n\(stamp)  ── \(story.chapters[index].title) ──\n"
            case let .reading(timed):
                let reading = timed.observation.reading
                guard reading.bucket != shownReading || timed.observation.trigger != .cadence else { continue }
                shownReading = reading.bucket
                text += "\(stamp)    text  @\(timed.observation.globalSentenceIndex) \(reading.bucket.rawValue) "
                text += "\(Int((reading.confidence * 100).rounded()))% (\(timed.observation.trigger.rawValue))\n"
            case let .decision(timed):
                let decision = timed.decision
                text += "\(stamp)  music  \(decision.previous.rawValue) → \(decision.bucket.rawValue) "
                text += "(\(decision.reason.rawValue), \(decision.transition.rawValue))"
                if let follow = follow(timed), follow.index > 0 {
                    text += String(format: ", %.1f s after the text turned at @%d", follow.seconds, follow.index)
                }
                text += "\n"
            case let .track(trackID, mood, first):
                text += "\(stamp)  track  \(first ? "starts" : "now") \(mood.rawValue): \(title(of: trackID))\n"
            }
        }
        text += "\nSentences: \(report.clips.count). Music changes: \(report.decisions.count). "
        text += "Length: \(clock(report.duration)).\n"
        let lag = followLag(report, story: story)
        if lag.turns > 0 {
            text += "Text turns to a new mood: \(lag.turns). The music followed \(lag.followed.count)"
            if let median = lag.median {
                text += String(format: ", a median %.1f s after the turning sentence began (%.1f s to %.1f s)",
                               median, lag.followed.min() ?? 0, lag.followed.max() ?? 0)
            }
            text += "."
            if lag.missed > 0 {
                text += " \(lag.missed) passed too soon after the last change to follow."
            }
            text += "\n"
        }
        return text
    }

    /// How quickly the music followed the story's turns of mood (by its own labels): for
    /// each turn, the first music change to the new mood before the next turn, measured
    /// from the start of the turning sentence. A turn back to the mood the music is
    /// already playing needs no change and counts as followed at once.
    public static func followLag(
        _ report: OfflineStoryRun.Report,
        story: DemoStory
    ) -> (turns: Int, followed: [TimeInterval], missed: Int, median: TimeInterval?) {
        var clipStart: [Int: TimeInterval] = [:]
        for clip in report.clips where clipStart[clip.globalIndex] == nil {
            clipStart[clip.globalIndex] = clip.start
        }
        let turns = story.sentences.filter { sentence in
            sentence.globalIndex > 0 && story.sentences[sentence.globalIndex - 1].mood != sentence.mood
        }
        var followed: [TimeInterval] = []
        var missed = 0
        var counted = 0
        for (n, turn) in turns.enumerated() {
            guard let start = clipStart[turn.globalIndex] else { continue }
            counted += 1
            let end = turns.dropFirst(n + 1).first.flatMap { clipStart[$0.globalIndex] } ?? .infinity
            let playing = report.decisions.last { $0.time < start - 1e-9 }?.decision.bucket ?? .neutral
            if playing == turn.mood {
                followed.append(0)
            } else if let hit = report.decisions.first(where: {
                $0.decision.bucket == turn.mood && $0.time >= start - 1e-9 && $0.time < end
            }) {
                followed.append(hit.time - start)
            } else {
                missed += 1
            }
        }
        let sorted = followed.sorted()
        let median: TimeInterval? = sorted.isEmpty ? nil
            : sorted.count % 2 == 1 ? sorted[sorted.count / 2]
            : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        return (counted, followed, missed, median)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded(.down)))
        return String(format: "%2d:%02d", whole / 60, whole % 60)
    }
}
