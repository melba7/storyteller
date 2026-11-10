import Foundation
import LofiScoreCore

/// Turns noisy mood readings into calm, rule-bound music decisions.
///
/// The director is pure logic: it reads time only through an injected ``LofiClock``,
/// never schedules anything itself and never touches audio. Feed it readings with
/// ``receive(_:)``; when a change it held back may go ahead later, ``nextDeadline``
/// says when to call ``tick()``.
///
/// The rules, from the plan:
/// - Evidence per mood fades over about 60 seconds of listening (``MoodEvidence``).
/// - A new mood must win two readings in a row, or one reading at least 0.8 confident
///   that lands far from the current mood (a big jump).
/// - The music keeps a mood for at least 90 seconds, except right after a seek or at a
///   chapter start, where the first reading decides at once.
/// - It only ever reacts to readings at or before the sentence being narrated; a reading
///   for a later sentence is refused (``IgnoredReason/aheadOfPlayhead``).
///
/// Not thread-safe: use it from one queue (``LofiScorePlayer`` does).
public final class MoodDirector {
    public enum Phase: Sendable, Hashable {
        /// A book was just opened; the first reading decides.
        case awaitingFirstReading
        /// The listener jumped; the reading for the new place decides. Older readings are ignored.
        case awaitingSeekReading(target: Int?, since: TimeInterval)
        /// Normal listening.
        case following
    }

    /// Why a reading was not used.
    public enum IgnoredReason: String, Sendable, Hashable, Codable, CaseIterable {
        /// The reading is for a sentence after the one being narrated. Never used: no spoilers.
        case aheadOfPlayhead
        /// The reading was taken before the latest seek.
        case beforeSeek
        /// The reading is older than one already used.
        case outOfOrder
    }

    public let config: DirectorConfig
    private let clock: LofiClock

    public private(set) var currentBucket: MoodBucket
    public private(set) var phase: Phase = .awaitingFirstReading
    /// Clock time of the last change, if any since the book opened.
    public private(set) var lastChangeTime: TimeInterval?
    /// True while the dwell rule is suspended: after a seek or chapter start until the next
    /// change, and after a provisional change.
    public private(set) var dwellWaived = true
    public private(set) var evidence = MoodEvidence()
    public private(set) var lastObservation: MoodObservation?
    public private(set) var playheadIndex: Int?
    public private(set) var ignoredCounts: [IgnoredReason: Int] = [:]
    /// The most recent decisions, oldest first (at most 50).
    public private(set) var recentDecisions: [MoodDecision] = []

    private var pending: (bucket: MoodBucket, count: Int)?
    private var lastAcceptedIndex: Int?
    private var listening: ListeningTime

    public init(config: DirectorConfig = DirectorConfig(), clock: LofiClock, initialBucket: MoodBucket = .neutral) {
        self.config = config
        self.clock = clock
        currentBucket = initialBucket
        listening = ListeningTime(runningSince: clock.now)
    }

    // MARK: - Inputs

    /// Forgets the current book. The music returns to `bucket` and the next reading decides.
    public func reset(to bucket: MoodBucket = .neutral) {
        currentBucket = bucket
        phase = .awaitingFirstReading
        lastChangeTime = nil
        dwellWaived = true
        evidence = MoodEvidence()
        lastObservation = nil
        playheadIndex = nil
        pending = nil
        lastAcceptedIndex = nil
        recentDecisions.removeAll()
    }

    /// Whether narration is playing. Evidence fades only while it plays, so a pause does
    /// not wipe out what the director knows. Dwell timers keep counting in wall-clock time.
    public func setNarrationPlaying(_ playing: Bool) {
        listening.setRunning(playing, at: clock.now)
    }

    /// The sentence being narrated right now. Once set, readings for later sentences are refused.
    public func notePlayhead(globalSentenceIndex index: Int) {
        playheadIndex = index
    }

    /// The listener jumped to another place in the book. Until the reading for the new
    /// place arrives, older readings are ignored. Pass the new sentence's index if known.
    public func noteSeek(toGlobalSentenceIndex target: Int?) {
        phase = .awaitingSeekReading(target: target, since: clock.now)
        pending = nil
        lastAcceptedIndex = nil
        if playheadIndex != nil, let target {
            playheadIndex = target
        }
    }

    /// Feeds one reading. Returns a decision when the music should change now.
    @discardableResult
    public func receive(_ observation: MoodObservation) -> MoodDecision? {
        let now = clock.now
        let index = observation.globalSentenceIndex
        if let playhead = playheadIndex, index > playhead {
            return ignore(.aheadOfPlayhead)
        }
        switch phase {
        case .awaitingFirstReading:
            return acceptBoundary(observation, reason: .firstReading, at: now)
        case let .awaitingSeekReading(target, since):
            let isSeekReading = observation.trigger == .seek || observation.trigger == .start
            let reachedTarget = target.map { index >= $0 } ?? false
            let timedOut = now - since >= config.seekReadingTimeout
            guard isSeekReading || reachedTarget || timedOut else {
                return ignore(.beforeSeek)
            }
            return acceptBoundary(observation, reason: .seek, at: now)
        case .following:
            switch observation.trigger {
            case .seek:
                return acceptBoundary(observation, reason: .seek, at: now)
            case .start:
                // A new listening stretch. If it simply carries on from where the last one
                // stopped (a pause and resume), treat it as a regular reading; if it starts
                // somewhere else, it decides like a seek.
                guard let last = lastAcceptedIndex,
                      index >= last,
                      index - last <= config.resumeContinuityWindow
                else {
                    return acceptBoundary(observation, reason: .seek, at: now)
                }
                return acceptCadence(observation, at: now)
            case .chapterStart, .cadence:
                if let last = lastAcceptedIndex, index < last {
                    return ignore(.outOfOrder)
                }
                if observation.trigger == .chapterStart {
                    return acceptChapterStart(observation, at: now)
                }
                return acceptCadence(observation, at: now)
            }
        }
    }

    /// Lets a change that was held back by the dwell rule go ahead, if it still stands.
    @discardableResult
    public func tick() -> MoodDecision? {
        let now = clock.now
        guard case .following = phase,
              let pending,
              pending.count >= requiredReadings,
              dwellAllows(config.minimumDwell, at: now)
        else { return nil }
        evidence.decay(to: listening.time(at: now), timeConstant: config.evidenceTimeConstant)
        guard evidence.leader(current: currentBucket, config: config) == pending.bucket else {
            self.pending = nil
            return nil
        }
        return change(
            to: pending.bucket,
            reason: .dwellElapsed,
            transition: .gentle,
            observation: lastObservation,
            provisional: false,
            at: now
        )
    }

    /// When ``tick()`` may next return a decision, if anything is waiting.
    public var nextDeadline: TimeInterval? {
        guard case .following = phase,
              let pending,
              pending.count >= requiredReadings,
              !dwellWaived,
              let lastChangeTime
        else { return nil }
        return lastChangeTime + config.minimumDwell
    }

    // MARK: - Inspection

    public var snapshot: DirectorSnapshot {
        let now = clock.now
        var faded = evidence
        faded.decay(to: listening.time(at: now), timeConstant: config.evidenceTimeConstant)
        let dwellRemaining: TimeInterval
        if dwellWaived {
            dwellRemaining = 0
        } else if let lastChangeTime {
            dwellRemaining = max(0, lastChangeTime + config.minimumDwell - now)
        } else {
            dwellRemaining = 0
        }
        return DirectorSnapshot(
            time: now,
            currentBucket: currentBucket,
            leader: faded.leader(current: currentBucket, config: config),
            shares: faded.shares(neutralPrior: config.neutralPrior),
            centroid: faded.centroid(neutralPrior: config.neutralPrior),
            pendingBucket: pending?.bucket,
            pendingCount: pending?.count ?? 0,
            dwellRemaining: dwellRemaining,
            dwellWaived: dwellWaived,
            phase: phase,
            lastReading: lastObservation?.reading,
            lastDecision: recentDecisions.last,
            ignoredCounts: ignoredCounts
        )
    }

    // MARK: - Rules

    private var requiredReadings: Int {
        max(1, config.confirmationReadings)
    }

    /// The first reading after a book opened or a seek: it alone sets the mood.
    private func acceptBoundary(
        _ observation: MoodObservation,
        reason: MoodDecision.Reason,
        at now: TimeInterval
    ) -> MoodDecision? {
        phase = .following
        lastAcceptedIndex = observation.globalSentenceIndex
        lastObservation = observation
        pending = nil
        evidence.removeAll()
        evidence.add(
            observation.reading.evidence(config: config),
            at: listening.time(at: now),
            timeConstant: config.evidenceTimeConstant
        )
        dwellWaived = true
        let leader = evidence.leader(current: currentBucket, config: config)
        guard leader != currentBucket else { return nil }
        return change(
            to: leader,
            reason: reason,
            transition: .quick,
            observation: observation,
            provisional: observation.reading.confidence < config.provisionalConfidence,
            at: now
        )
    }

    /// The first reading a few sentences into a new chapter: most old evidence is dropped,
    /// and the result decides at once, without waiting for the dwell or a second reading.
    private func acceptChapterStart(_ observation: MoodObservation, at now: TimeInterval) -> MoodDecision? {
        lastAcceptedIndex = observation.globalSentenceIndex
        lastObservation = observation
        pending = nil
        let time = listening.time(at: now)
        evidence.decay(to: time, timeConstant: config.evidenceTimeConstant)
        evidence.scale(by: config.chapterCarryOver)
        evidence.add(observation.reading.evidence(config: config), at: time, timeConstant: config.evidenceTimeConstant)
        dwellWaived = true
        let leader = evidence.leader(current: currentBucket, config: config)
        guard leader != currentBucket else { return nil }
        return change(
            to: leader,
            reason: .chapterStart,
            transition: .gentle,
            observation: observation,
            provisional: observation.reading.confidence < config.provisionalConfidence,
            at: now
        )
    }

    /// A regular reading: smoothing, two-reading confirmation and the dwell rule apply.
    private func acceptCadence(_ observation: MoodObservation, at now: TimeInterval) -> MoodDecision? {
        lastAcceptedIndex = observation.globalSentenceIndex
        lastObservation = observation
        let reading = observation.reading
        let time = listening.time(at: now)
        evidence.add(reading.evidence(config: config), at: time, timeConstant: config.evidenceTimeConstant)

        // One very confident reading far from where the music is: react now.
        if reading.confidence >= config.bigJumpConfidence,
           reading.bucket != currentBucket,
           reading.point.distance(to: currentBucket.anchor) >= config.bigJumpDistance,
           dwellAllows(config.bigJumpMinimumDwell, at: now) {
            // Start the evidence over from this reading, so the old mood does not
            // immediately win the music back.
            evidence.removeAll()
            evidence.add(reading.evidence(config: config), at: time, timeConstant: config.evidenceTimeConstant)
            return change(
                to: reading.bucket,
                reason: .bigJump,
                transition: .quick,
                observation: observation,
                provisional: false,
                at: now
            )
        }

        let leader = evidence.leader(current: currentBucket, config: config)
        guard leader != currentBucket else {
            pending = nil
            return nil
        }
        let count = (pending?.bucket == leader ? pending?.count ?? 0 : 0) + 1
        pending = (leader, count)
        guard count >= requiredReadings, dwellAllows(config.minimumDwell, at: now) else {
            // Either not confirmed yet, or confirmed and waiting out the dwell (see tick()).
            return nil
        }
        return change(
            to: leader,
            reason: .confirmed,
            transition: .gentle,
            observation: observation,
            provisional: false,
            at: now
        )
    }

    private func dwellAllows(_ minimum: TimeInterval, at now: TimeInterval) -> Bool {
        if dwellWaived { return true }
        guard let lastChangeTime else { return true }
        return now - lastChangeTime >= minimum - 1e-9
    }

    private func change(
        to bucket: MoodBucket,
        reason: MoodDecision.Reason,
        transition: MoodDecision.Transition,
        observation: MoodObservation?,
        provisional: Bool,
        at now: TimeInterval
    ) -> MoodDecision {
        let decision = MoodDecision(
            bucket: bucket,
            previous: currentBucket,
            reason: reason,
            transition: transition,
            time: now,
            globalSentenceIndex: observation?.globalSentenceIndex,
            provisional: provisional,
            dwellWaived: dwellWaived
        )
        currentBucket = bucket
        lastChangeTime = now
        pending = nil
        dwellWaived = provisional
        recentDecisions.append(decision)
        if recentDecisions.count > 50 {
            recentDecisions.removeFirst(recentDecisions.count - 50)
        }
        return decision
    }

    private func ignore(_ reason: IgnoredReason) -> MoodDecision? {
        ignoredCounts[reason, default: 0] += 1
        return nil
    }
}

/// A read-only view of the director, for debug overlays and tests.
/// It shows the present only: nothing in it looks ahead of the narration.
public struct DirectorSnapshot: Sendable, Hashable {
    public var time: TimeInterval
    public var currentBucket: MoodBucket
    /// The bucket the evidence favours right now (with hysteresis).
    public var leader: MoodBucket
    /// Evidence per bucket, neutral prior included, as shares summing to 1.
    public var shares: [MoodBucket: Double]
    /// Evidence-weighted valence and arousal, for a 2D display.
    public var centroid: MoodPoint
    public var pendingBucket: MoodBucket?
    public var pendingCount: Int
    /// Seconds until a regular change is allowed again (0 when allowed now).
    public var dwellRemaining: TimeInterval
    public var dwellWaived: Bool
    public var phase: MoodDirector.Phase
    public var lastReading: MoodReading?
    public var lastDecision: MoodDecision?
    public var ignoredCounts: [MoodDirector.IgnoredReason: Int]
}

/// Listening time: a stopwatch that only runs while narration plays.
struct ListeningTime: Sendable, Hashable {
    private var accumulated: TimeInterval = 0
    private var runningSince: TimeInterval?

    init(runningSince: TimeInterval?) {
        self.runningSince = runningSince
    }

    mutating func setRunning(_ running: Bool, at now: TimeInterval) {
        if running {
            if runningSince == nil { runningSince = now }
        } else if let since = runningSince {
            accumulated += max(0, now - since)
            runningSince = nil
        }
    }

    func time(at now: TimeInterval) -> TimeInterval {
        accumulated + (runningSince.map { max(0, now - $0) } ?? 0)
    }
}
