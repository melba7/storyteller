import Foundation
import LofiText

/// One passage from a real book with what the scorer should answer for it: the accuracy
/// test set for scene scoring (`Tools/atmosphere/eval/cases.jsonl`).
///
/// A case is the passage as the scorer sees it (sentences, oldest first; the last one is
/// being read now), the memory the scorer is given with it (the book's world, the
/// places met before and what each sounded like, the scene before this passage), and
/// the expected answer: which place (a known id, a new one, or none), the setting, the
/// main sound and the sounds that must or must not be there, the state of the place,
/// a moment and a one-off sound. Every expectation is optional, so a case can test one
/// thing (a return to a known place, a knock at the door) without pinning the rest.
public struct SceneEvalCase: Codable, Sendable, Hashable {
    /// A place the story has been before this passage, as the memory shows it.
    public struct MemoryPlace: Codable, Sendable, Hashable {
        public var id: String
        public var name: String
        public var setting: StoryScene.Setting
        /// "fireplace soft, oldTown.churchBells faint".
        public var sounds: String
        public var state: String?

        public init(id: String, name: String, setting: StoryScene.Setting, sounds: String, state: String? = nil) {
            self.id = id
            self.name = name
            self.setting = setting
            self.sounds = sounds
            self.state = state
        }
    }

    public struct Memory: Codable, Sendable, Hashable {
        public var world: String?
        /// The scene before this passage: a place id from `places` (shown with the
        /// sounds remembered there) or "none". Nil means the last place listed.
        public var current: String?
        public var places: [MemoryPlace]

        public init(world: String? = nil, current: String? = nil, places: [MemoryPlace] = []) {
            self.world = world
            self.current = current
            self.places = places
        }
    }

    public struct Expect: Codable, Sendable, Hashable {
        /// "new", "none", "any", or the id of a place in the memory.
        public var place: String
        /// indoors, outdoors or vehicle; nil leaves it unchecked.
        public var setting: String?
        /// Families any of which may be the loudest layer.
        public var main: [String]?
        /// Families that must be in the scene at any level.
        public var required: [String]?
        /// Families that must not be in the scene.
        public var forbidden: [String]?
        /// For a family in the scene, the kinds (variant ids) it should be; a plain
        /// family where one of these kinds was expected is a miss.
        public var kinds: [String: [String]]?
        /// Words any of which should be in the state note; an empty list means the
        /// note should be empty.
        public var state: [String]?
        /// "none", "swell" or "hush"; nil leaves it unchecked.
        public var moment: String?
        /// "none" or a one-off sound; nil leaves it unchecked.
        public var oneShot: String?
        /// Whether the scene should be heard at all (confidence at least
        /// ``SceneEvaluator/minimumConfidence`` and at least one sound). Nil means yes
        /// unless `place` is "none".
        public var heard: Bool?

        public init(
            place: String, setting: String? = nil, main: [String]? = nil, required: [String]? = nil,
            forbidden: [String]? = nil, kinds: [String: [String]]? = nil, state: [String]? = nil,
            moment: String? = nil, oneShot: String? = nil, heard: Bool? = nil
        ) {
            self.place = place
            self.setting = setting
            self.main = main
            self.required = required
            self.forbidden = forbidden
            self.kinds = kinds
            self.state = state
            self.moment = moment
            self.oneShot = oneShot
            self.heard = heard
        }
    }

    public var id: String
    public var book: String?
    /// What the passage is, for the report.
    public var about: String?
    /// Which behaviours the case is about ("place", "state", "transition", "oneShot",
    /// "sounds"), for grouping the report.
    public var tags: [String]?
    /// The passage as sentences, oldest first, in one or more chapters. The last
    /// sentence of the last chapter is the one being read now.
    public var chapters: [[String]]
    public var memory: Memory?
    public var expect: Expect

    public init(id: String, book: String? = nil, about: String? = nil, tags: [String]? = nil, chapters: [[String]], memory: Memory? = nil, expect: Expect) {
        self.id = id
        self.book = book
        self.about = about
        self.tags = tags
        self.chapters = chapters
        self.memory = memory
        self.expect = expect
    }

    /// The window the scorer sees: the last sentence of the last chapter and what came
    /// before it.
    public func window() throws -> CausalWindow {
        let guardian = try SpoilerGuard(chapters: chapters)
        guard let last = chapters.last, !last.isEmpty,
              let position = try guardian.position(chapterOrdinal: chapters.count - 1, sentenceIndex: last.count - 1)
        else { throw SceneEvalError.emptyCase(id) }
        return try guardian.window(at: position)
    }

    /// The memory the scorer is given: the places in order (the first listed is the
    /// oldest), the current scene last.
    public func placeMemory() throws -> PlaceMemory {
        guard let memory else { return PlaceMemory() }
        let count = memory.places.count + 2
        let guardian = try SpoilerGuard(chapters: [Array(repeating: "Earlier.", count: count)])
        var entries: [AtmosphereTrack.Entry] = []
        func entry(_ index: Int, scene: StoryScene) throws -> AtmosphereTrack.Entry {
            guard let position = try guardian.position(chapterOrdinal: 0, sentenceIndex: index) else { throw SceneEvalError.emptyCase(id) }
            return AtmosphereTrack.Entry(position: position, sentence: "Earlier.", scene: scene, world: memory.world)
        }
        for (i, place) in memory.places.enumerated() {
            let scene = StoryScene(
                placeID: place.id, placeName: place.name, setting: place.setting,
                layers: Self.layers(place.sounds), confidence: 1, state: place.state
            )
            entries.append(try entry(i, scene: scene))
        }
        let currentID = memory.current ?? memory.places.last?.id
        if let currentID, currentID.lowercased() != "none" {
            guard let place = memory.places.first(where: { $0.id == currentID }) else { throw SceneEvalError.unknownCurrent(id, currentID) }
            let scene = StoryScene(
                placeID: place.id, placeName: place.name, setting: place.setting,
                layers: Self.layers(place.sounds), confidence: 1, state: place.state
            )
            entries.append(try entry(memory.places.count, scene: scene))
        } else if memory.current != nil {
            entries.append(try entry(memory.places.count, scene: .silent))
        }
        return PlaceMemory(entries: entries)
    }

    /// "fireplace soft, oldTown.churchBells faint" as layers. Unknown words are skipped.
    public static func layers(_ text: String) -> [SceneLayer] {
        text.split(separator: ",").compactMap { part -> SceneLayer? in
            let words = part.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let key = words.first else { return nil }
            let level = words.dropFirst().first.flatMap { AmbientLevel(lenient: $0) } ?? .soft
            let pieces = key.split(separator: ".", maxSplits: 1).map(String.init)
            guard let sound = AmbientSound(rawValue: pieces[0]) ?? AmbientSound(lenient: pieces[0]) else { return nil }
            return SceneLayer(sound, level, variant: pieces.count > 1 ? pieces[1] : nil)
        }
    }

    /// Reads a JSON Lines file of cases; blank lines and lines starting with # are skipped.
    public static func load(from url: URL) throws -> [SceneEvalCase] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        var cases: [SceneEvalCase] = []
        var seen = Set<String>()
        for (number, line) in text.split(whereSeparator: \.isNewline).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            do {
                let item = try decoder.decode(SceneEvalCase.self, from: Data(trimmed.utf8))
                guard seen.insert(item.id).inserted else { throw SceneEvalError.duplicate(item.id) }
                cases.append(item)
            } catch let error as SceneEvalError {
                throw error
            } catch {
                throw SceneEvalError.badLine(number + 1, "\(error)")
            }
        }
        return cases
    }
}

public enum SceneEvalError: Error, CustomStringConvertible {
    case emptyCase(String)
    case unknownCurrent(String, String)
    case duplicate(String)
    case badLine(Int, String)

    public var description: String {
        switch self {
        case let .emptyCase(id): "case \(id) has no sentences"
        case let .unknownCurrent(id, place): "case \(id): current place \(place) is not in its memory"
        case let .duplicate(id): "two cases are called \(id)"
        case let .badLine(line, detail): "line \(line): \(detail)"
        }
    }
}

/// What the scorer answered for a case, kept so a run can be re-checked without
/// asking Claude again (`--replay`).
public struct SceneEvalAnswer: Codable, Sendable, Hashable {
    /// A known place's id, "new" or "none".
    public var place: String
    public var placeName: String?
    public var setting: String
    public var state: String?
    /// "fireplace soft", loudest first.
    public var sounds: [String]
    public var moment: String?
    public var oneShot: String?
    public var quote: String?
    public var confidence: Double
    public var world: String?

    public init(_ answer: SceneAnswer) {
        switch answer.place {
        case let .known(id): place = id
        case .new: place = "new"
        case .none: place = "none"
        }
        placeName = answer.scene.placeName
        setting = answer.scene.setting.rawValue
        state = answer.scene.state
        sounds = answer.scene.layers.map { "\($0.key) \($0.level.rawValue)" }
        moment = answer.scene.moment?.rawValue
        oneShot = answer.oneShot?.sound.rawValue
        quote = answer.oneShot?.quote
        confidence = answer.scene.confidence
        world = answer.world
    }

    /// The answer as a scene again, for re-checking.
    public var sceneAnswer: SceneAnswer {
        let place: SceneAnswer.Place
        switch self.place {
        case "none": place = .none
        case "new": place = .new(placeName ?? "")
        default: place = .known(self.place)
        }
        let scene = StoryScene(
            placeID: nil, placeName: placeName, setting: StoryScene.Setting(rawValue: setting) ?? .unclear,
            layers: SceneEvalCase.layers(sounds.joined(separator: ", ")), confidence: confidence,
            moment: moment.flatMap { StoryScene.Moment(rawValue: $0) }, state: state
        )
        let mention = oneShot.flatMap { OneShotSound(rawValue: $0) }.map { OneShotMention(sound: $0, quote: quote ?? "") }
        return SceneAnswer(place: place, scene: scene, world: world, oneShot: mention)
    }
}

/// One case's result: the answer and which expectations it met.
public struct SceneEvalResult: Codable, Sendable, Hashable {
    public var id: String
    public var answer: SceneEvalAnswer?
    public var error: String?
    /// Check name to pass or fail, only for the checks the case asks for.
    public var checks: [String: Bool]
    /// Every check the case asks for passed.
    public var passed: Bool

    public init(id: String, answer: SceneEvalAnswer?, error: String? = nil, checks: [String: Bool]) {
        self.id = id
        self.answer = answer
        self.error = error
        self.checks = checks
        passed = error == nil && checks.values.allSatisfy { $0 }
    }

    public static func load(from url: URL) throws -> [SceneEvalResult] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        return try text.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return try decoder.decode(SceneEvalResult.self, from: Data(trimmed.utf8))
        }
    }
}

/// Runs the cases through an engine and checks the answers.
public enum SceneEvaluator {
    /// Below this the director skips an entry (see `AtmosphereDirector`).
    public static let minimumConfidence = 0.35

    /// The checks in the order the report lists them.
    public static let checkNames = ["place", "setting", "main", "required", "forbidden", "kinds", "state", "moment", "oneShot", "heard"]

    /// Which expectations the answer meets. Only the checks the case asks for are in
    /// the result.
    public static func checks(for item: SceneEvalCase, answer: SceneAnswer, window: CausalWindow?) -> [String: Bool] {
        let expect = item.expect
        let scene = answer.scene
        var checks: [String: Bool] = [:]
        let families = Set(scene.layers.map(\.sound.rawValue))

        switch expect.place.lowercased() {
        case "any": break
        case "none": checks["place"] = answer.place == .none
        case "new":
            if case .new = answer.place { checks["place"] = true } else { checks["place"] = false }
        default: checks["place"] = answer.place == .known(expect.place)
        }
        if let setting = expect.setting {
            checks["setting"] = scene.setting.rawValue == setting.lowercased()
        }
        if let main = expect.main {
            checks["main"] = scene.layers.first.map { main.contains($0.sound.rawValue) } ?? false
        }
        if let required = expect.required {
            checks["required"] = required.allSatisfy { families.contains($0) }
        }
        if let forbidden = expect.forbidden {
            checks["forbidden"] = !forbidden.contains { families.contains($0) }
        }
        if let kinds = expect.kinds, !kinds.isEmpty {
            var ok = true
            for (family, accepted) in kinds {
                guard let layer = scene.layers.first(where: { $0.sound.rawValue == family }) else { continue }
                if let variant = layer.variant {
                    if !accepted.contains(variant) { ok = false }
                } else if !accepted.isEmpty {
                    ok = false
                }
            }
            checks["kinds"] = ok
        }
        if let words = expect.state {
            let note = (scene.state ?? "").lowercased()
            checks["state"] = words.isEmpty ? note.isEmpty : words.contains { note.contains($0.lowercased()) }
        }
        if let moment = expect.moment {
            checks["moment"] = moment.lowercased() == "none" ? scene.moment == nil : scene.moment?.rawValue == moment.lowercased()
        }
        if let oneShot = expect.oneShot {
            if oneShot.lowercased() == "none" {
                checks["oneShot"] = answer.oneShot == nil
            } else if let mention = answer.oneShot, mention.sound.rawValue == oneShot {
                // The builder keeps a cue only when its words are found in the passage.
                checks["oneShot"] = window.map { mention.locate(in: $0) != nil } ?? true
            } else {
                checks["oneShot"] = false
            }
        }
        let heard = expect.heard ?? (expect.place.lowercased() != "none")
        if heard {
            checks["heard"] = scene.confidence >= minimumConfidence && !scene.isSilent
        }
        return checks
    }

    /// Scores one case.
    public static func evaluate(_ item: SceneEvalCase, engine: any SceneEngine) async -> SceneEvalResult {
        do {
            let window = try item.window()
            let memory = try item.placeMemory()
            let answer = try await engine.scene(for: window, memory: memory)
            return SceneEvalResult(id: item.id, answer: SceneEvalAnswer(answer), checks: checks(for: item, answer: answer, window: window))
        } catch {
            return SceneEvalResult(id: item.id, answer: nil, error: "\(error)", checks: [:])
        }
    }

    /// Scores the cases, several at a time, in the cases' order.
    public static func run(
        _ cases: [SceneEvalCase], engine: any SceneEngine, concurrency: Int = 4,
        onResult: (@Sendable (SceneEvalResult, Int) -> Void)? = nil
    ) async -> [SceneEvalResult] {
        var results = [SceneEvalResult?](repeating: nil, count: cases.count)
        let width = max(1, concurrency)
        var done = 0
        await withTaskGroup(of: (Int, SceneEvalResult).self) { group in
            var next = 0
            func launch() {
                guard next < cases.count else { return }
                let index = next
                next += 1
                group.addTask { (index, await evaluate(cases[index], engine: engine)) }
            }
            for _ in 0..<width { launch() }
            while let (index, result) = await group.next() {
                results[index] = result
                done += 1
                onResult?(result, done)
                launch()
            }
        }
        return results.compactMap { $0 }
    }

    /// Re-checks saved answers against the cases (after a change to a case or the checks).
    public static func replay(_ cases: [SceneEvalCase], results: [SceneEvalResult]) -> [SceneEvalResult] {
        let saved = Dictionary(results.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return cases.compactMap { item in
            guard let old = saved[item.id] else { return nil }
            guard let answer = old.answer else { return old }
            let window = try? item.window()
            return SceneEvalResult(id: item.id, answer: answer, checks: checks(for: item, answer: answer.sceneAnswer, window: window))
        }
    }

    public struct Summary: Sendable, Hashable {
        public var cases = 0
        public var passed = 0
        public var errors = 0
        /// Check name to (passed, asked).
        public var byCheck: [String: (passed: Int, asked: Int)] = [:]
        /// Tag to (passed, cases).
        public var byTag: [String: (passed: Int, cases: Int)] = [:]

        public static func == (a: Summary, b: Summary) -> Bool {
            a.cases == b.cases && a.passed == b.passed && a.errors == b.errors
                && a.byCheck.mapValues { [$0.passed, $0.asked] } == b.byCheck.mapValues { [$0.passed, $0.asked] }
                && a.byTag.mapValues { [$0.passed, $0.cases] } == b.byTag.mapValues { [$0.passed, $0.cases] }
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(cases)
            hasher.combine(passed)
        }
    }

    public static func summary(_ cases: [SceneEvalCase], results: [SceneEvalResult]) -> Summary {
        let byID = Dictionary(cases.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var summary = Summary()
        for result in results {
            summary.cases += 1
            if result.error != nil { summary.errors += 1 }
            if result.passed { summary.passed += 1 }
            for (name, ok) in result.checks {
                var entry = summary.byCheck[name] ?? (0, 0)
                entry.asked += 1
                if ok { entry.passed += 1 }
                summary.byCheck[name] = entry
            }
            for tag in byID[result.id]?.tags ?? [] {
                var entry = summary.byTag[tag] ?? (0, 0)
                entry.cases += 1
                if result.passed { entry.passed += 1 }
                summary.byTag[tag] = entry
            }
        }
        return summary
    }

    /// The report: totals, each check, each tag, then every case that missed something.
    public static func report(_ cases: [SceneEvalCase], results: [SceneEvalResult], engineID: String, verbose: Bool = false) -> String {
        let byID = Dictionary(cases.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let summary = summary(cases, results: results)
        var lines: [String] = []
        lines.append("\(engineID): \(summary.passed) of \(summary.cases) cases pass every check" + (summary.errors > 0 ? ", \(summary.errors) failed to score" : ""))
        for name in checkNames {
            guard let entry = summary.byCheck[name] else { continue }
            let share = 100 * Double(entry.passed) / Double(max(1, entry.asked))
            lines.append("  " + name.padding(toLength: 10, withPad: " ", startingAt: 0) + String(format: " %3d of %3d  %3.0f%%", entry.passed, entry.asked, share))
        }
        for (tag, entry) in summary.byTag.sorted(by: { $0.key < $1.key }) {
            lines.append("  tag " + tag.padding(toLength: 10, withPad: " ", startingAt: 0) + String(format: " %3d of %3d cases", entry.passed, entry.cases))
        }
        for result in results where verbose || !result.passed {
            let item = byID[result.id]
            let about = item?.about.map { ": \($0)" } ?? ""
            if let error = result.error {
                lines.append("- \(result.id)\(about)\n    error: \(error)")
                continue
            }
            let missed = checkNames.filter { result.checks[$0] == false }
            let mark = result.passed ? "+" : "-"
            lines.append("\(mark) \(result.id)\(about)" + (missed.isEmpty ? "" : "  missed: " + missed.joined(separator: ", ")))
            if let answer = result.answer {
                let place = answer.place == "new" ? "new \"\(answer.placeName ?? "")\"" : answer.place
                let state = answer.state.map { " (\($0))" } ?? ""
                let extras = [answer.moment.map { "moment \($0)" }, answer.oneShot.map { "one-off \($0) \"\(answer.quote ?? "")\"" }].compactMap { $0 }
                lines.append("    got: \(place) [\(answer.setting)]\(state): " + (answer.sounds.isEmpty ? "no sounds" : answer.sounds.joined(separator: ", "))
                    + String(format: " conf %.2f", answer.confidence) + (extras.isEmpty ? "" : "; " + extras.joined(separator: "; ")))
            }
            if let expect = item?.expect, !missed.isEmpty {
                var want: [String] = []
                if missed.contains("place") { want.append("place \(expect.place)") }
                if missed.contains("setting"), let s = expect.setting { want.append("setting \(s)") }
                if missed.contains("main"), let m = expect.main { want.append("main \(m.joined(separator: "|"))") }
                if missed.contains("required"), let r = expect.required { want.append("required \(r.joined(separator: ","))") }
                if missed.contains("forbidden"), let f = expect.forbidden { want.append("forbidden \(f.joined(separator: ","))") }
                if missed.contains("kinds"), let k = expect.kinds { want.append("kinds " + k.map { "\($0.key).\($0.value.joined(separator: "|"))" }.joined(separator: " ")) }
                if missed.contains("state"), let s = expect.state { want.append("state ~ \(s.joined(separator: "|"))") }
                if missed.contains("moment"), let m = expect.moment { want.append("moment \(m)") }
                if missed.contains("oneShot"), let o = expect.oneShot { want.append("one-off \(o)") }
                if missed.contains("heard") { want.append("heard (confidence >= \(minimumConfidence), a sound)") }
                lines.append("    want: " + want.joined(separator: "; "))
            }
        }
        return lines.joined(separator: "\n")
    }
}
