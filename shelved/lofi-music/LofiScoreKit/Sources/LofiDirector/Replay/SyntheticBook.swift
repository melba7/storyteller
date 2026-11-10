import Foundation
import LofiScoreCore

/// A made-up book: a known mood timeline plus the noisy readings an engine might produce
/// for it. Lets tests and `lofi-replay` check the director over many hours of listening
/// and compare its choices with the "true" mood.
public struct SyntheticBook: Sendable {
    public struct Segment: Sendable, Hashable {
        public var bucket: MoodBucket
        public var start: TimeInterval
        public var end: TimeInterval
    }

    public struct Options: Sendable, Hashable {
        public var hours: Double = 10
        /// Average length of a stretch of one mood, in seconds.
        public var meanSegment: TimeInterval = 600
        public var minimumSegment: TimeInterval = 120
        /// Average chapter length, in seconds.
        public var meanChapter: TimeInterval = 1800
        /// Seconds between readings (the engine's cadence).
        public var readingInterval: TimeInterval = 20
        /// Seconds of narration per sentence.
        public var sentenceLength: TimeInterval = 5
        /// How far back an engine's window reaches, in seconds of narration (about 400 words).
        public var windowLength: TimeInterval = 150
        /// Chance that a reading names a wrong (usually neighbouring) mood.
        public var labelNoise: Double = 0.2
        /// Spread of valence/arousal noise around the label's anchor.
        public var pointNoise: Double = 0.12
        /// Chance per segment that it opens with a sudden, very confident reading.
        public var suddenOpenings: Double = 0.1
        /// Average number of pauses per hour (each 1 to 10 minutes).
        public var pausesPerHour: Double = 0.5
        /// Average length of a run of wrong live readings, in seconds. 0 draws each wrong
        /// reading on its own, which suits a 20-second cadence; read every sentence,
        /// neighbouring windows overlap and an engine stays wrong for a few sentences.
        public var noiseEpisode: TimeInterval = 0

        /// Where readings come from: a live engine reading the window, or the book's mood
        /// track (readings marked ``ReadingSource/track``).
        public var source: ReadingSource = .live
        /// With a track: the most sentences after a real turn that the track marks it (the
        /// text side pins each turn by bisection to within a few sentences).
        public var trackPinSentences = 3
        /// With a track: chance that it misses a turn and stays on the old mood until the next.
        public var trackMissedTurns = 0.1
        /// With a track: set false to send its readings unmarked, as live readings, the way
        /// the director saw them before tracks were marked.
        public var markTrackReadings = true

        public init() {}
    }

    public var segments: [Segment]
    public var chapterStarts: [TimeInterval]
    public var script: ReplayScript

    /// The true mood of the story at listening time `t` (`nil` while paused).
    public func trueBucket(at t: TimeInterval) -> MoodBucket? {
        segments.first { $0.start <= t && t < $0.end }?.bucket
    }

    /// Builds a book. The same seed always builds the same book.
    public static func generate(seed: UInt64, options: Options = Options()) -> SyntheticBook {
        var rng = SplitMix64(seed: seed)
        let length = options.hours * 3600

        // The story's mood timeline, in story time (seconds of narration).
        var segments: [Segment] = []
        var t = 0.0
        var bucket = MoodBucket.allCases.randomElement(using: &rng) ?? .neutral
        while t < length {
            let draw = -log(max(rng.nextUnit(), 1e-9)) * options.meanSegment
            let duration = min(max(options.minimumSegment, draw), options.meanSegment * 3)
            segments.append(Segment(bucket: bucket, start: t, end: min(length, t + duration)))
            t += duration
            bucket = nextBucket(after: bucket, using: &rng)
        }

        var chapterStarts: [TimeInterval] = []
        var chapterTime = 0.0
        while chapterTime < length {
            chapterStarts.append(chapterTime)
            chapterTime += options.meanChapter * (0.7 + 0.6 * rng.nextUnit())
        }

        func storyBucket(at storyTime: TimeInterval) -> MoodBucket {
            segments.first { $0.start <= storyTime && storyTime < $0.end }?.bucket ?? segments.last?.bucket ?? .neutral
        }

        // The book's mood track, as the text side would have scored it: each turn marked up
        // to a few sentences late, now and then one missed. It draws from its own generator,
        // so live books stay exactly as they were.
        var trackRNG = SplitMix64(seed: seed ^ 0x5452_4143_4B00)
        var trackTurns: [(start: TimeInterval, bucket: MoodBucket)] = []
        if options.source == .track, let first = segments.first {
            trackTurns.append((0, first.bucket))
            for segment in segments.dropFirst() {
                if trackRNG.nextUnit() < options.trackMissedTurns { continue }
                let pinned = Double(Int(trackRNG.nextUnit() * Double(options.trackPinSentences + 1)))
                let start = max(trackTurns[trackTurns.count - 1].start, segment.start + pinned * options.sentenceLength)
                guard start < segment.end else { continue }
                trackTurns.append((start, segment.bucket))
            }
        }
        func trackBucket(at storyTime: TimeInterval) -> MoodBucket {
            trackTurns.last { $0.start <= storyTime }?.bucket ?? storyBucket(at: storyTime)
        }
        var noiseUntil = -1.0
        var noiseLabel = MoodBucket.neutral
        var noiseConfidence = 0.5

        // The mood an honest engine would see: the most common mood in its window.
        func windowBucket(at storyTime: TimeInterval) -> MoodBucket {
            var tally: [MoodBucket: Double] = [:]
            var probe = max(0, storyTime - options.windowLength)
            while probe <= storyTime {
                // Recent text counts a little more, as it does for a real engine.
                let recency = 1 + (probe - (storyTime - options.windowLength)) / options.windowLength
                tally[storyBucket(at: probe), default: 0] += recency
                probe += options.sentenceLength
            }
            return tally.max { $0.value < $1.value }?.key ?? storyBucket(at: storyTime)
        }

        // Listening time = story time plus pauses.
        var events: [ReplayEvent] = [ReplayEvent(t: 0, playing: true)]
        var listeningSegments: [Segment] = []
        var storyTime = 0.0
        var wallTime = 0.0
        var nextReading = 2.0
        var chapterIndex = 0
        var pendingChapterReading = false
        var openedSegments: Set<Int> = []
        var firstReading = true

        let pauseChancePerReading = options.pausesPerHour * options.readingInterval / 3600
        while storyTime < length {
            let step = min(nextReading, length) - storyTime
            // Record the true mood over this stretch in listening time.
            appendTimeline(&listeningSegments, from: wallTime, story: storyTime, duration: step, storyBucket: storyBucket)
            storyTime += step
            wallTime += step
            guard storyTime < length else { break }

            while chapterIndex + 1 < chapterStarts.count, chapterStarts[chapterIndex + 1] <= storyTime {
                chapterIndex += 1
                pendingChapterReading = true
            }
            let sentence = Int(storyTime / options.sentenceLength)
            let chapterStartSentence = Int(chapterStarts[chapterIndex] / options.sentenceLength)

            var trigger = ReadingTrigger.cadence
            if firstReading {
                trigger = .start
                firstReading = false
            } else if pendingChapterReading {
                if sentence - chapterStartSentence >= 3 {
                    trigger = .chapterStart
                    pendingChapterReading = false
                } else {
                    // Hold readings until a few sentences into the new chapter.
                    nextReading = storyTime + options.sentenceLength
                    continue
                }
            }

            let reading: ReplayReading
            if options.source == .track {
                let label = trackBucket(at: storyTime)
                let confidence = min(0.95, max(0.5, trackRNG.nextGaussian(mean: 0.8, deviation: 0.07)))
                reading = ReplayReading(
                    bucket: label,
                    valence: label.anchor.valence + trackRNG.nextGaussian(deviation: options.pointNoise / 2),
                    arousal: label.anchor.arousal + trackRNG.nextGaussian(deviation: options.pointNoise / 4),
                    confidence: (confidence * 100).rounded() / 100,
                    source: options.markTrackReadings ? .track : nil
                )
            } else {
                let truth = windowBucket(at: storyTime)
                let segmentIndex = segments.firstIndex { $0.start <= storyTime && storyTime < $0.end } ?? 0
                var label = truth
                var confidence = min(0.95, max(0.2, rng.nextGaussian(mean: 0.65, deviation: 0.12)))
                if !openedSegments.contains(segmentIndex), storyTime - segments[segmentIndex].start < options.readingInterval * 1.5 {
                    openedSegments.insert(segmentIndex)
                    if rng.nextUnit() < options.suddenOpenings {
                        label = segments[segmentIndex].bucket
                        confidence = 0.9
                    }
                }
                if options.noiseEpisode > 0 {
                    // Runs of wrong readings, about labelNoise of all readings in all.
                    if storyTime < noiseUntil, noiseLabel != truth {
                        label = noiseLabel
                        confidence = min(0.9, max(0.15, noiseConfidence + rng.nextGaussian(deviation: 0.04)))
                    } else if label == truth {
                        // A run lasts 1 / (1 - e^(-interval / episode)) readings on average;
                        // start runs so that labelNoise of all readings are wrong.
                        let p = min(0.99, options.labelNoise)
                        let runReadings = 1 / (1 - exp(-options.readingInterval / options.noiseEpisode))
                        let startChance = p / (runReadings * (1 - p) + p)
                        if rng.nextUnit() < startChance {
                            noiseLabel = nextBucket(after: truth, using: &rng)
                            noiseUntil = storyTime - log(max(rng.nextUnit(), 1e-9)) * options.noiseEpisode
                            noiseConfidence = min(0.9, max(0.15, rng.nextGaussian(mean: 0.5, deviation: 0.12)))
                            label = noiseLabel
                            confidence = noiseConfidence
                        }
                    }
                } else if label == truth, rng.nextUnit() < options.labelNoise {
                    label = nextBucket(after: truth, using: &rng)
                    confidence = min(0.9, max(0.15, rng.nextGaussian(mean: 0.5, deviation: 0.12)))
                }
                let anchor = label.anchor
                reading = ReplayReading(
                    bucket: label,
                    valence: anchor.valence + rng.nextGaussian(deviation: options.pointNoise),
                    arousal: anchor.arousal + rng.nextGaussian(deviation: options.pointNoise / 2),
                    confidence: (confidence * 100).rounded() / 100
                )
            }
            events.append(ReplayEvent(
                t: (wallTime * 10).rounded() / 10,
                reading: reading,
                index: sentence,
                chapter: chapterIndex,
                sentence: sentence - chapterStartSentence,
                trigger: trigger
            ))

            if rng.nextUnit() < pauseChancePerReading {
                let pause = 60 + rng.nextUnit() * 540
                events.append(ReplayEvent(t: wallTime + 0.5, playing: false, note: "pause"))
                wallTime += pause
                events.append(ReplayEvent(t: wallTime, playing: true, note: "resume"))
            }
            nextReading = storyTime + options.readingInterval * (0.85 + 0.3 * rng.nextUnit())
        }

        let script = ReplayScript(
            title: "Synthetic book, seed \(seed), \(options.hours) h",
            duration: wallTime,
            events: events
        )
        return SyntheticBook(segments: listeningSegments, chapterStarts: chapterStarts, script: script)
    }

    /// A mood that follows `bucket`: usually a neighbour on the valence/arousal map.
    static func nextBucket(after bucket: MoodBucket, using rng: inout SplitMix64) -> MoodBucket {
        let others = MoodBucket.allCases.filter { $0 != bucket }
        let weights = others.map { 1 / (0.3 + $0.anchor.distance(to: bucket.anchor)) }
        var pick = rng.nextUnit() * weights.reduce(0, +)
        for (candidate, weight) in zip(others, weights) {
            pick -= weight
            if pick <= 0 { return candidate }
        }
        return others.last ?? bucket
    }

    private static func appendTimeline(
        _ timeline: inout [Segment],
        from wallStart: TimeInterval,
        story storyStart: TimeInterval,
        duration: TimeInterval,
        storyBucket: (TimeInterval) -> MoodBucket
    ) {
        guard duration > 0 else { return }
        var offset = 0.0
        let step = 1.0
        while offset < duration {
            let bucket = storyBucket(storyStart + offset)
            let piece = min(step, duration - offset)
            let wall = wallStart + offset
            if var last = timeline.last, last.bucket == bucket, abs(last.end - wall) < 1e-6 {
                last.end = wall + piece
                timeline[timeline.count - 1] = last
            } else {
                timeline.append(Segment(bucket: bucket, start: wall, end: wall + piece))
            }
            offset += piece
        }
    }
}

extension ReplayResult {
    /// Share of listening time the music's mood matched the story's true mood.
    /// `lag` forgives the music for trailing the story by that many seconds after a change.
    public func agreement(with book: SyntheticBook, lag: TimeInterval = 0) -> Double {
        var musicTimeline: [(start: TimeInterval, bucket: MoodBucket)] = [(0, .neutral)]
        for decision in decisions {
            musicTimeline.append((decision.time, decision.bucket))
        }
        func musicBucket(at t: TimeInterval) -> MoodBucket {
            musicTimeline.last { $0.start <= t }?.bucket ?? .neutral
        }
        var matched = 0.0
        var total = 0.0
        for segment in book.segments {
            var t = segment.start
            while t < segment.end {
                let piece = min(1, segment.end - t)
                total += piece
                let forgiven = lag > 0 && t - segment.start < lag && (book.trueBucket(at: segment.start - 1) == musicBucket(at: t))
                if musicBucket(at: t) == segment.bucket || forgiven {
                    matched += piece
                }
                t += piece
            }
        }
        return total > 0 ? matched / total : 0
    }
}

extension ReplayResult {
    /// How long the music took to reach each new true mood, over segments at least
    /// `minimumSegment` long. Returns the median delay and the share of such segments the
    /// music never reached before they ended.
    public func followDelay(in book: SyntheticBook, minimumSegment: TimeInterval = 180) -> (median: TimeInterval?, missed: Double) {
        var delays: [TimeInterval] = []
        var missed = 0
        var considered = 0
        var musicTimeline: [(start: TimeInterval, bucket: MoodBucket)] = [(0, .neutral)]
        for decision in decisions {
            musicTimeline.append((decision.time, decision.bucket))
        }
        for (index, segment) in book.segments.enumerated() where segment.end - segment.start >= minimumSegment {
            // Only count real mood changes, not the same mood resuming after a pause.
            if index > 0, book.segments[index - 1].bucket == segment.bucket { continue }
            considered += 1
            let playingAtStart = musicTimeline.last { $0.start <= segment.start }?.bucket
            if playingAtStart == segment.bucket {
                delays.append(0)
                continue
            }
            if let reached = musicTimeline.first(where: { $0.start >= segment.start && $0.start < segment.end && $0.bucket == segment.bucket }) {
                delays.append(reached.start - segment.start)
            } else {
                missed += 1
            }
        }
        let sorted = delays.sorted()
        let median = sorted.isEmpty ? nil : sorted[sorted.count / 2]
        return (median, considered > 0 ? Double(missed) / Double(considered) : 0)
    }

    /// Changes that broke the dwell rule: a regular change less than `minimumDwell` after
    /// the previous change (or a track turn less than `trackMinimumDwell` after it), made
    /// while the rule applied.
    public func dwellViolations(minimumDwell: TimeInterval, trackMinimumDwell: TimeInterval? = nil) -> [MoodDecision] {
        var violations: [MoodDecision] = []
        let trackDwell = trackMinimumDwell ?? minimumDwell
        for (previous, decision) in zip(decisions, decisions.dropFirst()) {
            let gap = decision.time - previous.time
            switch decision.reason {
            case .confirmed:
                if !decision.dwellWaived, gap < minimumDwell - 1e-6 { violations.append(decision) }
            case .trackTurn:
                if !decision.dwellWaived, gap < trackDwell - 1e-6 { violations.append(decision) }
            case .dwellElapsed:
                // Released by either rule: it must at least have waited the shorter one.
                if !decision.dwellWaived, gap < min(minimumDwell, trackDwell) - 1e-6 { violations.append(decision) }
            default:
                break
            }
        }
        return violations
    }
}
