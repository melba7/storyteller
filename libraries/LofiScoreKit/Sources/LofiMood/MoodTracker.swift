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
    private var cache: [String: (reading: MoodReading, source: ReadingSource)] = [:]
    private var cacheOrder: [String] = []
    private let cacheLimit: Int

    /// Readings that failed, for the debug overlay and the eval.
    public private(set) var failures: [String] = []

    /// - Parameter cadence: how often to read. `nil` picks
    ///   `MoodEngineCatalog.cadence(for:)` for the engine.
    public init(
        spoilerGuard: SpoilerGuard,
        engine: any MoodEngine,
        cadence: ReadingCadence.Configuration? = nil,
        cacheLimit: Int = 2_000,
        clock: @escaping @Sendable () -> Double = MoodTracker.uptimeSeconds
    ) {
        self.spoilerGuard = spoilerGuard
        self.engine = engine
        self.cadence = ReadingCadence(configuration: cadence ?? MoodEngineCatalog.cadence(for: engine))
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
        let source: ReadingSource
        let key = "\(engine.id)|\(position.chapterOrdinal):\(position.sentenceIndex)"
        if let cached = cache[key] {
            (reading, source) = cached
        } else {
            do {
                let window = try spoilerGuard.window(at: position)
                if let tracked = engine as? TrackedMoodEngine, let fromTrack = tracked.trackReading(for: window) {
                    (reading, source) = (fromTrack, .track)
                } else {
                    (reading, source) = (try await engine.reading(for: window), .live)
                }
            } catch {
                record("\(position): \(error)")
                return nil
            }
            // Track readings are not cached: the track may grow while the
            // book plays, and a lookup is cheaper than the cache anyway.
            if source == .live { remember(reading, for: key) }
        }

        // Drop results that a seek or a newer reading overtook while the engine ran.
        guard myStretch == stretch, ticket > delivered else { return nil }
        delivered = ticket
        return MoodObservation(
            reading: reading,
            chapterOrdinal: position.chapterOrdinal,
            sentenceIndex: position.sentenceIndex,
            globalSentenceIndex: position.globalIndex,
            trigger: trigger,
            source: source
        )
    }

    /// Forget the cadence state: the next clip starts a new stretch with a
    /// `.start` reading. Call after a long pause or when the book reopens.
    public func reset() {
        cadence.reset()
        stretch += 1
    }

    private func remember(_ reading: MoodReading, for key: String) {
        cache[key] = (reading, .live)
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

/// Picks engines for the app, following the choices recorded in
/// `Docs/MoodDetection.md`: the Fast classifier is the default; a book's
/// Claude mood track, where one exists, is played over it; Apple's on-device
/// model is an opt-in only (it agreed with the reference labels less than the
/// lexicon did).
public enum MoodEngineCatalog {
    /// The live engine for this device: the Fast classifier if it is bundled,
    /// otherwise the NLTagger baseline (or the lexicon on non-Apple platforms).
    public static func recommendedEngine(classifierModelURL: URL? = nil) -> any MoodEngine {
        fastEngine(classifierModelURL: classifierModelURL)
    }

    /// What plays during narration: the book's mood track where it reaches,
    /// and the recommended live engine everywhere else (or alone, with no track).
    public static func playbackEngine(track: MoodTrackStore?, classifierModelURL: URL? = nil) -> any MoodEngine {
        let live = recommendedEngine(classifierModelURL: classifierModelURL)
        guard let track else { return live }
        return TrackedMoodEngine(store: track, fallback: live)
    }

    /// Apple's on-device model with the Fast engine behind it, for an opt-in
    /// setting; nil where the model is not available.
    public static func onDeviceModelEngine(classifierModelURL: URL? = nil) -> (any MoodEngine)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *), FoundationModelsMoodEngine.availability().isAvailable {
            return FallbackMoodEngine(primary: FoundationModelsMoodEngine(), fallback: fastEngine(classifierModelURL: classifierModelURL))
        }
        #endif
        return nil
    }

    /// How often `MoodTracker` should read with this engine. Track lookups and
    /// the Fast classifier answer in milliseconds, so they read every
    /// sentence; Apple's on-device model takes a second or more per reading
    /// and keeps the plan's 4-sentence, 20-second cadence.
    public static func cadence(for engine: any MoodEngine) -> ReadingCadence.Configuration {
        usesOnDeviceModel(engine) ? .default : .everySentence
    }

    static func usesOnDeviceModel(_ engine: any MoodEngine) -> Bool {
        switch engine {
        case let tracked as TrackedMoodEngine: usesOnDeviceModel(tracked.fallback)
        case let chained as FallbackMoodEngine: usesOnDeviceModel(chained.primary) || usesOnDeviceModel(chained.fallback)
        default: engine.id.hasPrefix("fm.")
        }
    }

    /// The best engine that never needs Apple Intelligence or the network.
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
