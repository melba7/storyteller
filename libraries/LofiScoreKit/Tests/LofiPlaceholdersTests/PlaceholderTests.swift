import XCTest
import LofiAudio
import LofiScoreCore
@testable import LofiPlaceholders

final class LoudnessTests: XCTestCase {
    private func sine(frequency: Double, amplitude: Float, seconds: Double, sampleRate: Double) -> [Float] {
        (0..<Int(seconds * sampleRate)).map { Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) * amplitude }
    }

    func testFullScaleSineInBothChannelsIsZeroLUFS() {
        // BS.1770: a 0 dBFS 1 kHz sine in left and right measures 0 LKFS.
        for rate in [44_100.0, 48_000.0] {
            let tone = sine(frequency: 997, amplitude: 1, seconds: 3, sampleRate: rate)
            let measured = Loudness.integrated(channels: [tone, tone], sampleRate: rate)
            XCTAssertEqual(measured, 0, accuracy: 0.05, "at \(rate) Hz")
        }
    }

    func testOneChannelIsThreeDecibelsQuieter() {
        let rate = 48_000.0
        let tone = sine(frequency: 997, amplitude: 1, seconds: 3, sampleRate: rate)
        let silence = [Float](repeating: 0, count: tone.count)
        XCTAssertEqual(Loudness.integrated(channels: [tone, silence], sampleRate: rate), -3.01, accuracy: 0.05)
    }

    func testLevelScalesInDecibels() {
        let rate = 48_000.0
        let tone = sine(frequency: 997, amplitude: Float(Gain.linear(fromDB: -20)), seconds: 3, sampleRate: rate)
        XCTAssertEqual(Loudness.integrated(channels: [tone, tone], sampleRate: rate), -20, accuracy: 0.05)
    }

    func testGatingIgnoresSilence() {
        let rate = 48_000.0
        let tone = sine(frequency: 997, amplitude: Float(Gain.linear(fromDB: -23)), seconds: 4, sampleRate: rate)
        let padded = tone + [Float](repeating: 0, count: Int(8 * rate))
        // The 37 blocks inside the tone count fully; the three blocks straddling its end hold
        // 75%, 50% and 25% of it and pass the gates too. The 77 silent blocks are gated out.
        let expected = -23 + 10 * log10((37 + 0.75 + 0.5 + 0.25) / 40)
        XCTAssertEqual(Loudness.integrated(channels: [padded, padded], sampleRate: rate), expected, accuracy: 0.02)
        let silence = [Float](repeating: 0, count: 48_000)
        XCTAssertEqual(Loudness.integrated(channels: [silence, silence], sampleRate: rate), -.infinity)
    }

    func testTruePeakCatchesPeaksBetweenSamples() {
        // A sine at a quarter of the sample rate, phase-shifted so no sample lands on a crest.
        let rate = 48_000.0
        let samples = (0..<4800).map { Float(sin(2 * .pi * 12_000 * Double($0) / rate + .pi / 4)) }
        let buffer = StereoBuffer(left: samples, right: samples, sampleRate: rate)
        XCTAssertEqual(Double(buffer.samplePeak), sqrt(0.5), accuracy: 1e-3)
        XCTAssertGreaterThan(Loudness.truePeak(buffer), Gain.decibels(fromLinear: Double(buffer.samplePeak)) + 1)
    }
}

final class WAVFileTests: XCTestCase {
    func testRoundTrip() throws {
        let rate = 22_050.0
        let left = (0..<2000).map { Float(sin(Double($0) / 10)) * 0.5 }
        let right = (0..<2000).map { Float(cos(Double($0) / 7)) * 0.25 }
        let buffer = StereoBuffer(left: left, right: right, sampleRate: rate)
        let data = WAVFile.data(for: buffer)
        XCTAssertEqual(data.count, 44 + 2000 * 4)
        let decoded = try WAVFile.read(data)
        XCTAssertEqual(decoded.sampleRate, rate)
        XCTAssertEqual(decoded.frames, 2000)
        for index in stride(from: 0, to: 2000, by: 97) {
            XCTAssertEqual(decoded.left[index], left[index], accuracy: 1e-4)
            XCTAssertEqual(decoded.right[index], right[index], accuracy: 1e-4)
        }
    }

    func testClipsInsteadOfWrapping() throws {
        let buffer = StereoBuffer(left: [2, -2], right: [1, -1], sampleRate: 8000)
        let decoded = try WAVFile.read(WAVFile.data(for: buffer))
        XCTAssertGreaterThan(decoded.left[0], 0.99)
        XCTAssertLessThan(decoded.left[1], -0.99)
    }

    func testRejectsOtherFiles() {
        XCTAssertThrowsError(try WAVFile.read(Data("hello world, not a wav".utf8)))
    }
}

final class PlaceholderTests: XCTestCase {
    /// A short version of a recipe, so debug-build tests stay fast.
    private func short(_ recipe: PlaceholderRecipe, bars: Int = 3) -> PlaceholderRecipe {
        var copy = recipe
        copy.bars = bars
        return copy
    }

    func testEveryMoodHasTwoDistinctRecipes() {
        let recipes = PlaceholderRecipe.defaults()
        XCTAssertEqual(recipes.count, 16)
        for bucket in MoodBucket.allCases {
            let pair = recipes.filter { $0.bucket == bucket }
            XCTAssertEqual(pair.map(\.id), ["\(bucket.rawValue)-1", "\(bucket.rawValue)-2"])
            XCTAssertNotEqual(pair[0].key, pair[1].key)
            for recipe in pair {
                XCTAssertGreaterThanOrEqual(recipe.duration, 30, recipe.id)
                XCTAssertLessThanOrEqual(recipe.duration, 45, recipe.id)
            }
        }
        XCTAssertEqual(Set(recipes.map(\.id)).count, recipes.count)
    }

    func testMoreThanTwoPerMoodAreTransposedVariations() {
        let recipes = PlaceholderRecipe.defaults(perMood: 3)
        XCTAssertEqual(recipes.count, 24)
        let calm = recipes.filter { $0.bucket == .calm }
        XCTAssertEqual(calm[2].tonic, calm[0].tonic + 2)
        XCTAssertEqual(calm[2].key, "G major")
        XCTAssertNotEqual(calm[2].seed, calm[0].seed)
    }

    func testTempoAndEnergyFollowTheMood() {
        let recipes = PlaceholderRecipe.defaults()
        func meanBPM(_ bucket: MoodBucket) -> Double {
            let tempos = recipes.filter { $0.bucket == bucket }.map(\.bpm)
            return tempos.reduce(0, +) / Double(tempos.count)
        }
        XCTAssertGreaterThan(meanBPM(.tense), meanBPM(.calm))
        XCTAssertGreaterThan(meanBPM(.playful), meanBPM(.melancholy))
        XCTAssertLessThan(meanBPM(.somber), meanBPM(.cozy))
    }

    func testRenderingIsDeterministic() {
        let recipe = short(PlaceholderRecipe.defaults()[0])
        let first = LofiSynth.render(recipe, sampleRate: 16_000)
        let second = LofiSynth.render(recipe, sampleRate: 16_000)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.duration, recipe.duration, accuracy: 0.001)
    }

    func testRenderedTracksAreNormalisedWithHeadroom() {
        for recipe in [PlaceholderRecipe.defaults()[0], PlaceholderRecipe.defaults()[12]] {
            let track = PlaceholderLibrary.render(short(recipe, bars: 4), sampleRate: 22_050)
            XCTAssertEqual(track.loudness, -16, accuracy: 1.0, recipe.id)
            XCTAssertLessThanOrEqual(track.truePeak, -0.9, recipe.id)
            XCTAssertFalse(track.audio.left.contains { !$0.isFinite })
        }
    }

    func testWritesALibraryThePlayerCanLoad() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lofi-placeholders-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let recipes = PlaceholderRecipe.defaults(perMood: 1).map { short($0, bars: 1) }
        var progress: [Int] = []
        let manifest = try PlaceholderLibrary.write(to: folder, recipes: recipes, sampleRate: 8_000) { done, _, _ in
            progress.append(done)
        }
        XCTAssertEqual(progress, Array(1...8))
        XCTAssertEqual(manifest.tracks.count, 8)

        let library = try MusicLibrary.load(from: folder)
        XCTAssertTrue(library.emptyBuckets.isEmpty)
        let calm = try XCTUnwrap(library.tracks(in: .calm).first)
        XCTAssertEqual(calm.file, "Calm/calm-1 72bpm.wav")
        XCTAssertEqual(calm.bpm, 72)
        XCTAssertEqual(calm.source, PlaceholderLibrary.generatorTag)
        XCTAssertNotNil(calm.loudness)
        let audio = try WAVFile.read(Data(contentsOf: library.url(for: calm)))
        XCTAssertEqual(audio.duration, calm.duration ?? 0, accuracy: 0.01)

        // The scanner agrees with the manifest about tempo and mood.
        let scanned = try MusicLibrary.scan(folder: folder)
        XCTAssertEqual(Set(scanned.tracks.map(\.bucket)), Set(MoodBucket.allCases))
        XCTAssertEqual(scanned.tracks(in: .calm).first?.bpm, 72)

        // prepare() reuses a current library instead of rendering again.
        let before = try FileManager.default.attributesOfItem(atPath: library.url(for: calm).path)[.modificationDate] as? Date
        _ = try PlaceholderLibrary.prepare(at: folder, recipes: recipes, sampleRate: 8_000)
        let after = try FileManager.default.attributesOfItem(atPath: library.url(for: calm).path)[.modificationDate] as? Date
        XCTAssertEqual(before, after)
    }

    func testLimiterNeverExceedsTheCeiling() {
        var audio = StereoBuffer(left: [0.5, 0.9, 1.5, -3], right: [0, 0.7, -0.75, 10], sampleRate: 8000)
        PlaceholderLibrary.limit(&audio, ceiling: 0.87)
        XCTAssertEqual(audio.left[0], 0.5)
        XCTAssertTrue((audio.left + audio.right).allSatisfy { abs($0) <= 0.87 })
        XCTAssertGreaterThan(audio.left[2], audio.left[1], "the knee keeps the order of levels")
    }
}
