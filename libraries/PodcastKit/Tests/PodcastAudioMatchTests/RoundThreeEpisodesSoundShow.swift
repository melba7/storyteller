import Foundation
import XCTest

@testable import PodcastAudioMatch

/// The made show of the whole-round sound test: four MP3 files of one show, built from numbers.
/// The show itself is 128 kbps. Each standing ad is encoded on its own at 64 kbps, as a host
/// splices it in, so the audio really changes at its first and its last frame (a joint). Two
/// ads stand in the show: ACME (18.3 s) and BETA (13.1 s). A frame is told apart by an id, so the
/// ad's bytes are the same in every episode and the show's bytes are never the same twice.
enum RoundSound {
  /// One frame is 1152 / 44100 s long, at 64 and at 128 kbps alike.
  static let frame = 1152.0 / 44100
  static let show = "round-show"
  /// The time the phone learns at: seconds since 1970.
  static let now = 1_700_000_000.0

  /// The frame ids of the two standing ads.
  static let acme = 50_000..<50_700
  static let beta = 60_000..<60_500

  /// One piece of an episode: some frames of the show itself (fresh ids), or a standing ad.
  enum Part {
    case show(frames: Int)
    case acme
    case beta
    /// An ad that only plays in one episode, with its own ids.
    case delta
  }

  static let delta = 70_000..<70_600

  /// An episode: its bytes, and for each ad where it starts and ends (in frames, then in seconds).
  struct Episode {
    var bytes: [UInt8] = []
    var places: [String: Range<Int>] = [:]

    func start(_ ad: String) -> Double { Double(places[ad]?.lowerBound ?? 0) * frame }
    func end(_ ad: String) -> Double { Double(places[ad]?.upperBound ?? 0) * frame }
  }

  /// A frame of a standing ad: 64 kbps, with the id written into its bytes.
  static func adFrame(_ id: Int) -> [UInt8] {
    var bytes = Synth.frame(kbps: 64)
    bytes[100] = UInt8(id & 0xFF)
    bytes[101] = UInt8(id >> 8 & 0xFF)
    bytes[102] = UInt8(id >> 16 & 0xFF)
    return bytes
  }

  /// The episode number `number` made of `parts` in order, behind an ID3 tag like a real file.
  static func episode(_ number: Int, _ parts: [Part]) -> Episode {
    var made = Episode()
    made.bytes = Fake.id3(size: 300)
    var count = 0
    var fresh = number * 1_000_000
    func ad(_ name: String, _ ids: Range<Int>) {
      made.places[name] = count..<(count + ids.count)
      made.bytes += ids.flatMap { adFrame($0) }
      count += ids.count
    }
    for part in parts {
      switch part {
      case .show(let frames):
        made.bytes += Marked.frames(fresh..<(fresh + frames))
        fresh += frames
        count += frames
      case .acme: ad("acme", acme)
      case .beta: ad("beta", beta)
      case .delta: ad("delta", delta)
      }
    }
    return made
  }

  // The three episodes of the show, and a fourth one for an ad that is met for the first time in
  // the third. ACME and BETA play in the first three, at other places each time.
  static let one = episode(1, [.show(frames: 2000), .acme, .show(frames: 1500), .beta, .show(frames: 1000)])
  static let two = episode(2, [.show(frames: 1200), .beta, .show(frames: 2500), .acme, .show(frames: 800)])
  static let three = episode(
    3, [.show(frames: 3000), .acme, .show(frames: 1200), .beta, .show(frames: 900), .delta, .show(frames: 800)])
  static let four = episode(4, [.show(frames: 1500), .delta, .show(frames: 500)])
}

/// What the phone does with a downloaded episode's file and the ads the words found in it, in
/// the order of the round plan: the joints of the file, the snap of the found borders onto them,
/// the scan with the phone's own sounds (which the episodes before taught), and only then the
/// learning of the sure ads that were not undone.
class RoundSoundCase: XCTestCase {
  var folder: URL!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("round-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }
  override func tearDown() { try? FileManager.default.removeItem(at: folder) }

  func write(_ episode: RoundSound.Episode, as name: String) throws -> URL {
    let url = folder.appendingPathComponent(name)
    try Data(episode.bytes).write(to: url)
    return url
  }

  /// The ad as the words found it: the borders are off by a second or so, in the directions
  /// real transcripts are off (a late start, an early end).
  func found(_ episode: RoundSound.Episode, _ ad: String, late: Double, early: Double) -> SoundSpan {
    SoundSpan(start: episode.start(ad) + late, end: episode.end(ad) - early)
  }

  /// One episode through the phone's steps. `found` are the sure ads that the older finders gave,
  /// borders as they came; `undone` are those the listener took back, which are not learned.
  /// Returns what the phone's own sounds found in the file before they learned from it, and the
  /// stretches as the joint snap put them.
  @discardableResult
  func phone(
    _ url: URL, _ own: inout OwnAdSounds, found: [SoundSpan], undone: [SoundSpan] = []
  ) throws -> (hits: [SoundSpan], snapped: [SoundSpan]) {
    let joints = try XCTUnwrap(ScoreSounds.joints(in: url))
    let snapped = ScoreSounds.snap(found, joints: joints, steadyToo: false)
    let kept = zip(found, snapped).filter { pair in !undone.contains(pair.0) }.map(\.1)
    let stretches = kept.map { MarkedStretch(start: $0.start, end: $0.end, sort: $0.sort, who: "") }
    let hits = ScoreSounds.scanThenLearn(
      &own, show: RoundSound.show, in: url, stretches: stretches, now: RoundSound.now)
    return (hits, snapped)
  }
}
