import XCTest

@testable import PodcastAudioMatch

final class SoundBankTests: XCTestCase {
  private var folder: URL!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("bank-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  private func stretch(_ ids: [Int], sort: String = "sponsor", who: String = "Acme") -> BankedStretch {
    BankedStretch(
      sort: sort, who: who,
      frames: Snd.frames(ids).map {
        BankedFrame(hash: UInt32(truncatingIfNeeded: $0.hash), start: Float($0.start), duration: Float($0.duration))
      })
  }

  private var file: URL { SoundBank.fileURL(episode: "abc", in: folder) }

  /// The bank file of a small stretch as JSON, to break one thing at a time.
  private func goodFile() throws -> [String: Any] {
    let data = try SoundBank.data(episode: "abc", stretches: [stretch(Array(0..<3))])
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  private func read(_ object: [String: Any]) throws -> [BankedStretch]? {
    SoundBank.stretches(from: try JSONSerialization.data(withJSONObject: object), episode: "abc")
  }

  private func breaking(_ change: (inout [String: Any]) -> Void) throws -> [String: Any] {
    var object = try goodFile()
    change(&object)
    return object
  }

  private func breakingFirstStretch(_ change: (inout [String: Any]) -> Void) throws -> [String: Any] {
    try breaking {
      var list = $0["stretches"] as! [[String: Any]]
      change(&list[0])
      $0["stretches"] = list
    }
  }

  func testStretchesSurviveAWriteAndARead() throws {
    let stretches = [stretch(Array(0..<40)), stretch(Array(500..<530), sort: "network_promo", who: "Café ☕ \"News\"")]
    XCTAssertTrue(try SoundBank.save(stretches, episode: "abc", in: folder))
    XCTAssertEqual(SoundBank.load(episode: "abc", in: folder), stretches)
    XCTAssertEqual(SoundBank.fileURL(episode: "abc", in: folder).deletingLastPathComponent().lastPathComponent, "sound-bank")
  }

  func testTheFileHoldsTwelveBytesAFrameLittleEndian() throws {
    let one = BankedStretch(
      sort: "sponsor", who: "Acme",
      frames: [BankedFrame(hash: 0x0403_0201, start: 1.0, duration: 0.5)])
    let data = try SoundBank.data(episode: "abc", stretches: [one])
    let top = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(top["version"] as? Int, 1)
    XCTAssertEqual(top["episode"] as? String, "abc")
    let list = try XCTUnwrap(top["stretches"] as? [[String: Any]])
    XCTAssertEqual(list.count, 1)
    XCTAssertEqual(list[0]["sort"] as? String, "sponsor")
    XCTAssertEqual(list[0]["who"] as? String, "Acme")
    XCTAssertEqual(list[0]["frames"] as? Int, 1)
    let bytes = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(list[0]["data"] as? String)))
    // The hash, then 1.0 as a Float32 (0x3F800000), then 0.5 (0x3F000000).
    XCTAssertEqual([UInt8](bytes), [1, 2, 3, 4, 0, 0, 0x80, 0x3F, 0, 0, 0, 0x3F])
  }

  func testTheSameStretchesAlwaysMakeTheSameBytes() throws {
    let stretches = [stretch(Array(0..<40)), stretch(Array(500..<530), who: "B")]
    XCTAssertEqual(
      try SoundBank.data(episode: "abc", stretches: stretches),
      try SoundBank.data(episode: "abc", stretches: stretches))
  }

  func testAnEpisodeWithNothingToKeepStillGetsAFile() throws {
    XCTAssertTrue(try SoundBank.save([], episode: "abc", in: folder))
    XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    XCTAssertEqual(SoundBank.load(episode: "abc", in: folder), [])
  }

  func testSavingTheSameThingAgainWritesNothing() throws {
    let stretches = [stretch(Array(0..<40))]
    XCTAssertTrue(try SoundBank.save(stretches, episode: "abc", in: folder))
    XCTAssertFalse(try SoundBank.save(stretches, episode: "abc", in: folder))
    XCTAssertTrue(try SoundBank.save([stretch(Array(1..<41))], episode: "abc", in: folder))
    XCTAssertEqual(SoundBank.load(episode: "abc", in: folder), [stretch(Array(1..<41))])
  }

  func testAFileThatCannotBeReadIsReplacedBySaving() throws {
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{broken".utf8).write(to: file)
    XCTAssertTrue(try SoundBank.save([stretch(Array(0..<40))], episode: "abc", in: folder))
    XCTAssertNotNil(SoundBank.load(episode: "abc", in: folder))
  }

  func testNoTemporaryFileIsLeftBehind() throws {
    try SoundBank.save([stretch(Array(0..<40))], episode: "abc", in: folder)
    try SoundBank.save([stretch(Array(1..<41))], episode: "abc", in: folder)
    let names = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
    XCTAssertEqual(names, ["abc.json"])
  }

  func testAMissingFileReadsAsNothing() {
    XCTAssertNil(SoundBank.load(episode: "abc", in: folder))
    XCTAssertNil(SoundBank.load(episode: "abc", in: folder.appendingPathComponent("not-there")))
  }

  func testDamagedAndMismatchedFilesReadAsNothing() throws {
    XCTAssertNotNil(try read(goodFile()))  // the file the cases below start from reads
    XCTAssertNil(SoundBank.stretches(from: Data(), episode: "abc"))
    XCTAssertNil(SoundBank.stretches(from: Data("{ broken".utf8), episode: "abc"))
    XCTAssertNil(SoundBank.stretches(from: Data("[]".utf8), episode: "abc"))
    XCTAssertNil(try read(breaking { $0["version"] = 2 }), "another version")
    XCTAssertNil(try read(breaking { $0["version"] = nil }), "no version")
    XCTAssertNil(try read(breaking { $0["episode"] = "other" }), "another episode")
    XCTAssertNil(try read(breaking { $0["episode"] = nil }), "no episode")
    XCTAssertNil(try read(breaking { $0["stretches"] = nil }), "no stretches")
    XCTAssertNil(try read(breaking { $0["stretches"] = "none" }), "stretches that are not a list")
    XCTAssertNil(try read(breakingFirstStretch { $0["frames"] = 4 }), "more frames than data")
    XCTAssertNil(try read(breakingFirstStretch { $0["frames"] = 2 }), "fewer frames than data")
    XCTAssertNil(try read(breakingFirstStretch { $0["frames"] = 0 }), "no frames, some data")
    XCTAssertNil(try read(breakingFirstStretch { $0["frames"] = -3 }), "a negative count")
    XCTAssertNil(try read(breakingFirstStretch { $0["frames"] = Int.max }), "a count that overflows")
    XCTAssertNil(try read(breakingFirstStretch { $0["frames"] = Int.max / 12 + 1 }), "a count that overflows")
    XCTAssertNil(try read(breakingFirstStretch { $0["data"] = "not base64 !" }), "data that is not base64")
    XCTAssertNil(try read(breakingFirstStretch { $0["data"] = Data(count: 35).base64EncodedString() }))
    XCTAssertNil(try read(breakingFirstStretch { $0["data"] = nil }), "no data")
    XCTAssertNil(try read(breakingFirstStretch { $0["sort"] = nil }), "no sort")
    XCTAssertNil(try read(breakingFirstStretch { $0["who"] = 7 }), "who that is not text")
  }

  func testANumberThatCannotBeATimeReadsAsNothing() throws {
    func file(start: Float, duration: Float) throws -> [String: Any] {
      let one = BankedStretch(
        sort: "sponsor", who: "", frames: [BankedFrame(hash: 1, start: start, duration: duration)])
      let data = try SoundBank.data(episode: "abc", stretches: [one])
      return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    XCTAssertNotNil(try read(file(start: 0, duration: 0.026)))
    XCTAssertNil(try read(file(start: .nan, duration: 0.026)))
    XCTAssertNil(try read(file(start: 0, duration: .infinity)))
    XCTAssertNil(try read(file(start: -1, duration: 0.026)))
    XCTAssertNil(try read(file(start: 0, duration: -0.026)))
  }

  /// teach_free.py frees an episode's audio only when its bank is newer than its labels, so saving
  /// the same bytes again must still say "this bank is current as of now".
  func testSavingTheSameBytesAgainRefreshesTheModifiedTime() throws {
    let stretches = [stretch(Array(0..<40))]
    try SoundBank.save(stretches, episode: "abc", in: folder)
    let old = Date(timeIntervalSinceNow: -3600)
    try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: file.path)
    XCTAssertFalse(try SoundBank.save(stretches, episode: "abc", in: folder))
    let modified = try XCTUnwrap(
      try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)
    XCTAssertGreaterThan(modified.timeIntervalSince(old), 3000)
  }

  /// The bank says which folder of labels it was cut from, so that teach_free.py can tell a bank cut
  /// from Claude's own labels from one cut from the snapped ones.
  func testTheFileSaysWhichLabelsItWasCutFrom() throws {
    let stretches = [stretch(Array(0..<40))]
    func labels(_ data: Data) throws -> String? {
      (try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]))["labels"] as? String
    }
    XCTAssertEqual(try labels(SoundBank.data(episode: "abc", stretches: stretches)), "labels")
    XCTAssertEqual(
      try labels(SoundBank.data(episode: "abc", stretches: stretches, labels: "labels-snapped")), "labels-snapped")
    try SoundBank.save(stretches, episode: "abc", in: folder)
    XCTAssertTrue(try SoundBank.save(stretches, episode: "abc", in: folder, labels: "labels-snapped"))
    XCTAssertEqual(try labels(Data(contentsOf: file)), "labels-snapped")
    XCTAssertEqual(SoundBank.load(episode: "abc", in: folder), stretches)
  }

  func testAThirtySecondAdTakesAboutEighteenKilobytes() throws {
    let frames = Int(30 / Snd.duration)
    let data = try SoundBank.data(episode: "0123456789ab", stretches: [stretch(Array(0..<frames))])
    // 12 bytes a frame, a third more as base64 text, and a few dozen bytes of JSON around it.
    XCTAssertEqual(frames, 1148)
    XCTAssertEqual(data.count, 18_494)
    XCTAssertGreaterThan(data.count, frames * 12 * 4 / 3)
  }
}
