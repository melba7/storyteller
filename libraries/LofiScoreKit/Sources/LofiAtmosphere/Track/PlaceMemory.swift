import Foundation

/// The places the story has been so far, and how each one sounded the last time.
///
/// It is made only from track entries before the sentence being scored, so it holds
/// nothing the listener has not heard. The scorer sees it with each passage: when the
/// story comes back to a place it answers with that place's id and starts from the
/// sounds remembered there, changing only what the text says changed.
public struct PlaceMemory: Sendable, Hashable {
    public struct Place: Sendable, Hashable {
        public var id: String
        public var name: String
        public var setting: StoryScene.Setting
        /// The sounds the last time the story was here.
        public var layers: [SceneLayer]
        /// What the place was like then ("between lessons"), if the scorer said.
        public var state: String?
        public var visits: Int
        /// Global index of the last entry in this place.
        public var lastSeen: Int
    }

    public private(set) var places: [String: Place] = [:]
    /// The scene of the most recent entry, if any.
    public private(set) var current: StoryScene?
    /// The newest note about the book's world.
    public private(set) var world: String?
    /// The more specific sounds the scorer may use: the book's own variants asked for
    /// before this point, then those from other books and the starter set.
    public private(set) var variants: [SoundVariant] = []
    private var lastGlobalIndex: Int?

    public init() {}

    /// The memory as of just before `globalIndex`: every entry before it, in order, and
    /// the variants first asked for before it, then `offered` ones (never this book's).
    public init(track: AtmosphereTrack, before globalIndex: Int, offered: [SoundVariant] = []) {
        self.init(entries: track.entries(before: globalIndex))
        offer(track.variants(before: globalIndex))
        offer(offered)
    }

    /// Adds variants the scorer may use; one already offered under the same id stays.
    public mutating func offer(_ more: [SoundVariant]) {
        for variant in more where !variants.contains(where: { $0.id == variant.id }) {
            variants.append(variant)
        }
    }

    public func variant(_ id: String) -> SoundVariant? {
        variants.first { $0.id == id }
    }

    public init<S: Sequence>(entries: S) where S.Element == AtmosphereTrack.Entry {
        for entry in entries { record(entry) }
    }

    public mutating func record(_ entry: AtmosphereTrack.Entry) {
        let scene = entry.scene
        current = scene
        lastGlobalIndex = entry.globalIndex
        if let world = entry.world?.trimmingCharacters(in: .whitespacesAndNewlines), !world.isEmpty {
            self.world = world
        }
        guard let id = scene.placeID else { return }
        var place = places[id] ?? Place(id: id, name: scene.placeName ?? id, setting: scene.setting, layers: [], visits: 0, lastSeen: entry.globalIndex)
        if let name = scene.placeName, !name.isEmpty { place.name = name }
        if scene.setting != .unclear { place.setting = scene.setting }
        // What the characters were doing there (walking, eating) is not the place's.
        place.layers = scene.layers.filter { $0.sound.scope != .activity }
        place.state = scene.state
        // A visit is a stretch of entries in the same place.
        if place.visits == 0 || previousPlaceID != id { place.visits += 1 }
        place.lastSeen = entry.globalIndex
        places[id] = place
        previousPlaceID = id
    }

    private var previousPlaceID: String?

    /// The most recently visited places first, the current one included.
    public func recent(limit: Int) -> [Place] {
        Array(places.values.sorted { $0.lastSeen > $1.lastSeen }.prefix(max(0, limit)))
    }

    /// An id no place has yet: one more than the highest "pN".
    public func newPlaceID() -> String {
        let highest = places.keys.compactMap { Int($0.dropFirst()) }.max() ?? 0
        return "p\(highest + 1)"
    }

    /// A known place whose name is the same as `name`, give or take articles and case.
    public func place(named name: String) -> Place? {
        let key = Self.nameKey(name)
        guard !key.isEmpty else { return nil }
        return places.values
            .filter { Self.nameKey($0.name) == key }
            .max { $0.lastSeen < $1.lastSeen }
    }

    /// Lowercased words without articles, for matching place names.
    public static func nameKey(_ name: String) -> String {
        let skip: Set<String> = ["the", "a", "an", "of", "in", "at", "on"]
        return name.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !skip.contains($0) }
            .joined(separator: " ")
    }

    /// True when two place names probably mean the same place: the same words, or one
    /// name's words all inside the other's ("the garden", "the walled garden").
    public static func namesMatch(_ a: String, _ b: String) -> Bool {
        let wordsA = Set(nameKey(a).split(separator: " "))
        let wordsB = Set(nameKey(b).split(separator: " "))
        guard !wordsA.isEmpty, !wordsB.isEmpty else { return false }
        return wordsA.isSubset(of: wordsB) || wordsB.isSubset(of: wordsA)
    }
}
