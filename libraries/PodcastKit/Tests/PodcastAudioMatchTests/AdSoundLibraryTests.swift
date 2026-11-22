import XCTest

@testable import PodcastAudioMatch

final class AdSoundLibraryTests: XCTestCase {
  private let good = Snd.sound(Snd.ids(0..<100), who: "Acme", seen: 3)
  private let other = Snd.sound(Snd.ids(500..<600), sort: "network_promo", who: "Net", seen: 1)

  /// The library file of two good sounds, with the first sound damaged by `change`.
  private func file(_ change: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
    let data = try AdSoundLibrary(sounds: [good, other]).data()
    var top = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var sounds = try XCTUnwrap(top["sounds"] as? [[String: Any]])
    change(&sounds[0])
    top["sounds"] = sounds
    return try JSONSerialization.data(withJSONObject: top)
  }

  func testRoundTrip() throws {
    let library = AdSoundLibrary(sounds: [good, other])
    XCTAssertEqual(AdSoundLibrary(data: try library.data()), library)
  }

  func testTheFileHasSortedKeysAndBase64Anchors() throws {
    let text = String(decoding: try AdSoundLibrary(sounds: [good]).data(), as: UTF8.self)
    XCTAssertTrue(text.hasPrefix("{\"sounds\""))
    XCTAssertTrue(text.contains("\"step\":8"))
    XCTAssertTrue(text.contains("\"version\":1"))
    let bytes = good.anchors.flatMap { a in (0..<4).map { UInt8(truncatingIfNeeded: a >> (8 * UInt32($0))) } }
    XCTAssertTrue(text.contains(Data(bytes).base64EncodedString()))
  }

  func testTheWholeFileIsRefusedWhenItCannotBeTrusted() throws {
    XCTAssertNil(AdSoundLibrary(data: Data("not json".utf8)))
    XCTAssertNil(AdSoundLibrary(data: Data("[1, 2]".utf8)))
    let text = String(decoding: try AdSoundLibrary(sounds: [good]).data(), as: UTF8.self)
    let v2 = text.replacingOccurrences(of: "\"version\":1", with: "\"version\":2")
    XCTAssertNil(AdSoundLibrary(data: Data(v2.utf8)))
    let step4 = text.replacingOccurrences(of: "\"step\":8", with: "\"step\":4")
    XCTAssertNil(AdSoundLibrary(data: Data(step4.utf8)))
  }

  func testOneBadSoundIsLeftOutAndTheGoodOnesStay() throws {
    let damage: [(String, (inout [String: Any]) -> Void)] = [
      ("unknown sort", { $0["sort"] = "jingle" }),
      ("no frames", { $0["frames"] = 0 }),
      ("too few seconds", { $0["seconds"] = 0.5 }),
      ("too many seconds", { $0["seconds"] = 601 }),
      ("not base64", { $0["anchors"] = "###" }),
      ("not whole numbers", { $0["anchors"] = Data(repeating: 1, count: 34).base64EncodedString() }),
      ("too few anchors", { $0["anchors"] = Data(repeating: 1, count: 28).base64EncodedString() }),
      ("anchors do not fit frames", { $0["frames"] = 200 }),
      ("anchors missing", { $0.removeValue(forKey: "anchors") }),
    ]
    for (name, change) in damage {
      let library = try XCTUnwrap(AdSoundLibrary(data: try file(change)), name)
      XCTAssertEqual(library.sounds, [other], name)
    }
  }

  func testAFileTooLargeIsRefused() throws {
    let padded = try AdSoundLibrary(sounds: [good]).data() + Data(repeating: 0x20, count: AdSoundLibrary.maxBytes)
    XCTAssertNil(AdSoundLibrary(data: padded))
  }

  private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("sounds-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }

  func testInstallWritesTheFileAndLoadReadsIt() throws {
    let url = try folder()
    let path = url.appendingPathComponent(AdSoundLibrary.fileName)
    XCTAssertEqual(AdSoundLibrary.load(from: path), AdSoundLibrary())
    XCTAssertTrue(AdSoundLibrary.install(data: try file(), folder: url))
    XCTAssertEqual(AdSoundLibrary.load(from: path).sounds, [good, other])
  }

  func testInstallRefusesBadDataAndKeepsTheOldFile() throws {
    let url = try folder()
    let path = url.appendingPathComponent(AdSoundLibrary.fileName)
    XCTAssertTrue(AdSoundLibrary.install(data: try AdSoundLibrary(sounds: [good, other]).data(), folder: url))
    XCTAssertFalse(AdSoundLibrary.install(data: Data("nope".utf8), folder: url))
    let big = try AdSoundLibrary(sounds: [good]).data() + Data(repeating: 0x20, count: AdSoundLibrary.maxBytes)
    XCTAssertFalse(AdSoundLibrary.install(data: big, folder: url))
    XCTAssertEqual(AdSoundLibrary.load(from: path).sounds, [good, other])
  }

  func testLoadOfAnUnreadableFileIsEmpty() throws {
    let path = try folder().appendingPathComponent(AdSoundLibrary.fileName)
    try Data("garbage".utf8).write(to: path)
    XCTAssertEqual(AdSoundLibrary.load(from: path), AdSoundLibrary())
  }
}
