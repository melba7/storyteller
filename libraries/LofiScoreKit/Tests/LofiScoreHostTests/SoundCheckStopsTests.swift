import Foundation
import LofiAtmosphere
import LofiText
import XCTest
@testable import LofiScoreHost

/// The sound check's stops: its spots in the open book, each with where to jump the narration.
final class SoundCheckStopsTests: XCTestCase {
    func testStopsCarryTheAudioOfTheirSentenceAndStayBeforeWhatWasHeard() throws {
        let guardian = try SpoilerGuard(epubDirectory: AtmosphereHostTests.readerBook)
        func entry(_ sentence: Int, _ layers: [SceneLayer], _ setting: StoryScene.Setting) throws -> AtmosphereTrack.Entry {
            let position = try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: sentence))
            return AtmosphereTrack.Entry(position: position, sentence: "s", scene: StoryScene(placeID: "p\(sentence)", setting: setting, layers: layers))
        }
        let track = AtmosphereTrack(engineID: "test", bookID: "book", wordsBetweenEntries: 250, entries: [
            try entry(1, [SceneLayer(.roomTone, .soft)], .indoors),
            try entry(3, [SceneLayer(.crowd, .loud)], .indoors),
            try entry(5, [SceneLayer(.heavyRain, .full)], .outdoors),
        ])

        let all = try LofiAtmosphereHost.soundCheckStops(track: track, spoilerGuard: guardian, heardUpTo: 5, count: 6)
        XCTAssertEqual(all.map(\.spot.globalIndex), [1, 3, 5])
        for stop in all {
            XCTAssertEqual(stop.audioPath, "OEBPS/audio.wav")
            XCTAssertEqual(stop.start, Double(stop.spot.globalIndex) * 3, accuracy: 1e-9, "3 s clips")
        }

        let early = try LofiAtmosphereHost.soundCheckStops(track: track, spoilerGuard: guardian, heardUpTo: 3, count: 6)
        XCTAssertEqual(early.map(\.spot.globalIndex), [1, 3], "nothing past the sentence playing now")
    }
}
