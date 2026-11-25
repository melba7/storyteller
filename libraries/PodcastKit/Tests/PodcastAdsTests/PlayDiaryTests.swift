import XCTest

@testable import PodcastAds

/// The measuring diary: one line for every play that starts and one for every finished
/// transcription, kept apart from the ad diary's 500 lines.
final class PlayDiaryTests: XCTestCase {
  private func fields(_ line: String) throws -> [String: Any] {
    try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], line)
  }

  private func what(_ line: String) throws -> String {
    try XCTUnwrap(try fields(line)["what"] as? String, line)
  }

  // MARK: What a play was

  func testAPlayWithAFinishedResultIsReadyAndALoadedStreamIsAStream() {
    XCTAssertEqual(
      PlayDiary.start(isStream: false, hasFinishedAds: true, transcriptReached: 3600), .ready)
    XCTAssertEqual(
      PlayDiary.start(isStream: false, hasFinishedAds: false, transcriptReached: 240),
      .partly(transcriptTo: 240))
    XCTAssertEqual(
      PlayDiary.start(isStream: false, hasFinishedAds: false, transcriptReached: 0),
      .partly(transcriptTo: 0))
    // A stream is a stream whatever is on the disk for the episode.
    XCTAssertEqual(
      PlayDiary.start(isStream: true, hasFinishedAds: true, transcriptReached: 3600), .stream)
  }

  /// A feed can say any duration. A number too big for an Int must not stop the app.
  func testAnAbsurdlyLongTimeIsWrittenAndDoesNotCrash() throws {
    let play = PlayDiary.line(at: 1, episodeId: "e", start: .partly(transcriptTo: 1e30))
    XCTAssertEqual(try what(play), "play: partly, transcript to 1000000000 s")
    let done = PlayDiary.line(at: 1, episodeId: "e", audio: 1e300, work: 5, inBackground: false)
    XCTAssertEqual(try what(done), "1000000000 s of audio in 5.0 s, front")
  }

  func testAPlayLineSaysWhatThePhoneKnewWhenTheEpisodeStarted() throws {
    let ready = PlayDiary.line(at: 1_700_000_000.5, episodeId: "ab12cd34-ef56", start: .ready)
    XCTAssertEqual(try what(ready), "play: ready")
    XCTAssertEqual(try fields(ready)["kind"] as? String, "diary")
    XCTAssertEqual(try fields(ready)["episode"] as? String, "ab12cd34")
    XCTAssertEqual(try fields(ready)["time"] as? Double, 1_700_000_000.5)
    XCTAssertEqual(
      try what(PlayDiary.line(at: 1, episodeId: "e", start: .partly(transcriptTo: 239.6))),
      "play: partly, transcript to 240 s")
    XCTAssertEqual(
      try what(PlayDiary.line(at: 1, episodeId: "e", start: .stream)), "play: stream")
  }

  // MARK: How fast it transcribed

  func testATranscriptionLineSaysTheAudioTheWorkAndWhereItRan() throws {
    XCTAssertEqual(
      try what(
        PlayDiary.line(at: 1, episodeId: "e", audio: 3600.4, work: 214.26, inBackground: false)),
      "3600 s of audio in 214.3 s, front")
    XCTAssertEqual(
      try what(PlayDiary.line(at: 1, episodeId: "e", audio: 180, work: 9, inBackground: true)),
      "180 s of audio in 9.0 s, background")
  }

  func testARunWithNoAudioOrNoTimeMakesNoLine() {
    XCTAssertEqual(PlayDiary.line(at: 1, episodeId: "e", audio: 0, work: 5, inBackground: false), "")
    XCTAssertEqual(PlayDiary.line(at: 1, episodeId: "e", audio: 90, work: 0, inBackground: false), "")
    XCTAssertEqual(
      PlayDiary.line(at: 1, episodeId: "e", audio: -3, work: 4, inBackground: false), "")
    XCTAssertEqual(
      PlayDiary.line(at: 1, episodeId: "e", audio: .nan, work: 4, inBackground: false), "")
    XCTAssertEqual(
      PlayDiary.line(at: 1, episodeId: "e", audio: 60, work: .infinity, inBackground: false), "")
  }

  // MARK: The file's text

  func testThePlayLinesKeepTheirOwnLimitAndANewPlayOfTheSameEpisodeIsNotDropped() {
    var text =
      (1...PlayDiary.maxLines).map {
        PlayDiary.line(at: Double($0), episodeId: "e1", start: .stream)
      }.joined(separator: "\n") + "\n"
    for number in (PlayDiary.maxLines + 1)...(PlayDiary.maxLines + 10) {
      text = PlayDiary.appending(
        PlayDiary.line(at: Double(number), episodeId: "e1", start: .stream), to: text)
    }
    let lines = text.split(separator: "\n")
    XCTAssertEqual(lines.count, PlayDiary.maxLines)
    XCTAssertGreaterThan(PlayDiary.maxLines, AdDiary.maxLines)
    XCTAssertTrue(lines.last?.contains("\"time\":\(PlayDiary.maxLines + 10)") == true)
    // The ad diary drops a line that says what the last one says; a play never does.
    let one = PlayDiary.line(at: 5, episodeId: "e1", start: .ready)
    let twice = PlayDiary.appending(one, to: PlayDiary.appending(one, to: ""))
    XCTAssertEqual(twice.split(separator: "\n").count, 2)
    XCTAssertEqual(PlayDiary.appending("", to: one + "\n"), one + "\n")
  }

  func testTheSharedCopyHoldsThePlayLinesAfterTheDiaryAndTheirNumberIsNotTheDiarys() {
    let skip = "{\"kind\":\"skip\",\"episode\":\"e1\"}"
    let note = AdDiary.line(at: 2, episodeId: "e1", what: "first skip")
    let play = PlayDiary.line(at: 1, episodeId: "e1", start: .ready)
    let both = AdDiary.shared(skipLog: skip + "\n", diary: note + "\n", plays: play + "\n")
    XCTAssertEqual(both, [skip, note, play].joined(separator: "\n") + "\n")
    // Without play lines the copy is what it was.
    XCTAssertEqual(
      AdDiary.shared(skipLog: skip + "\n", diary: note + "\n"), [skip, note].joined(separator: "\n") + "\n")
    // A full ad diary is trimmed to 500 lines on its own, and the play lines stay.
    let diary = (1...600).map { AdDiary.line(at: Double($0), episodeId: "e1", what: "step \($0)") }
      .joined(separator: "\n")
    let kept = AdDiary.shared(
      skipLog: "", diary: AdDiary.trimmed(diary), plays: play + "\n")
    XCTAssertEqual(kept.split(separator: "\n").count, AdDiary.maxLines + 1)
    XCTAssertTrue(kept.contains("play: ready"))
  }
}
