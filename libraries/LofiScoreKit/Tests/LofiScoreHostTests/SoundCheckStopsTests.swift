import Foundation
import LofiAtmosphere
import LofiText
import XCTest
@testable import LofiScoreHost

/// The sound check's stops: its spots in the open book, each with where to jump the narration.
final class SoundCheckStopsTests: XCTestCase {
    private func book() throws -> (SpoilerGuard, (Int, [SceneLayer], StoryScene.Setting) throws -> AtmosphereTrack.Entry) {
        let guardian = try SpoilerGuard(epubDirectory: AtmosphereHostTests.readerBook)
        let entry = { (sentence: Int, layers: [SceneLayer], setting: StoryScene.Setting) throws -> AtmosphereTrack.Entry in
            let position = try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: sentence))
            return AtmosphereTrack.Entry(position: position, sentence: "s", scene: StoryScene(placeID: "p\(sentence)", setting: setting, layers: layers))
        }
        return (guardian, entry)
    }

    func testStopsCarryTheAudioOfTheirSentenceAndEndBeforeWhatIsPlayingNow() throws {
        let (guardian, entry) = try book()
        let track = AtmosphereTrack(engineID: "test", bookID: "book", wordsBetweenEntries: 250, entries: [
            try entry(0, [SceneLayer(.roomTone, .soft)], .indoors),
            try entry(3, [SceneLayer(.crowd, .loud)], .indoors),
            try entry(6, [SceneLayer(.heavyRain, .full)], .outdoors),
        ])

        let all = try LofiAtmosphereHost.soundCheckStops(track: track, spoilerGuard: guardian, playingNow: 9, count: 6)
        XCTAssertEqual(all.map(\.spot.globalIndex), [0, 3, 6])
        XCTAssertEqual(all.last?.spot.lastIndex, 7, "it ends while the sentence before the one playing now plays")
        for stop in all {
            XCTAssertEqual(stop.audioPath, "OEBPS/audio.wav")
            XCTAssertEqual(stop.start, Double(stop.spot.globalIndex) * 3, accuracy: 1e-9, "3 s clips")
        }
        XCTAssertEqual(try LofiAtmosphereHost.soundCheckStops(track: track, spoilerGuard: guardian, playingNow: 5, count: 6).map(\.spot.globalIndex), [0, 3])
    }

    func testAOneOffStopStartsAtLeastFiveSecondsBeforeItsSound() throws {
        let (guardian, entry) = try book()
        let position = { (i: Int) in try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: i)) }
        let track = AtmosphereTrack(
            engineID: "test", bookID: "book", wordsBetweenEntries: 250,
            entries: [try entry(0, [SceneLayer(.roomTone, .soft)], .indoors)],
            cues: [
                AtmosphereTrack.Cue(position: try position(1), sentence: "s", sound: .doorKnock, wordsBefore: 0, words: 2),
                AtmosphereTrack.Cue(position: try position(5), sentence: "s", sound: .doorKnock, wordsBefore: 0, words: 2),
            ]
        )
        // The knock at 1 is only 3 s into the file: too close to the start, so it is left out.
        // The knock at 5 starts two 3 s sentences earlier, at 3.
        let stops = try LofiAtmosphereHost.soundCheckStops(track: track, spoilerGuard: guardian, playingNow: 9, count: 6)
        let knock = try XCTUnwrap(stops.first { $0.spot.kind == .oneOff })
        XCTAssertEqual(knock.spot.cueIndex, 5)
        XCTAssertEqual(knock.spot.globalIndex, 3)
        XCTAssertEqual(knock.start, 9, accuracy: 1e-9)
    }

    func testAOneOffStopNeedsACleanLeadInAtTheNarrationSpeed() throws {
        let (guardian, entry) = try book()
        let position = { (i: Int) in try XCTUnwrap(try guardian.position(chapterOrdinal: 0, sentenceIndex: i)) }
        func knock(_ index: Int) throws -> AtmosphereTrack.Cue {
            AtmosphereTrack.Cue(position: try position(index), sentence: "s", sound: .doorKnock, wordsBefore: 0, words: 2)
        }
        func oneOff(_ track: AtmosphereTrack, rate: Double = 1) throws -> SoundCheckStop? {
            try LofiAtmosphereHost.soundCheckStops(track: track, spoilerGuard: guardian, playingNow: 9, count: 6, rate: rate)
                .first { $0.spot.kind == .oneOff }
        }
        let room = try entry(0, [SceneLayer(.roomTone, .soft)], .indoors)

        // At twice the speed, 5 s of listening is 10 s of audio: four 3 s sentences back.
        let plain = AtmosphereTrack(engineID: "test", bookID: "book", wordsBetweenEntries: 250, entries: [room], cues: [try knock(6)])
        XCTAssertEqual(try oneOff(plain)?.spot.globalIndex, 4)
        XCTAssertEqual(try oneOff(plain, rate: 2)?.spot.globalIndex, 2)
        XCTAssertEqual(try oneOff(plain, rate: 2)?.start ?? -1, 6, accuracy: 1e-9)

        // Another one-off in the lead-in would play in its place: 30 s must pass between two.
        let crowded = AtmosphereTrack(engineID: "test", bookID: "book", wordsBetweenEntries: 250, entries: [room], cues: [try knock(1), try knock(3)])
        XCTAssertNil(try oneOff(crowded), "the first is too near the file's start, the second has the first in its lead-in")

        // A door closing on the way to the knock would be heard as the one-off.
        let position5 = try position(5)
        let door = AtmosphereTrack.Entry(position: position5, sentence: "s", scene: StoryScene(
            placeID: "p5", setting: .outdoors, layers: [SceneLayer(.wind, .soft)], transition: .enterThroughDoor
        ))
        let moving = AtmosphereTrack(engineID: "test", bookID: "book", wordsBetweenEntries: 250, entries: [room, door], cues: [try knock(6)])
        XCTAssertNil(try oneOff(moving))
    }

    func testThePlayersNameForTheFileIsFoundFromShorterTails() async {
        let known = ["Audio/ch1.mp3": 1]
        var asked: [String] = []
        let found = await LofiAtmosphereHost.resolveAudio("OEBPS/Audio/ch1.mp3") { path in
            asked.append(path)
            return known[path]
        }
        XCTAssertEqual(found, 1)
        XCTAssertEqual(asked, ["OEBPS/Audio/ch1.mp3", "Audio/ch1.mp3"])
        let missing = await LofiAtmosphereHost.resolveAudio("OEBPS/x.mp3") { known[$0] }
        XCTAssertNil(missing)
    }

    func testReasonsReadWellOnTheScreen() {
        XCTAssertEqual(SoundCheckUnavailable.nothingHeard.localizedDescription, SoundCheckUnavailable.nothingHeard.description)
    }
}
