import XCTest
import LofiAudio
import LofiDirector
import LofiPlaceholders
import LofiScoreCore
@testable import LofiDemoKit

/// The offline run behind `lofi-render`, with a silent backend: the clock, the voice
/// timeline, the mix levels and the read-along text.
final class OfflineRenderTests: XCTestCase {
    private func library() -> MusicLibrary {
        let tracks = MoodBucket.allCases.flatMap { bucket in
            (1...2).map { n in
                LibraryTrack(id: "\(bucket.rawValue)-\(n)", file: "\(bucket.rawValue)/\(bucket.rawValue)-\(n).wav",
                             bucket: bucket, bpm: 80, duration: 40, loudness: -16)
            }
        }
        return MusicLibrary(root: URL(fileURLWithPath: "/music"), tracks: tracks)
    }

    private func makeRun(step: TimeInterval = 0.05) -> (OfflineStoryRun, FakeAudioBackend) {
        let scheduler = ManualScheduler()
        let backend = FakeAudioBackend(clock: scheduler)
        backend.defaultDuration = 40
        var config = ScoreConfig()
        config.director = .demo
        var options = OfflineStoryRun.Options()
        options.step = step
        // Pretend voice: 0.3 s per word.
        let run = OfflineStoryRun(
            library: library(),
            backend: backend,
            config: config,
            moodSource: ScriptedMoodSource(noise: 0, seed: 1),
            scheduler: scheduler,
            options: options,
            voiceDuration: { text in Double(text.split(separator: " ").count) * 0.3 }
        )
        return (run, backend)
    }

    func testRunsTheWholeStoryWithContiguousSteps() {
        let (run, _) = makeRun()
        var covered = 0.0
        var lastEnd = 0.0
        var gaps = 0
        let report = run.run { start, duration in
            if abs(start - lastEnd) > 1e-6 { gaps += 1 }
            lastEnd = start + duration
            covered += duration
        }
        let story = DemoStory.greenLantern
        XCTAssertTrue(report.finished)
        XCTAssertEqual(gaps, 0)
        XCTAssertEqual(covered, report.duration, accuracy: 1e-6)
        XCTAssertEqual(report.clips.map(\.globalIndex), Array(0..<story.sentences.count))
        XCTAssertEqual(report.clips.first?.start ?? -1, run.options.leadIn, accuracy: 0.051)

        // One sentence at a time, each as long as its voice, with the narrator's pauses between.
        for (clip, next) in zip(report.clips, report.clips.dropFirst()) {
            let words = Double(clip.text.split(separator: " ").count)
            XCTAssertEqual(clip.duration, words * 0.3, accuracy: 1e-9)
            XCTAssertGreaterThanOrEqual(next.start, clip.start + clip.duration + run.options.narrator.sentencePause - 0.051)
        }
        let last = report.clips[report.clips.count - 1]
        XCTAssertGreaterThanOrEqual(report.duration, last.start + last.duration + run.options.tail)
    }

    func testMusicNeverChangesBeforeItsMoodIsSpoken() {
        let (run, backend) = makeRun()
        let report = run.run { _, _ in }
        let story = DemoStory.greenLantern
        XCTAssertFalse(report.decisions.isEmpty)
        XCTAssertFalse(report.readings.isEmpty)
        for timed in report.decisions {
            // Some sentence of this mood had started by the time of the decision.
            let spoken = report.clips.filter { $0.start <= timed.time + 1e-9 }
            XCTAssertTrue(
                spoken.contains { story.sentences[$0.globalIndex].mood == timed.decision.bucket },
                "\(timed.decision.bucket) chosen at \(timed.time) before any \(timed.decision.bucket) sentence"
            )
        }
        // Readings never look past the sentence being spoken.
        for reading in report.readings {
            let current = report.clips.last { $0.start <= reading.time + 1e-9 }
            XCTAssertLessThanOrEqual(reading.observation.globalSentenceIndex, current?.globalIndex ?? -1)
        }
        XCTAssertTrue(backend.calls.contains(.startEngine))
    }

    func testDeckCallbacksAreDeliveredBetweenSteps() {
        let (run, backend) = makeRun(step: 0.1)
        var finishedOnce = false
        let report = run.run { start, _ in
            // A deck "finishes" from inside a render step, as a real engine's render thread would.
            if !finishedOnce, start > 20 {
                finishedOnce = true
                backend.finish(.a)
                backend.finish(.b)
            }
        }
        XCTAssertTrue(report.finished)
        XCTAssertTrue(finishedOnce)
        // The player heard about it after the step and replaced the finished track.
        let started = report.events.filter {
            if case .trackStarted = $0.event { return $0.time > 20 && $0.time < 20.3 }
            return false
        }
        XCTAssertFalse(started.isEmpty, "a finished deck is replaced at the next step")
    }

    func testVoiceTrackPlacesClipsAtTheirTimes() {
        let clips = [
            SpokenClip(globalIndex: 0, text: "a", start: 0.5, duration: 0.25),
            SpokenClip(globalIndex: 1, text: "b", start: 1.0, duration: 0.1),
        ]
        let rate = 100.0
        let track = OfflineMix.voiceTrack(clips: clips, sampleRate: rate, frames: 150) { clip in
            [Float](repeating: clip.text == "a" ? 0.5 : 0.25, count: 50)
        }
        XCTAssertEqual(track.count, 150)
        XCTAssertEqual(track[49], 0)
        XCTAssertEqual(track[50], 0.5)
        XCTAssertEqual(track[75], 0.5)
        XCTAssertEqual(track[77], 0, "cut at the clip's duration")
        XCTAssertEqual(track[100], 0.25)
        XCTAssertEqual(track[110], 0.25)
        XCTAssertEqual(track[112], 0)
    }

    func testMixLevelsTheVoiceAndLimitsPeaks() {
        let rate = 44_100.0
        let frames = Int(rate * 6)
        // A quiet "voice" (a 1 kHz tone) and quieter "music" (a 220 Hz tone).
        let voice = (0..<frames).map { Float(0.05 * sin(2 * Double.pi * 1000 * Double($0) / rate)) }
        var music = StereoBuffer(frames: frames, sampleRate: rate)
        for index in 0..<frames {
            let value = Float(0.01 * sin(2 * Double.pi * 220 * Double(index) / rate))
            music.left[index] = value
            music.right[index] = value
        }
        let result = OfflineMix.mix(voice: voice, music: music)
        let voiceAlone = Loudness.integrated(channels: [voice, voice], sampleRate: rate)
        XCTAssertEqual(result.voiceGainDB, -18 - voiceAlone, accuracy: 1e-9)
        XCTAssertEqual(result.outputLoudness, -16, accuracy: 0.2)
        XCTAssertLessThanOrEqual(result.outputPeak, -1 + 0.05)
        XCTAssertEqual(result.audio.frames, frames)

        // Very loud input is held under the ceiling.
        let loud = (0..<frames).map { Float(0.99 * sin(2 * Double.pi * 100 * Double($0) / rate)) }
        var levels = OfflineMix.Levels()
        levels.outputLoudness = 0
        let limited = OfflineMix.mix(voice: loud, music: StereoBuffer(frames: frames, sampleRate: rate), levels: levels)
        XCTAssertLessThanOrEqual(limited.audio.samplePeak, Float(Gain.linear(fromDB: -1)) + 1e-4)
    }

    func testTimelineReadsAlong() {
        let (run, _) = makeRun()
        let report = run.run { _, _ in }
        let text = OfflineMix.timeline(report, story: .greenLantern, library: library())
        for chapter in DemoStory.greenLantern.chapters {
            XCTAssertTrue(text.contains(chapter.title), "missing \(chapter.title)")
        }
        XCTAssertTrue(text.contains("music  calm →") || text.contains("music  "), text)
        XCTAssertTrue(text.contains("track  starts"))
        XCTAssertTrue(text.contains("Music changes: \(report.decisions.count)."))
        XCTAssertEqual(OfflineMix.clock(75.9), " 1:15")
    }
}
