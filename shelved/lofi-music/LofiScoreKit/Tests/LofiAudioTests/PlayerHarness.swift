import Foundation
import LofiDirector
import LofiScoreCore
@testable import LofiAudio

extension ScoreConfig {
    /// The timings the player tests were written against (the first version's defaults:
    /// 7 s crossfades, 2 s fade-in, up to 4 s bar wait, bed 12 dB under the voice, 4 dB
    /// lift after 1.5 s of silence). The tests check the player's mechanics with these;
    /// `DefaultsTests` checks the subtler defaults the app ships with.
    static var mechanics: ScoreConfig {
        var config = ScoreConfig()
        config.gentleCrossfade = 7
        config.rotationCrossfade = 7
        config.fadeIn = 2
        config.maxBarWait = 4
        config.ducking = .mechanics
        return config
    }
}

extension DuckingSettings {
    /// See ``ScoreConfig/mechanics``.
    static var mechanics: DuckingSettings {
        var settings = DuckingSettings()
        settings.bedLevelDB = -12
        settings.gapLiftDB = 4
        settings.gapThreshold = 1.5
        settings.liftTime = 1.5
        return settings
    }
}

/// A player wired to a fake backend and a manual clock, with a small library of silent
/// tracks named "<bucket>-<n>.wav".
final class PlayerHarness {
    let scheduler = ManualScheduler()
    let backend: FakeAudioBackend
    let library: MusicLibrary
    let config: ScoreConfig
    let player: LofiScorePlayer
    private(set) var events: [(time: TimeInterval, event: PlayerEvent)] = []
    private(set) var decisions: [MoodDecision] = []
    private(set) var lastIndex = 0

    init(
        config: ScoreConfig = .mechanics,
        buckets: [MoodBucket] = MoodBucket.allCases,
        tracksPerBucket: Int = 4,
        bpm: Double? = nil,
        duration: TimeInterval = 120,
        failingFiles: Set<String> = []
    ) {
        self.config = config
        backend = FakeAudioBackend(clock: scheduler)
        backend.defaultDuration = duration
        backend.failingFiles = failingFiles
        var tracks: [LibraryTrack] = []
        for bucket in buckets {
            for n in 1...tracksPerBucket {
                tracks.append(LibraryTrack(
                    id: "\(bucket.rawValue)-\(n)",
                    file: "\(bucket.rawValue)/\(bucket.rawValue)-\(n).wav",
                    bucket: bucket,
                    bpm: bpm,
                    duration: duration,
                    loudness: -16
                ))
            }
        }
        library = MusicLibrary(root: URL(fileURLWithPath: "/music"), tracks: tracks)
        player = LofiScorePlayer(library: library, backend: backend, scheduler: scheduler, config: config, rotationSeed: 7)
        player.onEvent = { [unowned self] event in
            events.append((scheduler.now, event))
        }
        player.onDecision = { [unowned self] decision in
            decisions.append(decision)
        }
    }

    var now: TimeInterval { scheduler.now }

    func advance(_ seconds: TimeInterval) {
        scheduler.advance(by: seconds)
    }

    /// The bed gain of a −16 LUFS track with the default ducking settings.
    var bedGain: Double {
        config.ducking.bedGain(forTrackLoudness: -16)
    }

    func gain(_ deck: Deck) -> Double {
        Double(backend.gain(of: deck))
    }

    /// The mood of the file loaded on `deck`, from its name.
    func mood(on deck: Deck) -> MoodBucket? {
        guard let file = backend.file(on: deck), let name = file.split(separator: "-").first else { return nil }
        return MoodBucket(rawValue: String(name))
    }

    func snapshot() -> PlayerSnapshot {
        var result: PlayerSnapshot?
        player.snapshot { result = $0 }
        return result!
    }

    func reading(_ bucket: MoodBucket, confidence: Double = 0.7) -> MoodReading {
        MoodReading(
            bucket: bucket,
            valence: bucket.anchor.valence,
            arousal: bucket.anchor.arousal,
            confidence: confidence,
            engineID: "test"
        )
    }

    /// Sends a reading. Without `index` it continues four sentences after the previous one.
    func send(_ bucket: MoodBucket, trigger: ReadingTrigger = .cadence, confidence: Double = 0.7, index: Int? = nil) {
        let index = index ?? lastIndex + 4
        lastIndex = index
        player.receive(MoodObservation(
            reading: reading(bucket, confidence: confidence),
            chapterOrdinal: 0,
            sentenceIndex: index,
            globalSentenceIndex: index,
            trigger: trigger
        ))
    }

    /// Opens a book, starts the narrator, sends the first reading 0.2 s later and waits for
    /// the fade-in to finish. Deck A then plays `bucket` from position 0 at time 0.2.
    func startPlaying(in bucket: MoodBucket = .calm) {
        player.openBook(id: "book")
        player.narratorDidPlay()
        advance(0.2)
        send(bucket, trigger: .start, index: 0)
        advance(config.fadeIn + 0.1)
    }

    /// The listener jumps to `index`, and the reading for the new place says `bucket`.
    func seek(to index: Int, finding bucket: MoodBucket, confidence: Double = 0.7) {
        player.narratorDidSeek(toGlobalSentenceIndex: index)
        send(bucket, trigger: .seek, confidence: confidence, index: index)
    }

    var crossfades: [(time: TimeInterval, to: String, transition: MusicTransition, duration: TimeInterval)] {
        events.compactMap { entry in
            if case let .crossfadeStarted(_, to, transition, duration) = entry.event {
                return (entry.time, to, transition, duration)
            }
            return nil
        }
    }

    var startedFiles: [String] {
        events.compactMap { entry in
            if case let .trackStarted(trackID, _, _, _) = entry.event { return trackID }
            return nil
        }
    }

    var errors: [String] {
        events.compactMap { entry in
            if case let .error(message) = entry.event { return message }
            return nil
        }
    }

    func playCalls(_ deck: Deck) -> [TimeInterval] {
        backend.calls.compactMap { call in
            if case let .play(d, offset) = call, d == deck { return offset }
            return nil
        }
    }

    func count(_ call: FakeAudioBackend.Call) -> Int {
        backend.calls.filter { $0 == call }.count
    }
}
