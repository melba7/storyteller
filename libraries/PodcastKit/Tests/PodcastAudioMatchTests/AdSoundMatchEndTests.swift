import Foundation
import XCTest

@testable import PodcastAudioMatch

/// A hit ends where the matching stopped, and a library file cannot crash the phone.
final class AdSoundMatchEndTests: XCTestCase {
  private let long = Array(0..<2300)  // about 60 seconds

  private func hits(_ library: [AdSound], _ ids: [Int]) -> [AdSoundHit] {
    var scanner = AdSoundScanner(library: AdSoundLibrary(sounds: library))
    return scanner.feed(Snd.frames(ids)) + scanner.finish()
  }

  func testAFewSharedFramesDoNotReportTheWholeSound() {
    let episode = Array(80_000..<80_300) + Array(0..<40) + Array(80_300..<83_000)
    let found = hits([Snd.sound(long)], episode)
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found[0].start, Snd.time(300), accuracy: 1e-9)
    XCTAssertEqual(found[0].end, Snd.time(340), accuracy: 8 * Snd.duration)
  }

  func testAThirtySecondCutOfASixtySecondSoundEndsWhereTheCutEnds() {
    let cut = Array(0..<1150)
    let episode = Array(70_000..<70_300) + cut + Array(70_300..<72_000)
    let found = hits([Snd.sound(long)], episode)
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found[0].end, Snd.time(300 + cut.count), accuracy: 8 * Snd.duration)
  }

  func testAWholeSoundStillEndsAtItsLength() {
    let ad = Snd.sound(long)
    let found = hits([ad], Array(70_000..<70_300) + long + Array(70_300..<72_000))
    XCTAssertEqual(found.count, 1)
    XCTAssertEqual(found[0].end, found[0].start + ad.seconds, accuracy: 8 * Snd.duration)
  }

  func testAMatchStillGoingWhenTheDataRunsOutIsGivenByFinish() {
    var scanner = AdSoundScanner(library: AdSoundLibrary(sounds: [Snd.sound(long)]))
    let fed = scanner.feed(Snd.frames(Array(70_000..<70_100) + Array(0..<500)))
    XCTAssertTrue(fed.isEmpty, "the match has not ended yet")
    let rest = scanner.finish()
    XCTAssertEqual(rest.count, 1)
    XCTAssertEqual(rest[0].start, Snd.time(100), accuracy: 1e-9)
    XCTAssertEqual(rest[0].end, Snd.time(600), accuracy: 8 * Snd.duration)
    XCTAssertTrue(scanner.finish().isEmpty)
  }

  func testTheBuilderKeepsACutAndTheLongerSoundApart() {
    let short = Array(0..<1150)
    var builder = AdSoundBuilder()
    let one = Array(50_000..<50_300) + long + Array(50_300..<50_500)
    builder.add(
      episode: "one", frames: Snd.frames(one),
      marked: [MarkedStretch(start: Snd.time(300), end: Snd.time(300 + long.count), sort: "sponsor", who: "Acme")])
    let two = Array(60_000..<60_300) + short + Array(60_300..<60_500)
    builder.add(
      episode: "two", frames: Snd.frames(two),
      marked: [MarkedStretch(start: Snd.time(300), end: Snd.time(300 + short.count), sort: "sponsor", who: "Acme")])
    let sounds = builder.library().sounds
    XCTAssertEqual(sounds.count, 2)
    XCTAssertEqual(sounds.map(\.seen), [1, 1])
    XCTAssertGreaterThan(abs(sounds[0].seconds - sounds[1].seconds), 20)
  }

  func testAddingASoundToAScannerGivesTheSameHitsAsBuildingItAgain() {
    let a = Snd.sound(Array(0..<300), who: "A")
    let b = Snd.sound(Array(1000..<1300), who: "B")
    let episode = Array(5000..<5100) + Array(1000..<1300) + Array(0..<300) + Array(6000..<6100)
    var added = AdSoundScanner(library: AdSoundLibrary(sounds: [a]))
    added.add(b)
    var whole = AdSoundScanner(library: AdSoundLibrary(sounds: [a, b]))
    let frames = Snd.frames(episode)
    XCTAssertEqual(added.feed(frames) + added.finish(), whole.feed(frames) + whole.finish())
    XCTAssertEqual(whole.finish(), [])
  }

  func testALibraryOfThreeThousandSoundsStillFindsASound() {
    var sounds: [AdSound] = []
    for n in 0..<3000 { sounds.append(Snd.sound(Array((n * 400)..<(n * 400 + 300)), who: "s\(n)")) }
    var scanner = AdSoundScanner(library: AdSoundLibrary(sounds: sounds))
    let found =
      scanner.feed(Snd.frames(Array(5_000_000..<5_000_100) + Array(1_000_000..<1_000_300)))
      + scanner.finish()
    XCTAssertEqual(found.map(\.who), ["s2500"])
  }

  // MARK: Numbers in the file

  private func fileJSON(frames: String, seen: String = "1") -> Data {
    let anchors = Data((0..<32).map { UInt8($0) }).base64EncodedString()
    return Data(
      "{\"version\":1,\"step\":8,\"sounds\":[{\"sort\":\"sponsor\",\"who\":\"x\",\"frames\":\(frames),\"seconds\":30,\"seen\":\(seen),\"anchors\":\"\(anchors)\"}]}"
        .utf8)
  }

  func testAHugeOrOddFrameCountLeavesTheSoundOutAndDoesNotCrash() throws {
    for frames in ["9223372036854775807", "-9223372036854775808", "0", "-5", "25001", "1e30"] {
      let library = try XCTUnwrap(AdSoundLibrary(data: fileJSON(frames: frames)), frames)
      XCTAssertEqual(library.sounds.count, 0, "frames \(frames)")
    }
    XCTAssertEqual(AdSoundLibrary(data: fileJSON(frames: "64"))?.sounds.count, 1)
  }

  func testAnOddSeenCountLeavesTheSoundOut() throws {
    for seen in ["9223372036854775807", "-1"] {
      XCTAssertEqual(AdSoundLibrary(data: fileJSON(frames: "64", seen: seen))?.sounds.count, 0, seen)
    }
  }

  func testTheBuilderWritesNoMoreThanTheMacPublishes() throws {
    XCTAssertEqual(AdSoundLibrary.publishBytes, 4_500_000)
    XCTAssertLessThan(AdSoundLibrary.publishBytes, AdSoundLibrary.maxBytes)
    var builder = AdSoundBuilder()
    // Long sounds with their own frames, until the whole would not fit the Mac's limit.
    for n in 0..<330 {
      let ids = Array((n * 30_000)..<(n * 30_000 + 22_000))
      builder.add(
        episode: "e\(n)", frames: Snd.frames(ids),
        marked: [MarkedStretch(start: 1, end: Snd.time(ids.count) - 1, sort: "sponsor", who: "Acme \(n)")])
    }
    let built = builder.library()
    XCTAssertLessThanOrEqual(try built.data().count, AdSoundLibrary.publishBytes)
    XCTAssertGreaterThan(built.sounds.count, 200)
    XCTAssertLessThan(built.sounds.count, 330, "the whole would not fit")
  }
}
