import XCTest

@testable import PodcastAudioMatch

final class AdSoundScannerTests: XCTestCase {
  private let adIds = Snd.ids(0..<100)

  private func scan(_ sounds: [AdSound], _ ids: [Int], pieces: Int? = nil) -> [AdSoundHit] {
    var scanner = AdSoundScanner(library: AdSoundLibrary(sounds: sounds))
    let frames = Snd.frames(ids)
    guard let pieces else { return scanner.feed(frames) }
    return stride(from: 0, to: frames.count, by: pieces).flatMap {
      scanner.feed(Array(frames[$0..<min($0 + pieces, frames.count)]))
    }
  }

  func testASoundInTheMiddleOfOtherAudioIsFoundWithItsStartAndEnd() {
    let ad = Snd.sound(adIds, sort: "sponsor", who: "Acme")
    let hits = scan([ad], Snd.ids(1000..<1200, 0..<100, 2000..<2100))
    XCTAssertEqual(hits.count, 1)
    XCTAssertEqual(hits[0].sound, 0)
    XCTAssertEqual(hits[0].sort, "sponsor")
    XCTAssertEqual(hits[0].who, "Acme")
    XCTAssertEqual(hits[0].start, Snd.time(200), accuracy: 1e-9)
    XCTAssertEqual(hits[0].end, Snd.time(200) + ad.seconds, accuracy: 1e-9)
  }

  func testTheSameHitsWhenFedInOneCallOrInManyPieces() {
    let ad = Snd.sound(adIds)
    let ids = Snd.ids(1000..<1200, 0..<100, 2000..<2100, 0..<100)
    let whole = scan([ad], ids)
    XCTAssertEqual(whole.count, 2)
    XCTAssertEqual(scan([ad], ids, pieces: 1), whole)
    XCTAssertEqual(scan([ad], ids, pieces: 7), whole)
    XCTAssertEqual(scan([ad], ids, pieces: 33), whole)
  }

  func testThreeAnchorsAreNotEnoughAndFourAre() {
    let ad = Snd.sound(adIds)
    // The anchors are at frames 0, 8, 16 and 24 of the sound.
    XCTAssertTrue(scan([ad], Snd.ids(1000..<1100, 0..<20, 2000..<2100)).isEmpty)
    XCTAssertEqual(scan([ad], Snd.ids(1000..<1100, 0..<25, 2000..<2100)).count, 1)
  }

  func testTwoSoundsBackToBack() {
    let a = Snd.sound(Snd.ids(0..<100), who: "A")
    let b = Snd.sound(Snd.ids(300..<380), who: "B")
    let hits = scan([a, b], Snd.ids(1000..<1050, 0..<100, 300..<380, 2000..<2050))
    XCTAssertEqual(hits.map(\.who), ["A", "B"])
    XCTAssertEqual(hits[0].start, Snd.time(50), accuracy: 1e-9)
    XCTAssertEqual(hits[1].start, Snd.time(150), accuracy: 1e-9)
  }

  func testTheSameSoundTwiceInOneFileIsReportedTwice() {
    let hits = scan([Snd.sound(adIds)], Snd.ids(0..<100, 1000..<1300, 0..<100))
    XCTAssertEqual(hits.map { ($0.start / Snd.duration).rounded() }, [0, 400])
  }

  func testASoundThatStartsBeforeTheFirstFedFrameStartsAtZero() {
    let ad = Snd.sound(adIds)
    let hits = scan([ad], Array(adIds[40...]) + Snd.ids(2000..<2050))
    XCTAssertEqual(hits.count, 1)
    XCTAssertEqual(hits[0].start, 0)
    // Only frames 40 to 99 of the sound were there: the hit ends where the matching stopped (one
    // step after the last anchor that matched), not after the sound's whole length.
    XCTAssertEqual(hits[0].end, Snd.time(60), accuracy: 8 * Snd.duration)
    XCTAssertLessThan(hits[0].end, ad.seconds)
  }

  func testRepeatedIdenticalFramesStartNoTrail() {
    let silent = Snd.sound(Array(repeating: 999, count: 100))
    XCTAssertTrue(scan([silent], Array(repeating: 999, count: 300)).isEmpty)
  }

  func testAnAnchorInMoreThanThreePlacesOfTheLibraryStartsNoTrail() {
    // After their own first 8 frames the four sounds share frames 0..<92, so those anchors are
    // in four places each: they start nothing, but a trail that began earlier goes over them.
    let sounds = (0..<4).map { Snd.sound(Snd.ids((1000 + $0 * 100)..<(1000 + $0 * 100 + 8)) + Array(0..<92)) }
    XCTAssertTrue(scan(sounds, Snd.ids(0..<92)).isEmpty)
    let hits = scan(sounds, Snd.ids(1100..<1108, 0..<92))
    XCTAssertEqual(hits.map(\.sound), [1])
  }

  func testATrailMayPassOverAWeakAnchor() {
    let ids = Snd.ids(0..<8) + Array(repeating: 999, count: 56) + Snd.ids(100..<108)
    let hits = scan([Snd.sound(ids)], ids)
    XCTAssertEqual(hits.count, 1)
    XCTAssertEqual(hits[0].start, 0)
  }

  func testUnrelatedAudioGivesNoHits() {
    XCTAssertTrue(scan([Snd.sound(adIds)], Snd.ids(5000..<6000)).isEmpty)
  }

  func testAnEmptyLibraryAndEmptyFeedsAreFine() {
    var scanner = AdSoundScanner(library: AdSoundLibrary())
    XCTAssertTrue(scanner.feed([]).isEmpty)
    XCTAssertTrue(scanner.feed(Snd.frames(Snd.ids(0..<50))).isEmpty)
  }
}
