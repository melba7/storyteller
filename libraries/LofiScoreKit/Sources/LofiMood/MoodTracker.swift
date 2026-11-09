import Foundation
import LofiScoreCore
import LofiText

/// Ties the text side together for one open book: the player reports clip
/// changes, the tracker decides when to take a reading, builds the causal
/// window, runs the engine, and hands back a `MoodObservation` for the director.
///
/// Adapter sketch (Expo app):
///
///     AudiobookPlayerActor.shared.observeClipChanged { clip, _ in
///         clipEvents.yield(clip)   // an AsyncStream, consumed in order
///     }
///     for await clip in clipEvents {
///         if let observation = await tracker.clipChanged(
///             textResource: clip.textResource, fragmentId: clip.fragmentId,
///             audioResource: clip.relativeUrl.path, clipBegin: clip.start) {
///             director.receive(observation)
///         }
///     }
///
/// Feed clip changes in the order the player reports them (an `AsyncStream`
/// is the simplest way); the tracker itself never reorders results:
/// a result that a newer reading or a seek has overtaken is dropped.
public actor MoodTracker {
    public let engine: any MoodEngine
    private let spoilerGuard: SpoilerGuard
    private var cadence: ReadingCadence
    private let clock: @Sendable () -> Double

    private var issued = 0
    private var delivered = 0
    private var stretch = 0
    private var cache: [String: MoodReading] = [:]
    private var cacheOrder: [String] = []
    private let cacheLimit: Int

    /// Readings that failed, for the debug overlay and the eval.
    public private(set) var failures: [String] = []

    public init(
        spoilerGuard: SpoilerGuard,
        engine: any MoodEngine,
        cadence: ReadingCadence.Configuration = .default,
        cacheLimit: Int = 2_000,
        clock: @escaping @Sendable () -> Double = MoodTracker.uptimeSeconds
    ) {
        self.spoilerGuard = spoilerGuard
        self.engine = engine
        self.cadence = ReadingCadence(configuration: cadence)
        self.cacheLimit = cacheLimit
        self.clock = clock
    }

    /// Seconds from a monotonic clock.
    public static let uptimeSeconds: @Sendable () -> Double = {
        ProcessInfo.processInfo.systemUptime
    }

    /// Call for every clip the player starts. Returns an observation when a
    /// reading was taken for this clip and nothing newer has overtaken it.
    public func clipChanged(
        textResource: String,
        fragmentId: String,
        audioResource: String? = nil,
        clipBegin: Double? = nil,
        isSeek: Bool = false
    ) async -> MoodObservation? {
        let position: SentencePosition?
        do {
            position = try spoilerGuard.position(
                textResource: textResource,
                fragmentId: fragmentId,
                audioResource: audioResource,
                clipBegin: clipBegin
            )
        } catch {
            record("locate \(fragmentId): \(error)")
            return nil
        }
        guard let position else { return nil }
        return await sentenceStarted(position, isSeek: isSeek)
    }

    /// Same as `clipChanged`, for adapters that already have a position.
    public func sentenceStarted(_ position: SentencePosition, isSeek: Bool = false) async -> MoodObservation? {
        guard let trigger = cadence.observe(position, at: clock(), seek: isSeek) else { return nil }

        issued += 1
        let ticket = issued
        if trigger == .start || trigger == .seek { stretch += 1 }
        let myStretch = stretch

        let reading: MoodReading
        let key = "\(engine.id)|\(position.chapterOrdinal):\(position.sentenceIndex)"
        if let cached = cache[key] {
            reading = cached
        } else {
            do {
                let window = try spoilerGuard.window(at: position)
                reading = try await engine.reading(for: window)
            } catch {
                record("\(position): \(error)")
                return nil
            }
            remember(reading, for: key)
        }

        // Drop results that a seek or a newer reading overtook while the engine ran.
        guard myStretch == stretch, ticket > delivered else { return nil }
        delivered = ticket
        return MoodObservation(
            reading: reading,
            chapterOrdinal: position.chapterOrdinal,
            sentenceIndex: position.sentenceIndex,
            globalSentenceIndex: position.globalIndex,
            trigger: trigger
        )
    }

    /// Forget the cadence state: the next clip starts a new stretch with a
    /// `.start` reading. Call after a long pause or when the book reopens.
    public func reset() {
        cadence.reset()
        stretch += 1
    }

    private func remember(_ reading: MoodReading, for key: String) {
        cache[key] = reading
        cacheOrder.append(key)
        if cacheOrder.count > cacheLimit {
            cache[cacheOrder.removeFirst()] = nil
        }
    }

    private func record(_ failure: String) {
        failures.append(failure)
        if failures.count > 50 { failures.removeFirst() }
    }
}

/// Picks the engine for this device, following the plan's defaults: Apple's
/// on-device model where available (falling back to the Fast engine on a
/// refusal or parse failure), otherwise the Fast classifier if it is bundled,
/// otherwise the NLTagger baseline (or the lexicon on non-Apple platforms).
public enum MoodEngineCatalog {
    public static func recommendedEngine(classifierModelURL: URL? = nil) -> any MoodEngine {
        let fast: any MoodEngine = fastEngine(classifierModelURL: classifierModelURL)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *), FoundationModelsMoodEngine.availability().isAvailable {
            return FallbackMoodEngine(primary: FoundationModelsMoodEngine(), fallback: fast)
        }
        #endif
        return fast
    }

    /// The best engine that never needs Apple Intelligence.
    public static func fastEngine(classifierModelURL: URL? = nil) -> any MoodEngine {
        #if canImport(NaturalLanguage)
        let baseline: any MoodEngine = NLTaggerMoodEngine()
        #else
        let baseline: any MoodEngine = LexiconMoodEngine()
        #endif
        #if canImport(NaturalLanguage) && canImport(CoreML)
        if let url = classifierModelURL, let classifier = try? ClassifierMoodEngine(modelURL: url) {
            return FallbackMoodEngine(primary: classifier, fallback: baseline)
        }
        #endif
        return baseline
    }
}
