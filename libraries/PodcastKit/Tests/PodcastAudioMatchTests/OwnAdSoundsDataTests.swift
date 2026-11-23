import XCTest

@testable import PodcastAudioMatch

/// The file of the phone's own sounds as text: what is written, and what a damaged file reads as.
final class OwnAdSoundsDataTests: XCTestCase {
  /// Two sounds and one undone stretch.
  private func filled() -> OwnAdSounds {
    var own = OwnAdSounds()
    let one = Own.episode(filler: 10_000, ad: Array(0..<500))
    let two = Own.episode(filler: 20_000, ad: Array(1000..<1500), who: "Other")
    let three = Own.episode(filler: 30_000, ad: Array(2000..<2500))
    own.learn(show: "show", frames: one.frames, stretches: [one.stretch], now: Own.now)
    own.learn(show: "other show", frames: two.frames, stretches: [two.stretch], now: Own.now + 5)
    own.forget(frames: three.frames, start: three.stretch.start, end: three.stretch.end, now: Own.now + 9)
    return own
  }

  /// The file's JSON as a dictionary, changed by `change`, and written again.
  private func edited(_ data: Data, _ change: (inout [String: Any]) -> Void) throws -> Data {
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    change(&object)
    return try JSONSerialization.data(withJSONObject: object)
  }

  func testWhatIsWrittenReadsBackTheSame() {
    let own = filled()
    XCTAssertEqual(own.entries.count, 2)
    XCTAssertEqual(OwnAdSounds.read(own.data), own)
    XCTAssertEqual(OwnAdSounds.read(own.data).data, own.data)
    XCTAssertEqual(OwnAdSounds.currentVersion, 1)
  }

  func testAnEmptyLibraryWritesAFileThatReadsAsEmpty() {
    XCTAssertEqual(OwnAdSounds.read(OwnAdSounds().data), OwnAdSounds())
    XCTAssertFalse(OwnAdSounds().data.isEmpty)
  }

  func testTheFileIsTheMacsFormatWithTheShowAndTheTimeAdded() throws {
    let own = filled()
    let library = try XCTUnwrap(AdSoundLibrary(data: own.data))
    XCTAssertEqual(library.sounds, own.library.sounds)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: own.data) as? [String: Any])
    let sounds = try XCTUnwrap(object["sounds"] as? [[String: Any]])
    XCTAssertEqual(sounds.first?["show"] as? String, "other show")
    XCTAssertEqual(sounds.first?["lastSeen"] as? Double, Own.now + 5)
  }

  func testADamagedFileReadsAsEmpty() throws {
    let good = filled().data
    let empty = OwnAdSounds()
    XCTAssertEqual(OwnAdSounds.read(Data()), empty)
    XCTAssertEqual(OwnAdSounds.read(Data("not json at all".utf8)), empty)
    XCTAssertEqual(OwnAdSounds.read(Data([0xFF, 0x00, 0xFE])), empty)
    XCTAssertEqual(OwnAdSounds.read(good.prefix(good.count - 20)), empty)
    XCTAssertEqual(OwnAdSounds.read(Data("[1, 2, 3]".utf8)), empty)
    XCTAssertEqual(OwnAdSounds.read(Data("{\"version\": 1}".utf8)), empty)
    XCTAssertEqual(OwnAdSounds.read(try edited(good) { $0["sounds"] = "text" }), empty)
  }

  func testAnotherVersionOrStepReadsAsEmpty() throws {
    let good = filled().data
    XCTAssertEqual(OwnAdSounds.read(try edited(good) { $0["version"] = 2 }), OwnAdSounds())
    XCTAssertEqual(OwnAdSounds.read(try edited(good) { $0["version"] = 0 }), OwnAdSounds())
    XCTAssertEqual(OwnAdSounds.read(try edited(good) { $0["step"] = 4 }), OwnAdSounds())
    XCTAssertEqual(OwnAdSounds.read(try edited(good) { $0["version"] = "1" }), OwnAdSounds())
  }

  func testAFileOverTheLimitReadsAsEmptyWithoutBeingParsed() {
    let good = filled().data
    XCTAssertEqual(OwnAdSounds.read(good), filled())
    // A file that would read, made larger than 1.5 MB by blanks at the end.
    let padded = good + Data(repeating: 0x20, count: OwnAdSounds.maxBytes)
    XCTAssertGreaterThan(padded.count, OwnAdSounds.maxBytes)
    XCTAssertEqual(OwnAdSounds.read(padded), OwnAdSounds())
    XCTAssertEqual(OwnAdSounds.read(Data(repeating: 0x7B, count: 2_000_000)), OwnAdSounds())
  }

  func testASoundThatBreaksTheRulesIsLeftOutAlone() throws {
    let good = filled().data
    func broken(_ change: @escaping (inout [String: Any]) -> Void) throws -> OwnAdSounds {
      OwnAdSounds.read(
        try edited(good) { object in
          var sounds = object["sounds"] as? [[String: Any]] ?? []
          change(&sounds[0])
          object["sounds"] = sounds
        })
    }
    let changes: [(inout [String: Any]) -> Void] = [
      { $0["anchors"] = "AAAA" },  // too few anchors
      { $0["anchors"] = "!!not base64!!" },
      { $0["sort"] = "jingle" },
      { $0["frames"] = 0 },
      { $0["frames"] = 99_999_999 },
      { $0["seconds"] = 0 },
      { $0["seconds"] = 100_000 },
      { $0["seen"] = -1 },
      { $0["lastSeen"] = -5 },
      { $0["lastSeen"] = "yesterday" },
      { $0["show"] = "" },
      { $0["show"] = String(repeating: "x", count: 600) },
      { $0["who"] = nil },
    ]
    for (number, change) in changes.enumerated() {
      let read = try broken(change)
      XCTAssertEqual(read.entries.count, 1, "change \(number)")
      XCTAssertEqual(read.entries.first?.show, "show", "change \(number)")
    }
  }

  func testMoreThanTheLimitsInAFileAreCutWhenItIsRead() throws {
    // A file made by hand that holds one show's sounds three times over: 40 stay.
    let made = Own.crowded(count: 40, base: 1_000_000)
    var own = OwnAdSounds()
    own.learn(show: "show", frames: made.frames, stretches: made.stretches, now: Own.now)
    XCTAssertEqual(own.entries.count, 40)
    let many = try edited(own.data) { object in
      let sounds = object["sounds"] as? [[String: Any]] ?? []
      object["sounds"] = sounds + sounds + sounds
    }
    XCTAssertEqual(OwnAdSounds.read(many).entries.count, 40)
  }
}
