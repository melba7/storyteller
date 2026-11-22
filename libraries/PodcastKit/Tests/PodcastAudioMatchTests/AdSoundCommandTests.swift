import XCTest

@testable import PodcastAudioMatch

final class AdSoundCommandTests: XCTestCase {
  private var folder: URL!
  private var entries: [[String: Any]] = []

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("teach-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: folder.appendingPathComponent("audio"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: folder.appendingPathComponent("labels"), withIntermediateDirectories: true)
    entries = []
  }

  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  private func write(_ bytes: [UInt8], _ path: String) throws {
    try Data(bytes).write(to: folder.appendingPathComponent(path))
  }

  private func writeManifest() throws {
    let data = try JSONSerialization.data(withJSONObject: ["version": 1, "episodes": entries])
    try data.write(to: folder.appendingPathComponent("episodes.json"))
  }

  /// An episode of 700 frames whose frames 300..<(300 + ad.count) are the ad, marked as a sponsor.
  private func addEpisode(
    _ id: String, filler: Int, ad: Range<Int>? = nil, file: String? = nil, label: Bool = true,
    extra: [[String: Any]] = []
  ) throws {
    let name = file ?? "audio/\(id).mp3"
    entries.append(["id": id, "file": name, "show": "Show"])
    let ids = Array(filler..<filler + 300) + Array(ad ?? 0..<0) + Array(filler + 300..<filler + 700)
    try write(ids.flatMap { Marked.frame($0) }, name)
    guard label else { return }
    let start = Double(300) * 1152 / 44100
    let end = Double(300 + (ad?.count ?? 0)) * 1152 / 44100
    var segments: [[String: Any]] = extra
    if ad != nil {
      segments.append(["start": start, "end": end, "sort": "sponsor", "who": "Acme", "confidence": "high"])
    }
    let data = try JSONSerialization.data(withJSONObject: ["version": 1, "segments": segments])
    try data.write(to: folder.appendingPathComponent("labels/\(id).json"))
  }

  private func go(_ arguments: [String]? = nil) -> (code: Int32, said: String) {
    var lines: [String] = []
    let code = AdSoundCommand.run(arguments ?? [folder.path]) { lines.append($0) }
    return (code, lines.joined(separator: "\n"))
  }

  func testMakesTheLibraryAndCountsWhatItDid() throws {
    let low: [String: Any] = ["start": 1.0, "end": 20.0, "sort": "sponsor", "who": "X", "confidence": "low"]
    let ask: [String: Any] = ["start": 2.0, "end": 30.0, "sort": "host_ask", "who": "Y", "confidence": "high"]
    try addEpisode("aaaaaaaaaaaa", filler: 10_000, ad: 0..<500, extra: [low, ask])
    try addEpisode("bbbbbbbbbbbb", filler: 20_000, ad: 0..<500)
    try addEpisode("cccccccccccc", filler: 30_000, ad: 700..<1200)
    try addEpisode("dddddddddddd", filler: 40_000, ad: nil, label: false)
    try addEpisode("eeeeeeeeeeee", filler: 50_000, ad: 0..<500, file: "audio/eeeeeeeeeeee.m4a")
    entries.append(["id": "ffffffffffff", "file": NSNull(), "show": "Show"])
    try write([UInt8](repeating: 0x20, count: 5000), "audio/gggggggggggg.mp3")
    entries.append(["id": "gggggggggggg", "file": "audio/gggggggggggg.mp3", "show": "Show"])
    try Data("{ broken".utf8).write(to: folder.appendingPathComponent("labels/gggggggggggg.json"))
    try writeManifest()

    let result = go()
    XCTAssertEqual(result.code, 0)
    XCTAssertTrue(result.said.contains("Read 3 episodes."), result.said)
    XCTAssertTrue(result.said.contains("Skipped 1 episode with no audio."), result.said)
    XCTAssertTrue(result.said.contains("Skipped 1 episode that is not MP3."), result.said)
    XCTAssertTrue(result.said.contains("Skipped 1 episode with no label."), result.said)
    XCTAssertTrue(result.said.contains("Skipped 1 episode that could not be read."), result.said)
    XCTAssertTrue(result.said.contains("Looked at 3 marked stretches."), result.said)
    XCTAssertTrue(result.said.contains("Kept 2 different sounds."), result.said)
    XCTAssertTrue(result.said.contains("1 of them was heard in more than one episode"), result.said)

    let library = AdSoundLibrary.load(from: folder.appendingPathComponent(AdSoundLibrary.fileName))
    XCTAssertEqual(library.sounds.map(\.seen), [2, 1])
    XCTAssertEqual(library.sounds.map(\.who), ["Acme", "Acme"])
  }

  func testSaysClearlyWhenNothingWasHeardTwice() throws {
    try addEpisode("aaaaaaaaaaaa", filler: 10_000, ad: 0..<500)
    try writeManifest()
    let result = go()
    XCTAssertEqual(result.code, 0)
    XCTAssertTrue(result.said.contains("None of them was heard in more than one episode"), result.said)
  }

  func testNothingToDoIsNotAnError() throws {
    try addEpisode("aaaaaaaaaaaa", filler: 10_000, ad: nil, label: false)
    try writeManifest()
    let result = go()
    XCTAssertEqual(result.code, 0)
    XCTAssertTrue(result.said.contains("Nothing to do"), result.said)
    XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(AdSoundLibrary.fileName).path))
  }

  func testALabelsFolderOfAnotherNameIsRead() throws {
    try addEpisode("aaaaaaaaaaaa", filler: 10_000, ad: 0..<500)
    try writeManifest()
    try FileManager.default.moveItem(
      at: folder.appendingPathComponent("labels"), to: folder.appendingPathComponent("mine"))
    XCTAssertTrue(go().said.contains("Nothing to do"))
    let result = go([folder.path, "--labels", "mine"])
    XCTAssertEqual(result.code, 0)
    XCTAssertTrue(result.said.contains("Kept 1 different sound."), result.said)
  }

  func testSetUpProblemsExitWithTwo() throws {
    XCTAssertEqual(go([]).code, 2)
    XCTAssertEqual(go([folder.path + "-missing"]).code, 2)
    XCTAssertEqual(go().code, 2)  // no episodes.json yet
    try Data("[]".utf8).write(to: folder.appendingPathComponent("episodes.json"))
    XCTAssertEqual(go().code, 2)
    try writeManifest()
    XCTAssertEqual(go([folder.path, "--labels"]).code, 2)
    XCTAssertEqual(go([folder.path, "--nope"]).code, 2)
    XCTAssertEqual(go([folder.path, "extra"]).code, 2)
  }

  func testAnIdOrFileOutsideTheFolderIsNotRead() throws {
    entries.append(["id": "../x", "file": "audio/a.mp3", "show": "Show"])
    entries.append(["id": "aaaaaaaaaaaa", "file": "../outside.mp3", "show": "Show"])
    try writeManifest()
    let result = go()
    XCTAssertEqual(result.code, 0)
    XCTAssertTrue(result.said.contains("Nothing to do"), result.said)
  }
}
