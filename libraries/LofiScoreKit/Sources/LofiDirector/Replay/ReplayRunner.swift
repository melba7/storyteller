import Foundation
import LofiScoreCore

/// The outcome of replaying a script.
public struct ReplayResult: Sendable, Hashable {
    public struct Failure: Sendable, Hashable, CustomStringConvertible {
        public var eventIndex: Int
        public var time: TimeInterval
        public var expected: MoodBucket
        public var actual: MoodBucket
        public var note: String?

        public var description: String {
            let at = String(format: "%.1fs", time)
            return "event \(eventIndex) at \(at): expected \(expected), music is \(actual)" + (note.map { " (\($0))" } ?? "")
        }
    }

    public var title: String?
    public var decisions: [MoodDecision]
    public var failures: [Failure]
    public var finalBucket: MoodBucket
    public var ignoredCounts: [MoodDirector.IgnoredReason: Int]
    /// Total replayed time in seconds.
    public var duration: TimeInterval
    /// Seconds spent in each mood, for summaries.
    public var timeInBucket: [MoodBucket: TimeInterval]

    public var passed: Bool { failures.isEmpty }

    /// Mood changes per hour of replayed time.
    public var changesPerHour: Double {
        duration > 0 ? Double(decisions.count) / (duration / 3600) : 0
    }
}

/// Replays a ``ReplayScript`` through a fresh director on a ``ManualClock``,
/// so a whole book's worth of readings runs in milliseconds.
public enum ReplayRunner {
    /// Runs `script`. `config` overrides the script's own config when given.
    /// `onDecision` sees every decision as it happens, with the director in its new state.
    public static func run(
        _ script: ReplayScript,
        config: DirectorConfig? = nil,
        onDecision: ((MoodDecision, MoodDirector) -> Void)? = nil
    ) -> ReplayResult {
        let clock = ManualClock()
        let director = MoodDirector(config: config ?? script.config ?? DirectorConfig(), clock: clock)
        var decisions: [MoodDecision] = []
        var failures: [ReplayResult.Failure] = []
        var timeInBucket: [MoodBucket: TimeInterval] = [:]
        var lastIndex = 0
        var lastMark = 0.0

        func record(_ decision: MoodDecision?) {
            guard let decision else { return }
            decisions.append(decision)
            onDecision?(decision, director)
        }

        func advance(to time: TimeInterval) {
            // Fire held-back changes at their own deadlines, as the player's timer would.
            while let deadline = director.nextDeadline, deadline <= time {
                let at = max(clock.now, deadline)
                timeInBucket[director.currentBucket, default: 0] += at - lastMark
                lastMark = at
                clock.advance(to: at)
                guard let decision = director.tick() else { break }
                record(decision)
            }
            if time > clock.now {
                timeInBucket[director.currentBucket, default: 0] += time - lastMark
                lastMark = time
                clock.advance(to: time)
            }
        }

        let ordered = script.events.enumerated().sorted { lhs, rhs in
            (lhs.element.t, lhs.offset) < (rhs.element.t, rhs.offset)
        }
        for (position, event) in ordered {
            advance(to: max(0, event.t))
            if let playing = event.playing {
                director.setNarrationPlaying(playing)
            }
            if let seek = event.seek {
                director.noteSeek(toGlobalSentenceIndex: seek >= 0 ? seek : nil)
                if seek >= 0 { lastIndex = seek }
            }
            if let playhead = event.playhead {
                director.notePlayhead(globalSentenceIndex: playhead)
            }
            if let reading = event.reading {
                let index = event.index ?? lastIndex + 4
                lastIndex = index
                let observation = MoodObservation(
                    reading: reading.moodReading,
                    chapterOrdinal: event.chapter ?? 0,
                    sentenceIndex: event.sentence ?? index,
                    globalSentenceIndex: index,
                    trigger: event.trigger ?? .cadence
                )
                record(director.receive(observation))
            }
            if let expected = event.expect, director.currentBucket != expected {
                failures.append(.init(
                    eventIndex: position,
                    time: clock.now,
                    expected: expected,
                    actual: director.currentBucket,
                    note: event.note
                ))
            }
        }
        let end = max(clock.now, script.duration ?? 0)
        advance(to: end)

        return ReplayResult(
            title: script.title,
            decisions: decisions,
            failures: failures,
            finalBucket: director.currentBucket,
            ignoredCounts: director.ignoredCounts,
            duration: end,
            timeInBucket: timeInBucket
        )
    }
}
