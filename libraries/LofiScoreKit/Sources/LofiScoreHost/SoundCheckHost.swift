import Foundation
import LofiAtmosphere
import LofiText

/// One stop of the sound check: a spot of the open book and where its narration starts.
public struct SoundCheckStop: Sendable, Hashable {
    public let spot: SoundCheckSpot
    /// The audio file, relative to the book, as the book's media overlays name it.
    public let audioPath: String
    /// Where the spot's sentence starts in that file, in seconds.
    public let start: Double

    public func jsonObject() -> [String: Any] {
        var object: [String: Any] = [
            "globalIndex": spot.globalIndex,
            "kind": spot.kind.rawValue,
            "sounds": spot.sounds,
            "audioPath": audioPath,
            "start": start,
        ]
        if let place = spot.placeName { object["placeName"] = place }
        return object
    }
}

public enum SoundCheckUnavailable: Error, CustomStringConvertible {
    /// No book is open, or it has no atmosphere track yet.
    case noTrack
    /// The narration has not reached any sentence yet, so there is nothing heard to test.
    case nothingHeard

    public var description: String {
        switch self {
        case .noTrack: "This book has no sounds yet."
        case .nothingHeard: "Play the book for a moment first: the sound check only uses parts you have already heard."
        }
    }
}

extension LofiAtmosphereHost {
    /// The sound check for the open book: up to `count` stops, all at or before the
    /// sentence the narration is at now, so nothing ahead is given away.
    public func soundCheckStops(count: Int = 6) async throws -> [SoundCheckStop] {
        let followerStatus = await withCheckedContinuation { continuation in
            follower.status { continuation.resume(returning: $0) }
        }
        guard let source = await soundCheckSource() else { throw SoundCheckUnavailable.noTrack }
        guard let now = followerStatus.position, followerStatus.bookID == source.bookID else {
            throw SoundCheckUnavailable.nothingHeard
        }
        return try Self.soundCheckStops(track: source.track, spoilerGuard: source.spoilerGuard, heardUpTo: now.globalIndex, count: count)
    }

    /// The stops among the sentences up to and including `heardUpTo`. Spots whose audio
    /// cannot be found are left out.
    static func soundCheckStops(track: AtmosphereTrack, spoilerGuard: SpoilerGuard, heardUpTo: Int, count: Int) throws -> [SoundCheckStop] {
        try SoundCheck.spots(in: track, before: heardUpTo + 1, count: count).compactMap { spot in
            try spoilerGuard.clip(atGlobalIndex: spot.globalIndex).map {
                SoundCheckStop(spot: spot, audioPath: $0.audioPath, start: $0.start)
            }
        }
    }
}
