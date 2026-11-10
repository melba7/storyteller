import XCTest
import LofiAudio
import LofiScoreCore
@testable import LofiPlaceholders

final class PlaceholderTests: XCTestCase {
    /// A short version of a recipe, so debug-build tests stay fast.
    private func short(_ recipe: PlaceholderRecipe, bars: Int = 3) -> PlaceholderRecipe {
        var copy = recipe
        copy.bars = bars
        return copy
    }

    func testEveryMoodHasTwoDistinctRecipes() {
        let recipes = PlaceholderRecipe.defaults()
        XCTAssertEqual(recipes.count, 2 * MoodBucket.allCases.count)
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
        XCTAssertEqual(recipes.count, 3 * MoodBucket.allCases.count)
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
        XCTAssertEqual(progress, Array(1...MoodBucket.allCases.count))
        XCTAssertEqual(manifest.tracks.count, MoodBucket.allCases.count)

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
