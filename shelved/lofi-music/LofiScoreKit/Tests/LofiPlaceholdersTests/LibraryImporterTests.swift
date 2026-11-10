import XCTest
import LofiAudio
import LofiScoreCore
@testable import LofiPlaceholders

final class LibraryImporterTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lofi-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func tone(amplitude: Float, seconds: Double, rate: Double = 44_100) -> StereoBuffer {
        let samples = (0..<Int(seconds * rate)).map { Float(sin(2 * .pi * 997 * Double($0) / rate)) * amplitude }
        return StereoBuffer(left: samples, right: samples, sampleRate: rate)
    }

    private func write(_ audio: StereoBuffer, _ path: String) throws {
        let url = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try WAVFile.write(audio, to: url)
    }

    func testParsesQuotedCSV() {
        let text = "mood,file,title\r\nCalm,\"Calm/a, b.mp3\",\"He said \"\"hi\"\"\"\nTense,t.mp3,\n"
        XCTAssertEqual(LibraryImporter.parseCSV(text), [
            ["mood", "file", "title"],
            ["Calm", "Calm/a, b.mp3", "He said \"hi\""],
            ["Tense", "t.mp3", ""],
        ])
    }

    func testProvenanceMatchesByFileName() {
        let csv = """
        mood,file,title,album,page,license,source_url,sha256
        Calm,Calm/Rain Song.mp3,Rain Song,Album,https://example.org/rain,CC0 1.0,https://example.org/rain.mp3,abc
        """
        let table = LibraryImporter.provenance(csv: csv)
        XCTAssertEqual(table["rain song.mp3"], .init(source: "https://example.org/rain", license: "CC0 1.0"))
    }

    func testMeasuresTracksAndKeepsWhatWasRecorded() throws {
        try write(tone(amplitude: Float(Gain.linear(fromDB: -20)), seconds: 3), "Calm/quiet 70bpm.wav")
        try write(tone(amplitude: Float(Gain.linear(fromDB: -10)), seconds: 2), "Tense/loud.wav")
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent("Tense/broken.wav"))
        let library = try MusicLibrary.load(from: folder)
        let csv = "file,license,page\nloud.wav,CC0,https://example.org/loud\n"

        let outcome = LibraryImporter.importLibrary(library, provenance: LibraryImporter.provenance(csv: csv)) { url in
            try WAVFile.read(Data(contentsOf: url))
        }
        let tracks = Dictionary(uniqueKeysWithValues: outcome.manifest.tracks.map { ($0.file, $0) })
        XCTAssertEqual(tracks.count, 3)
        XCTAssertEqual(tracks["Calm/quiet 70bpm.wav"]?.loudness ?? 0, -20, accuracy: 0.1)
        XCTAssertEqual(tracks["Calm/quiet 70bpm.wav"]?.bpm, 70, "the tempo from the file name is kept")
        XCTAssertEqual(tracks["Calm/quiet 70bpm.wav"]?.duration ?? 0, 3, accuracy: 0.01)
        XCTAssertEqual(tracks["Tense/loud.wav"]?.loudness ?? 0, -10, accuracy: 0.1)
        XCTAssertEqual(tracks["Tense/loud.wav"]?.truePeak ?? 0, -10, accuracy: 0.1)
        XCTAssertEqual(tracks["Tense/loud.wav"]?.license, "CC0")
        XCTAssertEqual(tracks["Tense/loud.wav"]?.source, "https://example.org/loud")
        XCTAssertNil(tracks["Tense/broken.wav"]?.loudness)
        XCTAssertEqual(outcome.failures.map(\.file), ["Tense/broken.wav"])

        // Written next to the music, the player reads it back with the measured levels.
        try outcome.manifest.jsonData().write(to: folder.appendingPathComponent(LibraryManifest.fileName))
        let reloaded = try MusicLibrary.load(from: folder)
        XCTAssertEqual(reloaded.tracks.count, 3)
        let quiet = try XCTUnwrap(reloaded.tracks.first { $0.file == "Calm/quiet 70bpm.wav" })
        XCTAssertEqual(reloaded.loudness(of: quiet), -20, accuracy: 0.1)
    }
}
