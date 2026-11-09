import Foundation
import LofiDirector
import LofiScoreCore

/// Picks the next track, avoiding the ones played most recently.
///
/// The plan: when a track ends, play another from the same bucket, avoiding the last three
/// played. With only a few tracks in a bucket the rule relaxes: first it only avoids the
/// track that is playing, and with a single track that track repeats.
public struct TrackRotation: Sendable {
    public var avoidLast: Int
    /// Most recently played track ids, oldest first.
    public private(set) var recent: [String] = []
    private var random: SplitMix64

    public init(avoidLast: Int = 3, seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        self.avoidLast = max(0, avoidLast)
        random = SplitMix64(seed: seed)
    }

    /// Chooses a track from `candidates`. `playing` is the id of a track that must not be
    /// chosen if anything else is available (the one on the other deck).
    public mutating func pick(from candidates: [LibraryTrack], playing: String? = nil) -> LibraryTrack? {
        guard !candidates.isEmpty else { return nil }
        let avoid = Set(recent.suffix(avoidLast)).union(playing.map { [$0] } ?? [])
        var pool = candidates.filter { !avoid.contains($0.id) }
        if pool.isEmpty, let playing {
            pool = candidates.filter { $0.id != playing }
        }
        if pool.isEmpty {
            pool = candidates
        }
        // Among the allowed tracks, prefer the one heard least recently.
        let neverPlayed = pool.filter { !recent.contains($0.id) }
        if !neverPlayed.isEmpty {
            pool = neverPlayed
        } else {
            let oldest = pool.min { (recent.lastIndex(of: $0.id) ?? -1) < (recent.lastIndex(of: $1.id) ?? -1) }
            pool = oldest.map { [$0] } ?? pool
        }
        let index = Int(random.next() % UInt64(pool.count))
        return pool[index]
    }

    /// Records that `id` started playing.
    public mutating func notePlayed(_ id: String) {
        recent.removeAll { $0 == id }
        recent.append(id)
        if recent.count > 64 {
            recent.removeFirst(recent.count - 64)
        }
    }
}
