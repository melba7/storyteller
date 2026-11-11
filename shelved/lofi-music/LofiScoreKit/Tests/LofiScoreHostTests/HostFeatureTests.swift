import Foundation
import LofiAudio
import LofiDirector
import LofiMood
import LofiScoreCore
import XCTest
@testable import LofiScoreHost

/// The host's now-playing line, the "Wrong mood" button and music while reading on screen.
final class HostFeatureTests: XCTestCase {
    private var folder: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        folder = fileManager.temporaryDirectory.appendingPathComponent("lofi-features-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: folder)
    }

    private func touch(_ path: String) throws {
        let url = folder.appendingPathComponent(path)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0]).write(to: url)
    }

    private func makeHost(defaults: UserDefaults) -> LofiMusicHost {
        let scheduler = DispatchScheduler(label: "test.player")
        let environment = LofiMusicHost.Environment(
            settings: MusicSettings(defaults: defaults),
            musicFolder: folder.appendingPathComponent("app/Music", isDirectory: true),
            placeholderFolder: nil,
            booksFolder: folder.appendingPathComponent("books/extracted", isDirectory: true),
            makeBackend: { FakeAudioBackend(clock: scheduler) },
            makePlayerScheduler: { scheduler },
            followerScheduler: DispatchScheduler(label: "test.follower"),
            makeLiveEngine: { _ in LexiconMoodEngine() },
            feedbackFolder: folder.appendingPathComponent("app/Feedback", isDirectory: true)
        )
        return LofiMusicHost(environment: environment)
    }

    private func waitFor(_ host: LofiMusicHost, _ condition: (LofiMusicStatus) -> Bool) async throws -> LofiMusicStatus {
        let deadline = Date().addingTimeInterval(10)
        while true {
            let status = await host.status()
            if condition(status) { return status }
            if Date() > deadline {
                XCTFail("timed out; last status: \(status)")
                return status
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func clip(_ index: Int) -> NarratorClip {
        NarratorClip(
            textResource: "OEBPS/chapter.xhtml",
            fragmentId: "sentence-\(index)",
            audioResource: "OEBPS/audio.wav",
            start: Double(index) * 3,
            end: Double(index + 1) * 3
        )
    }

    func testReadingOnScreenPlaysAndTheWrongMoodButtonIsLogged() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "lofi-features-\(UUID().uuidString)"))
        for mood in MoodBucket.allCases {
            try touch("Picked/\(mood.rawValue.capitalized)/\(mood.rawValue.capitalized) Song - Some Artist.mp3")
        }
        try fileManager.createDirectory(at: folder.appendingPathComponent("books/extracted/book-1"), withIntermediateDirectories: true)
        try fileManager.copyItem(at: LofiMusicHostTests.readerBook, to: folder.appendingPathComponent("books/extracted/book-1/readaloud"))

        let host = makeHost(defaults: defaults)
        host.start()
        _ = try await host.importMusic(from: folder.appendingPathComponent("Picked"))
        _ = try await waitFor(host) { $0.library.tracks == MoodBucket.allCases.count }

        host.narratorLoadedBook(id: "book-1", trackFile: nil)
        _ = try await waitFor(host) { $0.book?.text == "ready" }
        let early = await host.markWrongMood()
        XCTAssertNil(early, "nothing playing yet")

        // Pages of another book are ignored; this book's start the music without the narrator.
        host.readerReached(bookID: "other", clip: clip(2))
        host.readerReached(bookID: "book-1", clip: clip(2))
        var status = try await waitFor(host) { $0.playback.reading && $0.playback.nowPlaying != nil }
        XCTAssertFalse(status.playback.narrating)
        XCTAssertEqual(status.playback.sentence, 2)
        XCTAssertTrue(status.followsReading)
        XCTAssertEqual(status.playback.nowPlaying?.artist, "Some Artist")
        XCTAssertEqual(status.playback.nowPlaying?.title, "\(status.playback.musicMood!.capitalized) Song")

        let first = try XCTUnwrap(status.playback.musicMood)
        let result = await host.markWrongMood()
        XCTAssertEqual(result?.rejected.rawValue, first)
        status = try await waitFor(host) { ($0.feedback?.bookWrong ?? 0) == 1 }
        XCTAssertEqual(status.feedback?.totalWrong, 1)
        XCTAssertGreaterThanOrEqual(status.feedback?.bookChanges ?? 0, 1, "the opening mood counts as a change")
        let unknown = await host.markWrongMood(named: "sunny")
        XCTAssertNil(unknown, "an unknown mood name does nothing")
        let picked = await host.markWrongMood(named: result?.chosen == .cozy ? "dreamy" : "cozy")
        XCTAssertEqual(picked?.correction, true)
        XCTAssertEqual(picked?.jsonObject()["picked"] as? Bool, true)
        status = await host.status()
        XCTAssertEqual(status.feedback?.bookWrong, 1, "a pick right after a guess is the same miss")
        let text = await host.moodFeedbackText()
        XCTAssertEqual(text?.split(separator: "\n").filter { !$0.hasPrefix("#") }.count, 2)

        // Switching music-while-reading off stops it.
        await host.setFollowsReading(false)
        status = try await waitFor(host) { !$0.playback.reading }
        XCTAssertFalse(status.followsReading)
        XCTAssertFalse(MusicSettings(defaults: defaults).followsReading)
        host.readerReached(bookID: "book-1", clip: clip(5))
        try await Task.sleep(nanoseconds: 200_000_000)
        status = await host.status()
        XCTAssertFalse(status.playback.reading)

        let json = status.jsonObject()
        XCTAssertNotNil(json["feedback"] as? [String: Any])
        XCTAssertEqual(json["followsReading"] as? Bool, false)
    }
}
