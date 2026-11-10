import Foundation
import LofiScoreCore

/// Turns noisy mood readings into calm, rule-bound music decisions.
///
/// The director is pure logic: it reads time only through an injected ``LofiClock``,
/// never schedules anything itself and never touches audio. Feed it readings with
/// ``receive(_:)``; when a change it held back may go ahead later, ``nextDeadline``
/// says when to call ``tick()``.
///
/// The rules:
/// - A book's mood track (readings marked ``ReadingSource/track``) pins each turn of mood to
///   the sentence where the text first reads as the new mood. When narration reaches it,
///   the music follows at once, unless it changed less than
///   ``DirectorConfig/trackMinimumDwell`` ago; then it follows when that time is up, if
///   the track still says so.
/// - Live readings are smoothed: evidence per mood fades over about a minute of
///   listening (``MoodEvidence``), each reading weighted by the time since the one before,
///   so reading every sentence smooths no more and no less than reading every 20 seconds.
/// - A new mood must win two live readings in a row and lead for 20 seconds, or be named by
///   readings at least 0.8 confident that land far from the current mood (a big jump): one
///   such reading at the slow cadence, a few seconds' worth when readings come every sentence.
/// - The music keeps a mood for at least 60 seconds after a live change, except right
///   after a seek or at a chapter start, where the first reading decides at once.
/// - It only ever reacts to readings at or before the sentence being narrated; a reading
///   for a later sentence is refused (``IgnoredReason/aheadOfPlayhead``).
/// - When the listener says the mood is wrong (``listenerOverride(to:)``), the music moves at
///   once and the rejected mood is kept out until the text names a third mood, a chapter
///   starts or the listener jumps.
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
    /// A mood the listener said was wrong. Readings naming it are not followed until the
    /// text names another mood (not the one now playing), a chapter starts or the listener
    /// jumps.
    public private(set) var rejectedBucket: MoodBucket?

    /// A mood that is winning but has not changed the music yet.
    private struct Pending {
        var bucket: MoodBucket
        var count: Int
        /// Clock time of the first reading in the run.
        var since: TimeInterval
        /// True when the run is made of mood-track readings.
        var fromTrack: Bool
    }

    private var pending: Pending?
    /// Confident, far live readings in a row naming the same mood, and their summed weight.
    private var jumpRun: (bucket: MoodBucket, weight: Double)?
    private var lastAcceptedIndex: Int?
    /// Clock time of the last reading used, for weighting the next one.
    private var lastReadingTime: TimeInterval?
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
        jumpRun = nil
        lastAcceptedIndex = nil
        lastReadingTime = nil
        recentDecisions.removeAll()
        rejectedBucket = nil
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
        jumpRun = nil
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
        guard case .following = phase, let pending else { return nil }
        if pending.fromTrack {
            // The run is cleared as soon as the track names another mood, so a pending
            // track turn that is still here still stands.
            guard pending.count >= requiredTrackReadings,
                  dwellAllows(config.trackMinimumDwell, at: now)
            else { return nil }
            return trackTurn(to: pending.bucket, reason: .dwellElapsed, transition: .gentle, observation: lastObservation, at: now)
        }
        guard pending.count >= requiredReadings,
              now - pending.since >= config.confirmationTime - 1e-9,
              dwellAllows(config.minimumDwell, at: now)
        else { return nil }
        evidence.decay(to: listening.time(at: now), timeConstant: config.evidenceTimeConstant)
        dropRejectedEvidence()
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

    /// The listener said the music's mood is wrong and chose `bucket` instead (or accepted
    /// the next guess, ``nextGuess(excluding:hasTracks:)``). The music changes at once with a
    /// quick crossfade and then keeps `bucket` for the usual dwell. The mood that was playing
    /// is rejected: its evidence is dropped, and readings naming it are not followed until
    /// the text names a third mood, a chapter starts or the listener jumps. Returns nil when
    /// `bucket` is already playing.
    @discardableResult
    public func listenerOverride(to bucket: MoodBucket) -> MoodDecision? {
        let now = clock.now
        guard bucket != currentBucket else { return nil }
        // Picking again within two minutes of a guess replaces the guess; the mood first
        // rejected stays rejected, unless the listener picked it back.
        let correcting = recentDecisions.last.map { $0.reason == .listener && now - $0.time < 120 } ?? false
        if let rejected = rejectedBucket, correcting {
            rejectedBucket = rejected == bucket ? currentBucket : rejected
        } else {
            rejectedBucket = currentBucket
        }
        if let rejectedBucket { evidence.clear(rejectedBucket) }
        pending = nil
        jumpRun = nil
        // Not a provisional change: the dwell holds the listener's choice.
        let decision = change(
            to: bucket,
            reason: .listener,
            transition: .quick,
            observation: lastObservation,
            provisional: false,
            at: now
        )
        return decision
    }

    /// The director's best guess other than the moods in `excluding`: the bucket the
    /// evidence favours most, ties broken by closeness to the evidence's centre on the
    /// valence/arousal map. `hasTracks` limits it to moods the library can play.
    public func nextGuess(excluding: Set<MoodBucket>, hasTracks: (MoodBucket) -> Bool = { _ in true }) -> MoodBucket? {
        var faded = evidence
        faded.decay(to: listening.time(at: clock.now), timeConstant: config.evidenceTimeConstant)
        let shares = faded.shares(neutralPrior: config.neutralPrior)
        let centre = faded.centroid(neutralPrior: config.neutralPrior)
        let candidates = MoodBucket.allCases.filter { !excluding.contains($0) }
        let playable = candidates.filter(hasTracks)
        let pool = playable.isEmpty ? candidates : playable
        return pool.min { lhs, rhs in
            let left = shares[lhs] ?? 0
            let right = shares[rhs] ?? 0
            if abs(left - right) > 0.01 { return left > right }
            return lhs.anchor.distance(to: centre) < rhs.anchor.distance(to: centre)
        }
    }

    /// When ``tick()`` may next return a decision, if anything is waiting.
    public var nextDeadline: TimeInterval? {
        guard case .following = phase, let pending else { return nil }
        if pending.fromTrack {
            guard pending.count >= requiredTrackReadings, !dwellWaived, let lastChangeTime else { return nil }
            return lastChangeTime + config.trackMinimumDwell
        }
        guard pending.count >= requiredReadings else { return nil }
        let confirmed = pending.since + config.confirmationTime
        guard !dwellWaived, let lastChangeTime else {
            // Only the confirmation time is left to wait for.
            return confirmed > clock.now ? confirmed : nil
        }
        return max(lastChangeTime + config.minimumDwell, confirmed)
    }

    // MARK: - Inspection

    public var snapshot: DirectorSnapshot {
        let now = clock.now
        var faded = evidence
        faded.decay(to: listening.time(at: now), timeConstant: config.evidenceTimeConstant)
        let dwellRemaining: TimeInterval
        let dwell = pending?.fromTrack == true ? config.trackMinimumDwell : config.minimumDwell
        if dwellWaived {
            dwellRemaining = 0
        } else if let lastChangeTime {
            dwellRemaining = max(0, lastChangeTime + dwell - now)
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
            ignoredCounts: ignoredCounts,
            rejectedBucket: rejectedBucket
        )
    }

    // MARK: - Rules

    private var requiredReadings: Int {
        max(1, config.confirmationReadings)
    }

    private var requiredTrackReadings: Int {
        max(1, config.trackConfirmationReadings)
    }

    /// How much a reading taken now counts: in full when at least
    /// ``DirectorConfig/evidenceReferenceInterval`` passed since the previous reading,
    /// proportionally less when readings come faster.
    private func readingWeight(at now: TimeInterval) -> Double {
        guard config.evidenceReferenceInterval > 0, let last = lastReadingTime else { return 1 }
        return min(1, max(0.05, (now - last) / config.evidenceReferenceInterval))
    }

    private func scaled(_ contribution: [MoodBucket: Double], by weight: Double) -> [MoodBucket: Double] {
        weight == 1 ? contribution : contribution.mapValues { $0 * weight }
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
        lastReadingTime = now
        pending = nil
        jumpRun = nil
        rejectedBucket = nil
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
        rejectedBucket = nil
        lastAcceptedIndex = observation.globalSentenceIndex
        lastObservation = observation
        lastReadingTime = now
        pending = nil
        jumpRun = nil
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

    /// A regular reading: mood-track readings follow the track's turns; live readings go
    /// through smoothing, confirmation and the dwell rule.
    private func acceptCadence(_ observation: MoodObservation, at now: TimeInterval) -> MoodDecision? {
        if observation.source == .track,
           observation.reading.confidence >= config.trackMinimumConfidence {
            return acceptTrack(observation, at: now)
        }
        lastAcceptedIndex = observation.globalSentenceIndex
        lastObservation = observation
        let reading = observation.reading
        let time = listening.time(at: now)
        let weight = readingWeight(at: now)
        lastReadingTime = now
        noteRejection(reading.bucket)
        evidence.add(scaled(reading.evidence(config: config), by: weight), at: time, timeConstant: config.evidenceTimeConstant)
        dropRejectedEvidence()

        // Very confident readings far from where the music is: react now. One reading is
        // enough at the slow cadence; read every sentence, a few in a row are needed.
        if reading.confidence >= config.bigJumpConfidence,
           reading.bucket != currentBucket,
           reading.bucket != rejectedBucket,
           reading.point.distance(to: currentBucket.anchor) >= config.bigJumpDistance {
            if let run = jumpRun, run.bucket == reading.bucket {
                jumpRun = (run.bucket, run.weight + weight)
            } else {
                jumpRun = (reading.bucket, weight)
            }
        } else {
            jumpRun = nil
        }
        if let run = jumpRun,
           run.weight >= config.bigJumpWeight - 1e-9,
           dwellAllows(config.bigJumpMinimumDwell, at: now) {
            // Start the evidence over from this reading, so the old mood does not
            // immediately win the music back.
            evidence.removeAll()
            evidence.add(reading.evidence(config: config), at: time, timeConstant: config.evidenceTimeConstant)
            return change(
                to: run.bucket,
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
        var run = Pending(bucket: leader, count: 1, since: now, fromTrack: false)
        if let pending, !pending.fromTrack, pending.bucket == leader {
            run.count = pending.count + 1
            run.since = pending.since
        }
        pending = run
        guard run.count >= requiredReadings,
              now - run.since >= config.confirmationTime - 1e-9,
              dwellAllows(config.minimumDwell, at: now)
        else {
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

    /// A reading from the book's mood track. The track already pins each turn to the
    /// sentence where the text first reads as the new mood, so the music follows as soon
    /// as narration gets there, without smoothing it again.
    private func acceptTrack(_ observation: MoodObservation, at now: TimeInterval) -> MoodDecision? {
        lastAcceptedIndex = observation.globalSentenceIndex
        lastObservation = observation
        jumpRun = nil
        let reading = observation.reading
        let time = listening.time(at: now)
        let weight = readingWeight(at: now)
        lastReadingTime = now
        noteRejection(reading.bucket)
        // Track readings feed the evidence too, so a live engine taking over where the
        // track ends starts from what the track said.
        evidence.add(scaled(reading.evidence(config: config), by: weight), at: time, timeConstant: config.evidenceTimeConstant)
        dropRejectedEvidence()

        let bucket = reading.bucket
        // The listener said this mood was wrong here: stay where they put the music.
        guard bucket != currentBucket, bucket != rejectedBucket else {
            pending = nil
            return nil
        }
        var run = Pending(bucket: bucket, count: 1, since: now, fromTrack: true)
        if let pending, pending.fromTrack, pending.bucket == bucket {
            run.count = pending.count + 1
            run.since = pending.since
        }
        pending = run
        guard run.count >= requiredTrackReadings else { return nil }

        // A confident turn far from the current mood (sudden violence) may come sooner
        // and crossfades quickly, as a live big jump does.
        if reading.confidence >= config.bigJumpConfidence,
           reading.point.distance(to: currentBucket.anchor) >= config.bigJumpDistance,
           dwellAllows(config.bigJumpMinimumDwell, at: now) {
            return trackTurn(to: bucket, reason: .bigJump, transition: .quick, observation: observation, at: now)
        }
        guard dwellAllows(config.trackMinimumDwell, at: now) else {
            // Waits for the dwell; tick() goes ahead then if the track still says so.
            return nil
        }
        return trackTurn(to: bucket, reason: .trackTurn, transition: .gentle, observation: observation, at: now)
    }

    /// Changes to a mood the track turned to, and restarts the evidence from it so a live
    /// reading that follows does not pull the music straight back.
    private func trackTurn(
        to bucket: MoodBucket,
        reason: MoodDecision.Reason,
        transition: MoodDecision.Transition,
        observation: MoodObservation?,
        at now: TimeInterval
    ) -> MoodDecision {
        if let reading = observation?.reading {
            evidence.removeAll()
            evidence.add(reading.evidence(config: config), at: listening.time(at: now), timeConstant: config.evidenceTimeConstant)
        }
        return change(
            to: bucket,
            reason: reason,
            transition: transition,
            observation: observation,
            provisional: false,
            at: now
        )
    }

    /// A reading naming a third mood (neither the rejected one nor the one playing) means
    /// the text has moved on: the rejection ends.
    private func noteRejection(_ named: MoodBucket) {
        guard let rejected = rejectedBucket, named != rejected, named != currentBucket else { return }
        rejectedBucket = nil
    }

    /// Keeps a rejected mood from winning on evidence while the rejection lasts.
    private func dropRejectedEvidence() {
        if let rejectedBucket { evidence.clear(rejectedBucket) }
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
        jumpRun = nil
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
    /// A mood the listener said was wrong, kept out until the text moves on.
    public var rejectedBucket: MoodBucket? = nil
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
