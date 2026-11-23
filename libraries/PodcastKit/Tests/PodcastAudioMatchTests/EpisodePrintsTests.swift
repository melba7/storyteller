import XCTest

@testable import PodcastAudioMatch

final class EpisodePrintsTests: XCTestCase {
  // MARK: the print

  func testThePrintHoldsTheLow32BitsOfEveryEighthFrame() {
    let ids = Array(0..<100)
    let frames = Snd.frames(ids)
    var builder = EpisodePrintBuilder()
    builder.feed(frames)
    let print = builder.finish(episode: "e1", date: 5)
    XCTAssertEqual(print.anchors.count, 13)
    // The same numbers the Mac's sound library holds for a sound made of these frames.
    XCTAssertEqual(print.anchors, Snd.sound(ids).anchors)
    XCTAssertEqual(print.episode, "e1")
    XCTAssertEqual(print.date, 5)
    XCTAssertEqual(print.frames, 100)
    XCTAssertEqual(print.seconds, Snd.time(100), accuracy: 1e-9)
  }

  func testFramesFedInPiecesGiveTheSamePrint() {
    let ids = Array(0..<1001)
    let whole = Rep.print(ids, pieces: ids.count)
    for pieces in [1, 3, 8, 9, 500] {
      XCTAssertEqual(Rep.print(ids, pieces: pieces), whole, "pieces \(pieces)")
    }
  }

  func testNothingFedGivesAnEmptyPrintAndBadTimesDoNotBreakIt() {
    let empty = EpisodePrintBuilder().finish(episode: "e", date: .nan)
    XCTAssertEqual(empty.anchors, [])
    XCTAssertEqual(empty.frames, 0)
    XCTAssertEqual(empty.seconds, 0)
    XCTAssertEqual(empty.date, 0)
    var frames = Snd.frames(Array(0..<20))
    frames[3].start = .nan
    frames[4].duration = .infinity
    var builder = EpisodePrintBuilder()
    builder.feed(frames)
    let print = builder.finish(episode: "e", date: 1)
    XCTAssertEqual(print.anchors.count, 3)
    XCTAssertTrue(print.seconds.isFinite)
  }

  func testAnHourIsAboutSixtyNineKilobytes() {
    // 137,800 frames of 26 ms are an hour; one number of 4 bytes for every eighth frame.
    let print = Rep.print(Array(0..<137_800), episode: "hour", pieces: 8192)
    XCTAssertEqual(print.anchors.count, 17_225)
    let size = ShowPrints(prints: [print]).data().count
    XCTAssertGreaterThan(size, 68_900)
    XCTAssertLessThan(size, 69_100)
  }

  func testALongFileIsPrintedOnlyUpToTheLimit() {
    var builder = EpisodePrintBuilder()
    var next = 0
    while next < 900_000 {
      var frames = Snd.frames(Array(next..<next + 50_000))
      for place in frames.indices { frames[place].start += Snd.time(next) }
      builder.feed(frames)
      next += 50_000
    }
    let print = builder.finish(episode: "long", date: 1)
    XCTAssertEqual(print.anchors.count, EpisodePrint.maxAnchors)
    XCTAssertEqual(print.frames, EpisodePrint.maxAnchors * EpisodePrint.step)
    XCTAssertEqual(print.seconds, Snd.time(EpisodePrint.maxFrames), accuracy: 1e-6)
    XCTAssertEqual(ShowPrints(data: ShowPrints(prints: [print]).data()).prints, [print])
  }

  // MARK: the prints of one show

  private func print(_ episode: String, date: Double, tag: Int = 0) -> EpisodePrint {
    Rep.print(Rep.filler(tag + 1, 200), episode: episode, date: date)
  }

  func testAShowKeepsTheNewestThreeEpisodes() {
    var show = ShowPrints()
    for day in 1...5 { show = show.adding(print("e\(day)", date: Double(day))) }
    XCTAssertEqual(show.prints.map(\.episode), ["e5", "e4", "e3"])
    // An episode older than all three is not kept, and one in between takes the oldest's place.
    XCTAssertEqual(show.adding(print("e0", date: 0)).prints.map(\.episode), ["e5", "e4", "e3"])
    XCTAssertEqual(show.adding(print("e4b", date: 4.5)).prints.map(\.episode), ["e5", "e4b", "e4"])
  }

  func testAnEpisodeAddedAgainReplacesItself() {
    let first = print("e1", date: 1, tag: 1)
    let again = print("e1", date: 1, tag: 2)
    let show = ShowPrints().adding(first).adding(print("e2", date: 2)).adding(again)
    XCTAssertEqual(show.prints.map(\.episode), ["e2", "e1"])
    XCTAssertEqual(show.prints.last, again)
  }

  func testAPrintWithNoIdOrNoAnchorsIsNotKept() {
    let show = ShowPrints().adding(print("e1", date: 1))
    XCTAssertEqual(show.adding(print("", date: 2)), show)
    let bare = EpisodePrint(episode: "e2", date: 2, frames: 0, seconds: 0, anchors: [])
    XCTAssertEqual(show.adding(bare), show)
    let long = String(repeating: "x", count: 1000)
    XCTAssertEqual(show.adding(print(long, date: 3)), show)
  }

  func testTheOlderPrintsToScanAgainstLeaveOutTheEpisodeBeingScanned() {
    let show = ShowPrints().adding(print("e1", date: 1)).adding(print("e2", date: 2))
    XCTAssertEqual(show.prints(excluding: "e2").map(\.episode), ["e1"])
    XCTAssertEqual(show.prints(excluding: "e9").map(\.episode), ["e2", "e1"])
  }

  func testTheFileReadsBackAsItWasWritten() {
    let show = ShowPrints().adding(print("épisode 1", date: 1.5)).adding(print("e2", date: 2))
    let data = show.data()
    XCTAssertEqual(ShowPrints(data: data), show)
    XCTAssertEqual(ShowPrints(data: ShowPrints().data()), ShowPrints())
  }

  // MARK: damage

  /// A file of `body` with its checksum, as `ShowPrints.data()` makes it.
  private func sealed(_ body: [UInt8]) -> Data {
    var bytes = body
    let sum = ShowPrints.checksum(body)
    bytes += (0..<4).map { UInt8(truncatingIfNeeded: sum >> (8 * UInt32($0))) }
    return Data(bytes)
  }

  func testADamagedFileReadsAsEmpty() {
    let show = ShowPrints().adding(print("e1", date: 1)).adding(print("e2", date: 2))
    let bytes = [UInt8](show.data())
    XCTAssertEqual(ShowPrints(data: Data(bytes)), show)
    XCTAssertEqual(ShowPrints(data: Data()), ShowPrints())
    XCTAssertEqual(ShowPrints(data: Data("not a print file".utf8)), ShowPrints())
    for length in 0..<bytes.count {
      XCTAssertEqual(ShowPrints(data: Data(bytes[0..<length])), ShowPrints(), "cut at \(length)")
    }
    XCTAssertEqual(ShowPrints(data: Data(bytes + [0])), ShowPrints())
    for place in 0..<bytes.count {
      var broken = bytes
      broken[place] ^= 0x10
      XCTAssertEqual(ShowPrints(data: Data(broken)), ShowPrints(), "byte \(place)")
    }
  }

  func testAFileOfAnotherVersionOrWithTooManyEpisodesReadsAsEmpty() {
    let show = ShowPrints().adding(print("e1", date: 1))
    let body = Array([UInt8](show.data()).dropLast(4))
    XCTAssertEqual(ShowPrints(data: sealed(body)), show)  // the sealing is right
    guard body.count > 12 else { return }
    var other = body
    other[4] = 2  // version 2
    XCTAssertEqual(ShowPrints(data: sealed(other)), ShowPrints())
    var many = body
    many[8] = 4  // four episodes, though the data holds one
    XCTAssertEqual(ShowPrints(data: sealed(many)), ShowPrints())
    var tag = body
    tag[0] = 0x58  // another kind of file
    XCTAssertEqual(ShowPrints(data: sealed(tag)), ShowPrints())
  }

  func testAFileOfTheWrongSizeReadsAsEmpty() {
    let huge = Data(count: ShowPrints.maxBytes + 1)
    XCTAssertEqual(ShowPrints(data: huge), ShowPrints())
  }
}
