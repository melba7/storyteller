import Foundation
import LofiAtmosphere
import LofiAudioCore
import LofiText

/// One stop of the sound check: a spot of the open book and where its narration starts.
public struct SoundCheckStop: Sendable, Hashable {
    public let spot: SoundCheckSpot
    /// The audio file, relative to the book, as the book's media overlays name it.
    public let audioPath: String
    /// Where the stop's first sentence starts in that file, in seconds.
    public let start: Double

    public func jsonObject() -> [String: Any] {
        var object: [String: Any] = [
            "globalIndex": spot.globalIndex,
            "lastIndex": spot.lastIndex,
            "kind": spot.kind.rawValue,
            "sounds": spot.sounds.map { sound -> [String: Any] in
                var object: [String: Any] = ["key": sound.key]
                if let level = sound.level { object["level"] = level.rawValue }
                return object
            },
            "audioPath": audioPath,
            "start": start,
        ]
        if let place = spot.placeName { object["placeName"] = place }
        if let cue = spot.cueIndex { object["cueIndex"] = cue }
        return object
    }
}

/// Why there is no sound check. A `LocalizedError`, so the app's error shows these words.
public enum SoundCheckUnavailable: LocalizedError, CustomStringConvertible {
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

    public var errorDescription: String? { description }
}

extension LofiAtmosphereHost {
    /// The sound check for the open book: up to `count` stops, all ending before the
    /// sentence the narration is at now, so nothing ahead is given away. A one-off stop is
    /// offered only when one-off sounds are on and that sound has a recording.
    public func soundCheckStops(count: Int = 6) async throws -> [SoundCheckStop] {
        let followerStatus = await withCheckedContinuation { continuation in
            follower.status { continuation.resume(returning: $0) }
        }
        guard let source = await soundCheckSource() else { throw SoundCheckUnavailable.noTrack }
        guard let now = followerStatus.position, followerStatus.bookID == source.bookID else {
            throw SoundCheckUnavailable.nothingHeard
        }
        var snapshot: AmbienceSnapshot?
        if let player = source.player {
            snapshot = await withCheckedContinuation { continuation in player.snapshot { continuation.resume(returning: $0) } }
        }
        let missing = Set(snapshot?.missingOneShots ?? [])
        return try Self.soundCheckStops(
            track: source.track, spoilerGuard: source.spoilerGuard, playingNow: now.globalIndex, count: count,
            oneOffs: snapshot?.oneShotsEnabled ?? false, oneOffSound: { !missing.contains($0) }
        )
    }

    /// The seconds of narration a one-off stop plays before its sound: the player plays no
    /// one-off in the first 3 s after a jump.
    static let oneOffLeadIn: Double = 5

    /// The stops among the sentences before `playingNow`. Spots whose audio cannot be found
    /// are left out, and so is a one-off with no room for its lead-in in the same file.
    static func soundCheckStops(
        track: AtmosphereTrack, spoilerGuard: SpoilerGuard, playingNow: Int, count: Int,
        oneOffs: Bool = true, oneOffSound: (OneShotSound) -> Bool = { _ in true }
    ) throws -> [SoundCheckStop] {
        func leadIn(to cue: Int) -> (index: Int, clip: NarrationClip)? {
            guard let target = try? spoilerGuard.clip(atGlobalIndex: cue) else { return nil }
            for index in stride(from: cue - 1, through: max(0, cue - 20), by: -1) {
                guard let clip = try? spoilerGuard.clip(atGlobalIndex: index), clip.audioPath == target.audioPath else { return nil }
                if target.start - clip.start >= oneOffLeadIn { return (index, clip) }
            }
            return nil
        }
        let spots = SoundCheck.spots(
            in: track, before: playingNow, count: count, oneOffs: oneOffs,
            oneOffAllowed: { oneOffSound($0.sound) && leadIn(to: $0.globalIndex) != nil }
        )
        return try spots.compactMap { spot in
            if let cue = spot.cueIndex {
                guard let lead = leadIn(to: cue) else { return nil }
                let moved = SoundCheckSpot(
                    globalIndex: lead.index, lastIndex: spot.lastIndex, kind: spot.kind,
                    sounds: spot.sounds, placeName: spot.placeName, cueIndex: cue
                )
                return SoundCheckStop(spot: moved, audioPath: lead.clip.audioPath, start: lead.clip.start)
            }
            return try spoilerGuard.clip(atGlobalIndex: spot.globalIndex).map {
                SoundCheckStop(spot: spot, audioPath: $0.audioPath, start: $0.start)
            }
        }
    }

    /// Finds the player's own name for a file the book's media overlays name from the book's
    /// root: the path as it is, then shorter tails of it (the player may count from the
    /// package's folder).
    public static func resolveAudio<T>(_ audioPath: String, lookup: (String) async -> T?) async -> T? {
        var parts = audioPath.split(separator: "/").map(String.init)
        while !parts.isEmpty {
            if let found = await lookup(parts.joined(separator: "/")) { return found }
            parts.removeFirst()
        }
        return nil
    }

    /// What is playing now, for a sound check answer: each sound with its level, recording,
    /// gain and whether it sits at the gain cap, plus where the sound goes and the levels in
    /// use. Nil when the sounds are not running.
    public func soundCheckReading() async -> [String: Any]? {
        guard let player = await soundCheckSource()?.player else { return nil }
        let snapshot = await withCheckedContinuation { continuation in player.snapshot { continuation.resume(returning: $0) } }
        return [
            "voices": snapshot.voices.filter { $0.playing && !$0.fadingOut }.map { voice -> [String: Any] in
                var object: [String: Any] = [
                    "sound": voice.sound.rawValue,
                    "recording": voice.recording,
                    "gainDB": (Gain.decibels(fromLinear: voice.gain) * 10).rounded() / 10,
                    "atGainCap": voice.atGainCap,
                ]
                if let variant = voice.variant { object["variant"] = variant }
                if let level = voice.level { object["level"] = level.rawValue }
                return object
            },
            "missingSounds": snapshot.missingSounds.map(\.rawValue),
            "route": snapshot.route.rawValue,
            "routeMuted": snapshot.routeMuted,
            "voiceLoudnessLUFS": snapshot.voiceLoudnessLUFS,
            "bedLevelDB": snapshot.bedLevelDB,
            "oneShotsEnabled": snapshot.oneShotsEnabled,
            "pausesEnabled": snapshot.pausesEnabled,
        ]
    }
}
