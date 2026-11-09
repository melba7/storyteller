import Foundation
import LofiMood
import LofiScoreCore
import LofiText

/// Engines by name, for `--engine`:
///
///     lexicon                  hand-written cues (runs anywhere)
///     nltagger                 NLTagger sentiment + cues (Apple platforms)
///     fm                       Apple's on-device model, general use case
///     fm-tagging               Apple's on-device model, content-tagging adapter
///     fast:<model>             Create ML classifier (.mlmodel or .mlmodelc)
///     fm+fast:<model>          on-device model, falling back to the classifier
///     recommended[:<model>]    what the app would pick on this machine
enum EngineFactory {
    static let names = ["lexicon", "nltagger", "fm", "fm-tagging", "fast:<model>", "fm+fast:<model>", "recommended[:<model>]"]

    static func make(_ name: String) throws -> any MoodEngine {
        let (base, argument) = split(name)
        switch base {
        case "lexicon":
            return LexiconMoodEngine()
        case "nltagger":
            #if canImport(NaturalLanguage)
            return NLTaggerMoodEngine()
            #else
            throw unavailable(name, "NaturalLanguage is not available on this platform")
            #endif
        case "fm", "fm-tagging":
            return try foundationModels(tagging: base == "fm-tagging")
        case "fast":
            return try classifier(argument, name: name)
        case "fm+fast":
            return FallbackMoodEngine(primary: try foundationModels(tagging: false), fallback: try classifier(argument, name: name))
        case "recommended":
            return MoodEngineCatalog.recommendedEngine(classifierModelURL: argument.map { URL(fileURLWithPath: $0) })
        default:
            throw unavailable(name, "unknown engine; try one of \(names.joined(separator: ", "))")
        }
    }

    /// One line per engine saying whether it can run here.
    static func availabilityReport() -> [String] {
        var lines = ["lexicon: available"]
        #if canImport(NaturalLanguage)
        lines.append("nltagger: available")
        #else
        lines.append("nltagger: unavailable (no NaturalLanguage on this platform)")
        #endif
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            let a = FoundationModelsMoodEngine.availability()
            lines.append("fm: \(a.isAvailable ? "available" : "unavailable (\(a.reason))")")
        } else {
            lines.append("fm: unavailable (needs macOS 26 or iOS 26)")
        }
        #else
        lines.append("fm: unavailable (SDK has no FoundationModels)")
        #endif
        #if canImport(NaturalLanguage) && canImport(CoreML)
        lines.append("fast: available when given a model (fast:<path>)")
        #else
        lines.append("fast: unavailable (no CoreML on this platform)")
        #endif
        lines.append("recommended here: \(MoodEngineCatalog.recommendedEngine().id)")
        return lines
    }

    private static func split(_ name: String) -> (String, String?) {
        guard let colon = name.firstIndex(of: ":") else { return (name, nil) }
        return (String(name[..<colon]), String(name[name.index(after: colon)...]))
    }

    private static func foundationModels(tagging: Bool) throws -> any MoodEngine {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            let a = FoundationModelsMoodEngine.availability()
            guard a.isAvailable else { throw unavailable("fm", a.reason) }
            return FoundationModelsMoodEngine(variant: tagging ? .contentTagging : .general)
        }
        throw unavailable("fm", "needs macOS 26 or iOS 26")
        #else
        throw unavailable("fm", "this SDK has no FoundationModels")
        #endif
    }

    private static func classifier(_ path: String?, name: String) throws -> any MoodEngine {
        guard let path, !path.isEmpty else { throw unavailable(name, "give the model path, e.g. fast:Models/LofiMood.mlmodel") }
        #if canImport(NaturalLanguage) && canImport(CoreML)
        let url = URL(fileURLWithPath: path)
        let version = url.deletingPathExtension().lastPathComponent
        return try ClassifierMoodEngine(modelURL: url, version: version)
        #else
        throw unavailable(name, "CoreML is not available on this platform")
        #endif
    }

    private static func unavailable(_ name: String, _ reason: String) -> MoodEngineError {
        .unavailable("\(name): \(reason)")
    }
}

/// Wraps an engine and remembers how long each reading took.
final class TimedEngine: MoodEngine, @unchecked Sendable {
    let inner: any MoodEngine
    private let lock = NSLock()
    private var last: Double?

    init(_ inner: any MoodEngine) { self.inner = inner }

    var id: String { inner.id }

    func reading(for window: CausalWindow) async throws -> MoodReading {
        let start = now()
        defer { record((now() - start) * 1000) }
        return try await inner.reading(for: window)
    }

    private func record(_ elapsed: Double) {
        lock.lock(); last = elapsed; lock.unlock()
    }

    /// The latency of the most recent reading, then forgets it (cache hits take none).
    func takeLatency() -> Double? {
        lock.lock(); defer { lock.unlock() }
        let value = last
        last = nil
        return value
    }
}
