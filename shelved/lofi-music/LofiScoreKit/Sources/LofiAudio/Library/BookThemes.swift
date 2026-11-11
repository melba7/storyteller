import Foundation
import LofiScoreCore

/// Each book's themes: one track per mood that comes back whenever the story returns to
/// that mood, the way a film score brings back a theme. The rest of the mood's tracks still
/// follow it in rotation when it ends.
///
/// The choice needs no memory: it is a stable hash of the book, the mood and each track's
/// id (rendezvous hashing), so a book gets the same themes every time it is opened, and
/// adding a track to the library only changes a theme where the new track wins.
public enum BookThemes {
    /// The theme for `bucket` in the book `bookID`, from `candidates`.
    public static func theme(bookID: String, bucket: MoodBucket, candidates: [LibraryTrack]) -> LibraryTrack? {
        candidates.max { lhs, rhs in
            let left = score(bookID: bookID, bucket: bucket, trackID: lhs.id)
            let right = score(bookID: bookID, bucket: bucket, trackID: rhs.id)
            return left != right ? left < right : lhs.id > rhs.id
        }
    }

    static func score(bookID: String, bucket: MoodBucket, trackID: String) -> UInt64 {
        // FNV-1a, then a SplitMix64 finaliser to spread similar ids.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(bookID)\u{1F}\(bucket.rawValue)\u{1F}\(trackID)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        hash ^= hash >> 30
        hash &*= 0xbf58_476d_1ce4_e5b9
        hash ^= hash >> 27
        hash &*= 0x94d0_49bb_1331_11eb
        hash ^= hash >> 31
        return hash
    }
}
