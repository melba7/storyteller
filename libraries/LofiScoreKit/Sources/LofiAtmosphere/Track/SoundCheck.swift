import Foundation

/// One spot of a book for the sound check: a short listening test that plays a few
/// different kinds of scene under the narration and asks whether each one can be heard.
public struct SoundCheckSpot: Sendable, Hashable {
    /// What kind of scene the spot tests, judged from its main (loudest) sound.
    public enum Kind: String, CaseIterable, Sendable {
        /// Room tone, a hushed room, a clock, an electric hum or an empty hall.
        case quietRoom
        /// A sound at `loud`, or a crowd at `full`.
        case loud
        /// Outdoors, with nature or a town as the main sound.
        case outdoors
        case water
        case weather
        /// A train, a ship, a carriage.
        case travel
        /// A one-off sound, such as a knock at the door.
        case oneOff
        /// Any other scene, picked for a main sound the check has not played yet.
        case other
    }

    /// A sound the listener should hear: a layer key ("river.runningTap") and its level,
    /// or a one-off's name ("doorKnock") with no level.
    public struct Sound: Sendable, Hashable {
        public let key: String
        public let level: AmbientLevel?

        public init(key: String, level: AmbientLevel?) {
            self.key = key
            self.level = level
        }
    }

    /// The sentence the stop starts at. For a one-off, the cue's sentence: the host moves
    /// the start a few seconds earlier, so the one-off is allowed to play.
    public let globalIndex: Int
    /// The last sentence the stop may play: the scene holds until here, and it is before
    /// the limit the spots were picked under.
    public let lastIndex: Int
    public let kind: Kind
    /// Main sound first.
    public let sounds: [Sound]
    public let placeName: String?
    /// For a one-off stop, the sentence of the one-off.
    public let cueIndex: Int?

    public init(globalIndex: Int, lastIndex: Int, kind: Kind, sounds: [Sound], placeName: String?, cueIndex: Int?) {
        self.globalIndex = globalIndex
        self.lastIndex = lastIndex
        self.kind = kind
        self.sounds = sounds
        self.placeName = placeName
        self.cueIndex = cueIndex
    }
}

/// Picks the sound check's spots from a book's atmosphere track.
///
/// A spot is a run of sentences where the same main sound (same kind, same level) plays
/// steadily at its full level, the way ``AtmosphereDirector`` plays the track: a confident
/// scene, no transition or moment cutting in, no chapter start (the sounds dip there until
/// the new chapter has a scene of its own) and no one-off. Runs of at least
/// ``minRunSentences`` qualify.
public enum SoundCheck {
    static let sceneKinds: [SoundCheckSpot.Kind] = [.quietRoom, .loud, .outdoors, .water, .weather, .travel]
    static let quietRoomSounds: Set<AmbientSound> = [.roomTone, .hushedRoom, .clock, .electricHum, .emptyHall]
    /// About 20 s of narration.
    public static let minRunSentences = 8

    /// Up to `count` spots, all ending before `limit` (the first sentence not yet heard),
    /// returned in book order. One place goes to a one-off when the book has one before the
    /// limit and `oneOffs` is on; the rest go to one steady scene per kind, then to steady
    /// scenes with a main sound not played yet, then to the longest run of each kind that
    /// has no steady one. Among steady runs it prefers a level no spot covers yet, then a
    /// main sound not picked yet, then the earliest, so the same spots come back on the
    /// next run.
    public static func spots(
        in track: AtmosphereTrack,
        before limit: Int,
        count: Int = 6,
        oneOffs: Bool = true,
        oneOffAllowed: (AtmosphereTrack.Cue) -> Bool = { _ in true },
        minConfidence: Double = AtmosphereConfig().minConfidence,
        maxLag: Int = AtmosphereConfig().maxLagSentences
    ) -> [SoundCheckSpot] {
        guard count > 0, limit > 0 else { return [] }
        let cues = track.cues.filter { $0.globalIndex + 1 < limit }
        let cue = oneOffs ? cues.first { oneOffAllowed($0) } : nil
        let runs = Self.runs(
            in: track, before: limit, minConfidence: minConfidence, maxLag: maxLag, splitAt: Set(cues.map(\.globalIndex))
        )

        var picked: [SoundCheckSpot] = []
        let sceneSlots = count - (cue == nil ? 0 : 1)
        func free(_ run: Run) -> Bool {
            !picked.contains { $0.globalIndex <= run.last && run.first <= $0.lastIndex }
        }
        func best(_ candidates: [Run]) -> Run? {
            let levels = Set(picked.compactMap { $0.sounds.first?.level })
            let keys = Set(picked.compactMap { $0.sounds.first?.key })
            return candidates.min { a, b in
                let ra = (levels.contains(a.main.level) ? 1 : 0, keys.contains(a.main.key) ? 1 : 0, a.first)
                let rb = (levels.contains(b.main.level) ? 1 : 0, keys.contains(b.main.key) ? 1 : 0, b.first)
                return ra < rb
            }
        }
        func spot(_ run: Run, _ kind: SoundCheckSpot.Kind) -> SoundCheckSpot {
            SoundCheckSpot(
                globalIndex: run.first, lastIndex: run.last, kind: kind,
                sounds: run.scene.layers.map { .init(key: $0.key, level: $0.level) },
                placeName: run.scene.placeName, cueIndex: nil
            )
        }

        let steady = runs.filter { $0.length >= minRunSentences }
        for kind in sceneKinds where picked.count < sceneSlots {
            if let choice = best(steady.filter { free($0) && matches($0.scene, kind) }) { picked.append(spot(choice, kind)) }
        }
        while picked.count < sceneSlots {
            let keys = Set(picked.compactMap { $0.sounds.first?.key })
            guard let choice = best(steady.filter { free($0) && !keys.contains($0.main.key) }) else { break }
            picked.append(spot(choice, .other))
        }
        // Places still free go to the kinds with no steady run: their longest one, the
        // earliest on a tie. A short stop tells less, so a steady one goes first.
        for kind in sceneKinds where picked.count < sceneSlots && !picked.contains(where: { $0.kind == kind }) {
            let ofKind = runs.filter { free($0) && matches($0.scene, kind) }
            if let choice = ofKind.min(by: { ($1.length, $0.first) < ($0.length, $1.first) }) { picked.append(spot(choice, kind)) }
        }
        if let cue {
            picked.append(SoundCheckSpot(
                globalIndex: cue.globalIndex, lastIndex: cue.globalIndex + 1, kind: .oneOff,
                sounds: [.init(key: cue.sound.rawValue, level: nil)], placeName: nil, cueIndex: cue.globalIndex
            ))
        }
        return picked.sorted { $0.globalIndex < $1.globalIndex }
    }

    struct Run {
        let first: Int
        let last: Int
        let scene: StoryScene
        var main: SceneLayer { scene.layers[0] }
        var length: Int { last - first + 1 }
    }

    /// Steady runs of a main sound as the director plays them, all ending before `limit`.
    ///
    /// Only confident entries count: the director passes over the others. An entry plays at
    /// its full level from its own sentence until the next confident entry, the next chapter
    /// start (the sounds dip there until the new chapter has a scene of its own) or `maxLag`
    /// sentences on, whichever comes first. Entries that follow on with the same main sound
    /// and level join into one run, unless the later one cuts in with a transition or a
    /// moment. Runs are then cut around one-offs. Each run gives up its last sentence: the
    /// stop is ended while that sentence plays, so nothing after the run is ever heard.
    static func runs(in track: AtmosphereTrack, before limit: Int, minConfidence: Double, maxLag: Int, splitAt cues: Set<Int>) -> [Run] {
        let entries = track.entries.filter { $0.globalIndex < limit && $0.scene.confidence >= minConfidence }
        /// The last sentence entry `i` plays at its full level.
        func lastPlayed(_ i: Int) -> Int {
            let index = entries[i].globalIndex
            var last = min(limit - 1, index + maxLag)
            if i + 1 < entries.count { last = min(last, entries[i + 1].globalIndex - 1) }
            if let chapter = track.chapterStarts.first(where: { $0 > index }) { last = min(last, chapter - 1) }
            return last
        }
        var spans: [Run] = []
        var i = 0
        while i < entries.count {
            let start = entries[i]
            guard let main = start.scene.layers.first else { i += 1; continue }
            var last = lastPlayed(i)
            var j = i + 1
            while j < entries.count, entries[j].globalIndex == last + 1 {
                let next = entries[j].scene
                guard next.transition == nil, next.moment == nil,
                      next.layers.first?.key == main.key, next.layers.first?.level == main.level else { break }
                last = lastPlayed(j)
                j += 1
            }
            if last >= start.globalIndex { spans.append(Run(first: start.globalIndex, last: last, scene: start.scene)) }
            i = j
        }
        return spans.flatMap { run -> [Run] in
            var pieces: [Run] = []
            var first = run.first
            for index in run.first...run.last where cues.contains(index) {
                if index > first { pieces.append(Run(first: first, last: index - 1, scene: run.scene)) }
                first = index + 1
            }
            if first <= run.last { pieces.append(Run(first: first, last: run.last, scene: run.scene)) }
            return pieces.map { $0.length > 1 ? Run(first: $0.first, last: $0.last - 1, scene: $0.scene) : $0 }
        }
    }

    static func matches(_ scene: StoryScene, _ kind: SoundCheckSpot.Kind) -> Bool {
        guard let main = scene.layers.first else { return false }
        let group = main.sound.group
        switch kind {
        case .quietRoom: return quietRoomSounds.contains(main.sound)
        case .loud: return main.level == .loud || (group == .people && main.level >= .full)
        case .outdoors: return scene.setting == .outdoors && (group == .nature || group == .places)
        case .water: return group == .water
        case .weather: return group == .weather
        case .travel: return scene.setting == .vehicle || group == .travel
        case .oneOff, .other: return false
        }
    }
}
