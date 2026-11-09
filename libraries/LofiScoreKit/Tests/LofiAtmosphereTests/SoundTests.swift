import Foundation
import XCTest
@testable import LofiAtmosphere
import LofiPlaceholders

final class SoundTests: XCTestCase {
    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("atmosphere-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testEverySynthSoundRendersAtTheSameLoudness() {
        for sound in AmbientSound.allCases {
            let buffer = AmbienceSynth.render(sound, seconds: 3, sampleRate: 8_000)
            XCTAssertFalse(buffer.left.contains { !$0.isFinite }, "\(sound)")
            XCTAssertLessThanOrEqual(buffer.left.map(abs).max() ?? 0, 0.71, "\(sound)")
            let loudness = Loudness.integrated(buffer)
            XCTAssertEqual(loudness, AmbienceSynth.targetLoudness, accuracy: 2.5, "\(sound) at \(loudness) LUFS")
        }
    }

    func testSynthLoopsHaveNoSeam() {
        for sound in [AmbientSound.rain, .fireplace, .crowd, .wind] {
            let buffer = AmbienceSynth.render(sound, seconds: 4, sampleRate: 8_000)
            let samples = buffer.left
            let steps = zip(samples, samples.dropFirst()).map { abs($1 - $0) }.sorted()
            let typical = steps[Int(Double(steps.count) * 0.999)]
            let seam = abs(samples[0] - samples[samples.count - 1])
            XCTAssertLessThanOrEqual(seam, typical, "\(sound): the jump back to the start is no bigger than the sound's own")

            func rms(_ slice: ArraySlice<Float>) -> Double {
                (slice.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(1, slice.count))).squareRoot()
            }
            let window = 4_000
            let end = rms(samples.suffix(window))
            let start = rms(samples.prefix(window))
            XCTAssertEqual(20 * log10(end / start), 0, accuracy: 4, "\(sound): level carries across the loop")
        }
    }

    func testPrepareWritesAMeasuredLibraryOnce() throws {
        let folder = try temporaryFolder().appendingPathComponent("Synth")
        let library = try AmbienceSynth.prepare(at: folder, sounds: [.rain, .fireplace], seconds: 2, sampleRate: 8_000)
        XCTAssertEqual(library.sounds, [.rain, .fireplace])
        for recording in library.recordings {
            XCTAssertTrue(FileManager.default.fileExists(atPath: library.url(for: recording).path))
            XCTAssertEqual(try XCTUnwrap(recording.loudness), AmbienceSynth.targetLoudness, accuracy: 2)
            XCTAssertEqual(recording.source, AmbienceSynth.generatorTag)
        }
        let again = try AmbienceSynth.prepare(at: folder, sounds: [.rain, .fireplace], seconds: 2, sampleRate: 8_000)
        XCTAssertEqual(again, library)
    }

    func testLibraryReadsFoldersAndTheManifestAndFillsGaps() throws {
        let folder = try temporaryFolder()
        let files = ["Heavy Rain/storm.wav", "fireplace/logs.m4a", "fireplace/notes.txt", "Bagpipes/drone.wav", "evil.wav"]
        for file in files {
            let url = folder.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0]).write(to: url)
        }
        let manifest = AmbienceLibrary.Manifest(sounds: [
            AmbienceRecording(id: "heavyRain/storm", file: "Heavy Rain/storm.wav", sound: .heavyRain, loudness: -30, author: "someone", license: "CC0"),
            AmbienceRecording(id: "rain/gone", file: "Rain/gone.wav", sound: .rain, loudness: -20),
            AmbienceRecording(id: "rain/escape", file: "../evil.wav", sound: .rain, loudness: -20),
        ])
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent(AmbienceLibrary.manifestName))

        let library = try AmbienceLibrary.load(from: folder)
        XCTAssertEqual(library.recordings.map(\.file), ["Heavy Rain/storm.wav", "fireplace/logs.m4a"])
        let storm = try XCTUnwrap(library.recordings(of: .heavyRain).first)
        XCTAssertEqual(library.loudness(of: storm), -30)
        XCTAssertEqual(storm.license, "CC0")
        let logs = try XCTUnwrap(library.recordings(of: .fireplace).first)
        XCTAssertEqual(library.loudness(of: logs), AmbienceLibrary.assumedLoudness, "unmeasured files play at an assumed level")

        let synthFolder = folder.deletingLastPathComponent().appendingPathComponent("synth-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: synthFolder) }
        let synth = try AmbienceSynth.prepare(at: synthFolder, sounds: [.fireplace, .rain], seconds: 2, sampleRate: 8_000)
        let filled = library.filling(from: synth)
        XCTAssertEqual(filled.sounds, [.heavyRain, .fireplace, .rain])
        XCTAssertEqual(filled.recordings(of: .fireplace).map(\.file), ["fireplace/logs.m4a"], "an imported sound is never mixed with its stand-in")
        let rain = try XCTUnwrap(filled.recordings(of: .rain).first)
        XCTAssertEqual(filled.url(for: rain).deletingLastPathComponent().deletingLastPathComponent().lastPathComponent, synthFolder.lastPathComponent)

        XCTAssertEqual(try AmbienceLibrary.load(from: folder.appendingPathComponent("nowhere")).recordings, [])
    }

    func testTheSameKeyAlwaysGetsTheSameRecording() {
        let library = PlayerTests.library
        let first = library.recording(of: .fireplace, key: "book|p1|fireplace")
        for _ in 0..<5 {
            XCTAssertEqual(library.recording(of: .fireplace, key: "book|p1|fireplace"), first)
        }
        let picks = Set((1...20).compactMap { library.recording(of: .fireplace, key: "book|p\($0)|fireplace")?.id })
        XCTAssertGreaterThan(picks.count, 1, "different places get different fires")
        XCTAssertNil(library.recording(of: .seaShore, key: "x"))
    }
}

/// Keeps the atmosphere in the same lane as the music: the narrator owns the audio
/// session, Now Playing and the remote commands.
final class AtmosphereBoundaryTests: XCTestCase {
    private static let forbidden = [
        "setCategory", "setMode", "setActive", "setPreferred", "overrideOutputAudioPort",
        "MPNowPlayingInfoCenter", "MPRemoteCommandCenter", "nowPlayingInfo", "import MediaPlayer",
        "inputNode", "AVAudioUnitTimePitch", "AVAudioUnitVarispeed",
    ]

    func testAtmosphereCodeNeverTouchesTheNarratorsControls() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        var scanned = 0
        for target in ["LofiAtmosphere", "lofi-atmosphere"] {
            let folder = root.appendingPathComponent("Sources").appendingPathComponent(target)
            guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else {
                return XCTFail("missing \(folder.path)")
            }
            for case let file as URL in files where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                scanned += 1
                for token in Self.forbidden where text.contains(token) {
                    XCTFail("\(target)/\(file.lastPathComponent) uses \(token)")
                }
            }
        }
        XCTAssertGreaterThan(scanned, 10)
    }
}
