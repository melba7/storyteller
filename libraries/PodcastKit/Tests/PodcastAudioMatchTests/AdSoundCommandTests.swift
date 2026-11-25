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

  func testAnExamEpisodeIsNeverLearnedFrom() throws {
    try addEpisode("aaaaaaaaaaaa", filler: 10_000, ad: 0..<500)
    try addEpisode("bbbbbbbbbbbb", filler: 20_000, ad: 0..<500)
    // The exam episode has an ad of its own that no other episode has.
    try addEpisode("cccccccccccc", filler: 30_000, ad: 700..<1200)
    try writeManifest()
    try Data("{\"episodes\": [\"cccccccccccc\"]}".utf8).write(
      to: folder.appendingPathComponent("exam.json"))
    XCTAssertEqual(go().code, 0)
    let file = folder.appendingPathComponent(AdSoundLibrary.fileName)
    let withLabel = try Data(contentsOf: file)
    // Take the exam episode's label away: what is saved must be the same, byte for byte.
    try FileManager.default.removeItem(at: folder.appendingPathComponent("labels/cccccccccccc.json"))
    XCTAssertEqual(go().code, 0)
    XCTAssertEqual(try Data(contentsOf: file), withLabel)
    XCTAssertEqual(AdSoundLibrary.load(from: file).sounds.count, 1)
  }

  func testADamagedExamFileIsASetUpProblem() throws {
    try addEpisode("aaaaaaaaaaaa", filler: 10_000, ad: 0..<500)
    try writeManifest()
    try Data("{broken".utf8).write(to: folder.appendingPathComponent("exam.json"))
    XCTAssertEqual(go().code, 2)
    XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(AdSoundLibrary.fileName).path))
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

  // MARK: the sound bank

  private func bank(_ id: String) -> URL { folder.appendingPathComponent("sound-bank/\(id).json") }

  private var libraryFile: URL { folder.appendingPathComponent(AdSoundLibrary.fileName) }

  private func removeAudio(_ ids: String...) throws {
    for id in ids { try FileManager.default.removeItem(at: folder.appendingPathComponent("audio/\(id).mp3")) }
  }

  /// Two episodes with one ad, one with another ad, and one with no ad at all.
  private func addLearnedEpisodes() throws {
    try addEpisode("aaaaaaaaaaaa", filler: 10_000, ad: 0..<500)
    try addEpisode("bbbbbbbbbbbb", filler: 20_000, ad: 0..<500)
    try addEpisode("cccccccccccc", filler: 30_000, ad: 700..<1200)
    try addEpisode("dddddddddddd", filler: 40_000, ad: nil)
    try writeManifest()
  }

  func testSavesABankFileForEveryLearnedEpisode() throws {
    try addLearnedEpisodes()
    try addEpisode("eeeeeeeeeeee", filler: 50_000, ad: 0..<500, label: false)
    try writeManifest()
    let result = go()
    XCTAssertEqual(result.code, 0)
    XCTAssertTrue(result.said.contains("Saved 4 sound-bank files."), result.said)
    XCTAssertEqual(SoundBank.load(episode: "aaaaaaaaaaaa", in: folder)?.count, 1)
    XCTAssertEqual(SoundBank.load(episode: "bbbbbbbbbbbb", in: folder)?.count, 1)
    XCTAssertEqual(SoundBank.load(episode: "cccccccccccc", in: folder)?.count, 1)
    // An episode with no ad is learned too, and its file says so with an empty list.
    XCTAssertEqual(SoundBank.load(episode: "dddddddddddd", in: folder), [])
    // One that was not learned from has no file.
    XCTAssertFalse(FileManager.default.fileExists(atPath: bank("eeeeeeeeeeee").path))
  }

  func testAnEpisodeWhoseAudioIsGoneIsLearnedFromItsBank() throws {
    try addLearnedEpisodes()
    XCTAssertEqual(go().code, 0)
    let first = try Data(contentsOf: libraryFile)
    try removeAudio("aaaaaaaaaaaa")
    let result = go()
    XCTAssertEqual(result.code, 0)
    XCTAssertTrue(result.said.contains("Read 3 episodes."), result.said)
    XCTAssertTrue(result.said.contains("Learned from 1 saved summary, its audio is gone."), result.said)
    XCTAssertTrue(result.said.contains("Saved 0 sound-bank files."), result.said)
    XCTAssertFalse(result.said.contains("with no audio"), result.said)
    XCTAssertEqual(try Data(contentsOf: libraryFile), first)
    XCTAssertEqual(AdSoundLibrary.load(from: libraryFile).sounds.map(\.seen), [2, 1])
  }

  func testTheLibraryIsTheSameWhenAllTheAudioIsGone() throws {
    try addLearnedEpisodes()
    XCTAssertEqual(go().code, 0)
    let first = try Data(contentsOf: libraryFile)
    try removeAudio("aaaaaaaaaaaa", "bbbbbbbbbbbb", "cccccccccccc", "dddddddddddd")
    let result = go()
    XCTAssertEqual(result.code, 0)
    XCTAssertFalse(result.said.contains("Nothing to do"), result.said)
    XCTAssertTrue(result.said.contains("Learned from 4 saved summaries, their audio is gone."), result.said)
    XCTAssertTrue(result.said.contains("Looked at 3 marked stretches."), result.said)
    XCTAssertEqual(try Data(contentsOf: libraryFile), first)
  }

  func testAnEpisodeWithNeitherAudioNorBankIsCountedAsBefore() throws {
    try addLearnedEpisodes()
    XCTAssertEqual(go().code, 0)
    try removeAudio("aaaaaaaaaaaa", "cccccccccccc")
    try FileManager.default.removeItem(at: bank("cccccccccccc"))
    let result = go()
    XCTAssertEqual(result.code, 0)
    XCTAssertTrue(result.said.contains("Learned from 1 saved summary, its audio is gone."), result.said)
    XCTAssertTrue(result.said.contains("Skipped 1 episode with no audio."), result.said)
    XCTAssertTrue(result.said.contains("Read 2 episodes."), result.said)
    // The ad that only the lost episode had is gone from the library; the shared one stays.
    XCTAssertEqual(AdSoundLibrary.load(from: libraryFile).sounds.map(\.seen), [2])
  }

  func testADamagedBankFileIsNotLearnedFrom() throws {
    try addLearnedEpisodes()
    XCTAssertEqual(go().code, 0)
    try removeAudio("aaaaaaaaaaaa")
    try Data("{ broken".utf8).write(to: bank("aaaaaaaaaaaa"))
    let result = go()
    XCTAssertEqual(result.code, 0)
    XCTAssertTrue(result.said.contains("Skipped 1 episode with no audio."), result.said)
    XCTAssertFalse(result.said.contains("Learned from"), result.said)
    XCTAssertEqual(AdSoundLibrary.load(from: libraryFile).sounds.map(\.seen), [1, 1])
  }

  func testABankFileIsOnlyWrittenWhenItIsMissingOrDifferent() throws {
    try addLearnedEpisodes()
    XCTAssertTrue(go().said.contains("Saved 4 sound-bank files."))
    XCTAssertTrue(go().said.contains("Saved 0 sound-bank files."))
    // Marked again a little shorter: this episode's file changes.
    let shorter: [String: Any] = [
      "start": Double(300) * 1152 / 44100, "end": Double(300 + 450) * 1152 / 44100,
      "sort": "sponsor", "who": "Acme", "confidence": "high",
    ]
    let label = try JSONSerialization.data(withJSONObject: ["version": 1, "segments": [shorter]])
    try label.write(to: folder.appendingPathComponent("labels/cccccccccccc.json"))
    XCTAssertTrue(go().said.contains("Saved 1 sound-bank file."))
    try FileManager.default.removeItem(at: bank("dddddddddddd"))
    XCTAssertTrue(go().said.contains("Saved 1 sound-bank file."))
    XCTAssertEqual(SoundBank.load(episode: "dddddddddddd", in: folder), [])
  }

  func testAnExamEpisodeGetsNoBankFile() throws {
    try addLearnedEpisodes()
    try Data("{\"episodes\": [\"cccccccccccc\"]}".utf8).write(to: folder.appendingPathComponent("exam.json"))
    let result = go()
    XCTAssertTrue(result.said.contains("Saved 3 sound-bank files."), result.said)
    XCTAssertFalse(FileManager.default.fileExists(atPath: bank("cccccccccccc").path))
  }

  func testAnExamEpisodeIsNotLearnedFromItsBankEither() throws {
    try addLearnedEpisodes()
    XCTAssertEqual(go().code, 0)
    XCTAssertEqual(AdSoundLibrary.load(from: libraryFile).sounds.map(\.seen), [2, 1])
    // The episode becomes an exam episode after it was learned, and its audio is deleted.
    try Data("{\"episodes\": [\"cccccccccccc\"]}".utf8).write(to: folder.appendingPathComponent("exam.json"))
    try removeAudio("cccccccccccc")
    let result = go()
    XCTAssertEqual(result.code, 0)
    XCTAssertFalse(result.said.contains("Learned from"), result.said)
    XCTAssertEqual(AdSoundLibrary.load(from: libraryFile).sounds.map(\.seen), [2])
  }

  func testALibraryIsStillMadeWhenTheBankCannotBeWritten() throws {
    try addLearnedEpisodes()
    try Data("in the way".utf8).write(to: folder.appendingPathComponent("sound-bank"))
    let result = go()
    XCTAssertEqual(result.code, 0)
    XCTAssertTrue(result.said.contains("Could not save 4 sound-bank files"), result.said)
    XCTAssertTrue(result.said.contains("Saved 0 sound-bank files."), result.said)
    XCTAssertTrue(result.said.contains("Kept 2 different sounds."), result.said)
    XCTAssertEqual(AdSoundLibrary.load(from: libraryFile).sounds.count, 2)
  }
}
