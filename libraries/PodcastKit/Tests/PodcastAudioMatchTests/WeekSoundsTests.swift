import XCTest

@testable import PodcastAudioMatch

/// This week's ad sounds: which episodes a test episode may learn from (published at least 1 day and
/// at most 7 days before it), and what a sound bank of those gives. Made-up banks and made MP3 bytes.
final class WeekSoundsTests: XCTestCase {
  private var folder: URL!
  private let day = 86_400.0
  private let frame = 1152.0 / 44100

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("week-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  private func episode(_ id: String, _ published: Double?) -> WeekEpisode {
    WeekEpisode(id: id, published: published)
  }

  // MARK: The window

  func testOnlyEpisodesFromOneToSevenDaysBeforeAreInTheWindow() {
    let target = episode("target", 10 * day)
    let others = [
      episode("sameMoment", 10 * day),
      episode("later", 11 * day),
      episode("twelveHours", 9.5 * day),
      episode("exactlyOneDay", 9 * day),
      episode("threeDays", 7 * day),
      episode("exactlySevenDays", 3 * day),
      episode("sevenAndABit", 3 * day - 1),
      episode("tenDays", 0),
      episode("noDate", nil),
    ]
    XCTAssertEqual(
      WeekSounds.window(for: target, among: others + [target]),
      ["exactlySevenDays", "threeDays", "exactlyOneDay"])
  }

  func testAnEpisodeWithNoDateLearnsFromNothing() {
    XCTAssertEqual(WeekSounds.window(for: episode("a", nil), among: [episode("b", 5 * day)]), [])
  }

  func testTheWindowIsOldestFirstAndTiesGoByTheId() {
    let others = [episode("b", 8 * day), episode("a", 8 * day), episode("c", 7 * day)]
    XCTAssertEqual(WeekSounds.window(for: episode("t", 10 * day), among: others), ["c", "a", "b"])
  }

  // MARK: The episode list

  func testTheEpisodeListGivesIdsAndDatesAndLeavesOutWhatIsNotAnEpisode() throws {
    let json = """
      {"version": 1, "episodes": [
        {"id": "aaaaaaaaaaaa", "published": 1700000000},
        {"id": "bbbbbbbbbbbb", "published": 1700000000.5},
        {"id": "cccccccccccc", "published": null},
        {"id": "dddddddddddd"},
        {"published": 5},
        {"id": "", "published": 5},
        "x"
      ]}
      """
    try json.write(to: folder.appendingPathComponent("episodes.json"), atomically: true, encoding: .utf8)
    XCTAssertEqual(
      WeekSounds.episodes(in: folder),
      [
        episode("aaaaaaaaaaaa", 1_700_000_000), episode("bbbbbbbbbbbb", 1_700_000_000.5),
        episode("cccccccccccc", nil), episode("dddddddddddd", nil),
      ])
  }

  func testNoEpisodeListOrADamagedOneGivesNoEpisodes() throws {
    XCTAssertEqual(WeekSounds.episodes(in: folder), [])
    try "{".write(to: folder.appendingPathComponent("episodes.json"), atomically: true, encoding: .utf8)
    XCTAssertEqual(WeekSounds.episodes(in: folder), [])
  }

  // MARK: The sounds

  private func bytes(_ parts: Range<Int>...) -> [UInt8] {
    Fake.id3(size: 300) + parts.flatMap { Marked.frames($0) }
  }

  /// Banks the ad in frames 500 to 1100 of an episode of made frames.
  private func bank(_ id: String, _ parts: Range<Int>...) throws {
    let frames = MP3Frames.parse(parts.flatMap { Marked.frames($0) }).frames
    let marked = [MarkedStretch(start: 500 * frame, end: 1100 * frame, sort: "sponsor", who: "Acme")]
    try SoundBank.save(AdSoundBuilder.slice(frames: frames, marked: marked), episode: id, in: folder)
  }

  func testTheLibraryHoldsOnlyTheSoundsOfTheWindowEpisodes() throws {
    // Each episode's ad is frames 500 to 1100: a different one in each.
    try bank("week", 10_000..<10_500, 50_000..<50_600, 10_500..<11_000)
    try bank("old", 20_000..<20_500, 60_000..<60_600, 20_500..<21_000)
    let among = [episode("week", 5 * day), episode("old", 0), episode("target", 10 * day)]
    let library = WeekSounds.library(for: episode("target", 10 * day), among: among, in: folder)
    XCTAssertEqual(library.sounds.count, 1)
    XCTAssertEqual(library.sounds.first?.who, "Acme")
    // An episode that has no bank file adds nothing and breaks nothing.
    let more = among + [episode("noBank", 8 * day)]
    XCTAssertEqual(WeekSounds.library(for: episode("target", 10 * day), among: more, in: folder).sounds.count, 1)
  }

  func testASoundOfTheWeekIsFoundInTheEpisodeAndAnOlderOneIsNot() throws {
    try bank("week", 10_000..<10_500, 50_000..<50_600, 10_500..<11_000)
    try bank("old", 20_000..<20_500, 60_000..<60_600, 20_500..<21_000)
    // The target plays the week's ad at frames 1000 to 1600 and the old ad after it.
    let audio = folder.appendingPathComponent("target.mp3")
    try Data(bytes(30_000..<31_000, 50_000..<50_600, 31_000..<31_300, 60_000..<60_600, 32_000..<32_100))
      .write(to: audio)
    let among = [episode("week", 5 * day), episode("old", 0), episode("target", 10 * day)]
    let spans = WeekSounds.spans(in: audio, for: episode("target", 10 * day), among: among, folder: folder)
    XCTAssertEqual(spans.count, 1)
    // The bank leaves a margin off each end of the marked stretch, so the sound is a little inside it.
    XCTAssertEqual(spans.first?.start ?? 0, 1000 * frame + AdSoundBuilder.margin, accuracy: 0.3)
    XCTAssertEqual(spans.first?.end ?? 0, 1600 * frame - AdSoundBuilder.margin, accuracy: 0.3)
    XCTAssertEqual(spans.first?.sort, "sponsor")
  }

  func testWithNothingInTheWindowTheEpisodeGetsNoSpans() throws {
    try bank("old", 20_000..<20_500, 60_000..<60_600, 20_500..<21_000)
    let audio = folder.appendingPathComponent("target.mp3")
    try Data(bytes(30_000..<31_000, 60_000..<60_600)).write(to: audio)
    let among = [episode("old", 0), episode("target", 10 * day)]
    XCTAssertEqual(
      WeekSounds.spans(in: audio, for: episode("target", 10 * day), among: among, folder: folder), [])
  }
}
