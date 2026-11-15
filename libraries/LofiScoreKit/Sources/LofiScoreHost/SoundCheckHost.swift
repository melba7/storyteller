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

    public var description: String {
        switch self {
        case .noTrack: "This book has no sounds yet."
        }
    }

    public var errorDescription: String? { description }
}

extension LofiAtmosphereHost {
    /// The sound check for the open book: up to `count` stops, all ending before
    /// ``soundCheckLimit(track:playingNow:)``: what has been heard, or the book's opening
    /// for a book not far in yet. A one-off stop is offered only when one-off sounds are on
    /// and that sound has a recording.
    public func soundCheckStops(count: Int = 6) async throws -> [SoundCheckStop] {
        let followerStatus = await withCheckedContinuation { continuation in
            follower.status { continuation.resume(returning: $0) }
        }
        guard let source = await soundCheckSource() else { throw SoundCheckUnavailable.noTrack }
        let now = followerStatus.bookID == source.bookID ? followerStatus.position?.globalIndex : nil
        var snapshot: AmbienceSnapshot?
        if let player = source.player {
            snapshot = await withCheckedContinuation { continuation in player.snapshot { continuation.resume(returning: $0) } }
        }
        let missing = Set(snapshot?.missingOneShots ?? [])
        return try Self.soundCheckStops(
            track: source.track, spoilerGuard: source.spoilerGuard,
            playingNow: Self.soundCheckLimit(track: source.track, playingNow: now), count: count,
            oneOffs: snapshot?.oneShotsEnabled ?? false, oneOffSound: { !missing.contains($0) },
            rate: followerStatus.estimatedRate
        )
    }

    /// About the first 5 minutes of narration (8 sentences are about 20 s).
    static let soundCheckFreeSentences = 120

    /// The first sentence the sound check may not reach. Mo's choice: a book not far in
    /// yet can be checked on its opening, the first chapter with sounds in it or about the
    /// first 5 minutes, whichever is longer, so the check works before most of the book is
    /// heard. Further in, it is the sentence playing now, so nothing ahead is given away.
    static func soundCheckLimit(track: AtmosphereTrack, playingNow: Int?) -> Int {
        let firstScene = track.entries.first { !$0.scene.isSilent }?.globalIndex ?? 0
        let chapterEnd = track.chapterStarts.sorted().first { $0 > firstScene } ?? Int.max
        let opening = max(chapterEnd == Int.max ? firstScene + soundCheckFreeSentences : chapterEnd, soundCheckFreeSentences)
        return max(playingNow ?? 0, opening)
    }

    /// The app is about to jump the narration to a stop that starts at this sentence: the
    /// sounds treat it as a seek however near it is (see ``NarrationFollower/expectJump(toGlobalSentenceIndex:)``).
    public func soundCheckWillJump(toGlobalSentenceIndex index: Int) {
        follower.expectJump(toGlobalSentenceIndex: index)
    }

    /// The seconds a one-off stop plays before its sound: the player plays no one-off in
    /// the first 3 s after a jump. At a faster narration speed the stop starts that much
    /// more audio ahead.
    static let oneOffLeadIn: Double = 5
    /// How many sentences back a one-off stop may start.
    static let oneOffLeadInSentences = 20

    /// The stops among the sentences before `playingNow`. Spots whose audio cannot be found
    /// are left out, and so is a one-off with no clean lead-in in the same file: room for
    /// ``oneOffLeadIn`` seconds at the narration speed `rate`, with no other one-off in
    /// them and no transition or moment cutting in before the stop ends.
    static func soundCheckStops(
        track: AtmosphereTrack, spoilerGuard: SpoilerGuard, playingNow: Int, count: Int,
        oneOffs: Bool = true, oneOffSound: (OneShotSound) -> Bool = { _ in true }, rate: Double = 1
    ) throws -> [SoundCheckStop] {
        let needed = oneOffLeadIn * max(1, rate.isFinite ? rate : 1)
        let otherCues = Set(track.cues.map(\.globalIndex))
        let cutIns = Set(track.entries.filter { $0.scene.transition != nil || $0.scene.moment != nil }.map(\.globalIndex))
        func leadIn(to cue: Int) -> (index: Int, clip: NarrationClip)? {
            guard let target = try? spoilerGuard.clip(atGlobalIndex: cue) else { return nil }
            for index in stride(from: cue - 1, through: max(0, cue - oneOffLeadInSentences), by: -1) {
                // Anything further back only adds to what is in the way.
                guard !otherCues.contains(index), !cutIns.contains(index + 1),
                      let clip = try? spoilerGuard.clip(atGlobalIndex: index), clip.audioPath == target.audioPath else { return nil }
                if target.start - clip.start >= needed {
                    return cutIns.contains(cue + 1) ? nil : (index, clip)
                }
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
    /// gain and whether it sits at the gain cap, plus where the sound goes, the levels in
    /// use and how many one-offs have played. Nil when the sounds are not running.
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
            "missingOneShots": snapshot.missingOneShots.map(\.rawValue),
            "oneShotsPlayed": snapshot.oneShotsPlayed,
            "route": snapshot.route.rawValue,
            "routeMuted": snapshot.routeMuted,
            "voiceLoudnessLUFS": snapshot.voiceLoudnessLUFS,
            "bedLevelDB": snapshot.bedLevelDB,
            "oneShotsEnabled": snapshot.oneShotsEnabled,
            "pausesEnabled": snapshot.pausesEnabled,
        ]
    }
}
