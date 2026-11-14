import Foundation

/// One spot of a book for the sound check: a short listening test that plays a few
/// different kinds of scene under the narration and asks whether each one can be heard.
public struct SoundCheckSpot: Sendable, Hashable {
    /// What kind of scene the spot tests. A scene can be several; it is listed under the
    /// one it was picked for.
    public enum Kind: String, CaseIterable, Sendable {
        /// A room whose main sound is quiet (room tone, a clock, a hushed room).
        case quietRoom
        /// Something loud: a sound at `loud`, or a crowd at `full`.
        case loud
        case outdoors
        case water
        case weather
        /// A train, a ship, a carriage.
        case travel
        /// A one-off sound, such as a knock at the door.
        case oneOff
        /// Any other scene, picked for a sound the check has not played yet.
        case other
    }

    /// The sentence the spot starts at.
    public let globalIndex: Int
    public let kind: Kind
    /// The sounds the listener should hear, as layer keys ("river.runningTap") or, for a
    /// one-off, the sound's name ("doorKnock").
    public let sounds: [String]
    public let placeName: String?
}

/// Picks the sound check's spots from a book's atmosphere track.
public enum SoundCheck {
    /// The order the kinds are tried in. The first `count` that the book has are picked.
    static let kinds: [SoundCheckSpot.Kind] = [.quietRoom, .loud, .outdoors, .water, .weather, .travel, .oneOff]

    /// Up to `count` spots, one per kind where the book has one, then scenes with sounds not
    /// played yet, spread across the book and returned in book order.
    ///
    /// Spoiler safety: with `limit` (the furthest sentence the listener has heard), every
    /// spot lies before it.
    public static func spots(in track: AtmosphereTrack, before limit: Int? = nil, count: Int = 6) -> [SoundCheckSpot] {
        guard count > 0 else { return [] }
        let heard = { (index: Int) in limit.map { index < $0 } ?? true }
        let scenes = track.entries.filter { !$0.scene.isSilent && heard($0.globalIndex) }
        let cues = track.cues.filter { heard($0.globalIndex) }

        var picked: [SoundCheckSpot] = []
        func farthest<T>(_ candidates: [T], at index: (T) -> Int) -> T? {
            let taken = picked.map(\.globalIndex)
            let free = candidates.filter { !taken.contains(index($0)) }
            // The candidate farthest from the spots already picked; the earliest on a tie.
            return free.max { a, b in
                let da = taken.map { abs($0 - index(a)) }.min() ?? 0
                let db = taken.map { abs($0 - index(b)) }.min() ?? 0
                return da != db ? da < db : index(a) > index(b)
            }
        }
        func spot(_ entry: AtmosphereTrack.Entry, _ kind: SoundCheckSpot.Kind) -> SoundCheckSpot {
            SoundCheckSpot(globalIndex: entry.globalIndex, kind: kind, sounds: entry.scene.layers.map(\.key), placeName: entry.scene.placeName)
        }

        for kind in kinds where picked.count < count {
            if kind == .oneOff {
                if let cue = farthest(cues, at: \.globalIndex) {
                    picked.append(SoundCheckSpot(globalIndex: cue.globalIndex, kind: .oneOff, sounds: [cue.sound.rawValue], placeName: nil))
                }
            } else if let entry = farthest(scenes.filter { matches($0.scene, kind) }, at: \.globalIndex) {
                picked.append(spot(entry, kind))
            }
        }
        while picked.count < count {
            let played = Set(picked.flatMap(\.sounds))
            let fresh = scenes.filter { !$0.scene.layers.allSatisfy { played.contains($0.key) } }
            guard let entry = farthest(fresh.isEmpty ? scenes : fresh, at: \.globalIndex) else { break }
            picked.append(spot(entry, .other))
        }
        return picked.sorted { $0.globalIndex < $1.globalIndex }
    }

    static func matches(_ scene: StoryScene, _ kind: SoundCheckSpot.Kind) -> Bool {
        guard let main = scene.layers.max(by: { $0.level < $1.level }) else { return false }
        let groups = Set(scene.layers.map(\.sound.group))
        switch kind {
        case .quietRoom: return main.sound.group == .rooms && main.level <= .soft
        case .loud: return scene.layers.contains { $0.level == .loud || ($0.sound.group == .people && $0.level >= .full) }
        case .outdoors: return scene.setting == .outdoors && !groups.contains(.water) && !groups.contains(.weather)
        case .water: return groups.contains(.water)
        case .weather: return groups.contains(.weather)
        case .travel: return scene.setting == .vehicle || main.sound.group == .travel
        case .oneOff, .other: return false
        }
    }
}
