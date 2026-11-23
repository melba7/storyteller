// LOFI-FORK: moves the borders of a found ad onto the joints of the MP3 file (see FORK.md).
//
// Where a host splices an ad into an episode, the frames show a joint: the encoding changes, an Xing
// or Info tag sits in the middle of the file, or the bit reservoir starts empty. `SeekDrift` lists
// these for a file that is parsed whole. `JointFinder` finds the same joints in one pass over frames
// that arrive in pieces, and `JointSnap` moves the start or the end of an ad onto a joint that
// lies close to it, so the skip begins at the ad's first frame and lands on the show's first.
// Foundation only.
import Foundation

/// The joints of one file, as `JointFinder` found them.
public struct Joints: Equatable, Sendable {
  /// Seconds from the first frame, in order, each time once.
  public var times: [Double]
  /// The length of the audio that was looked at.
  public var seconds: Double
  /// Whether `SeekDriftReport.steady` would call the file steady (one bitrate for 99% of it).
  public var steady: Bool
  /// Whether there were more joints than `JointFinder` keeps, so `times` is not all of them.
  public var overflowed: Bool

  public init(times: [Double], seconds: Double, steady: Bool, overflowed: Bool = false) {
    self.times = times
    self.seconds = seconds
    self.steady = steady
    self.overflowed = overflowed
  }

  /// Whether `JointSnap` uses the file by default: `usable(steadyToo: false)`.
  public var usable: Bool { usable(steadyToo: false) }

  /// Whether `JointSnap` may use the file at all. It does not for a file with more than
  /// `JointSnap.maxPerHour` joints an hour (then a joint says little: the file is joined
  /// everywhere), nor for one that overflowed or has no joint. Audio shorter than
  /// `JointSnap.shortestWindow` counts as that long, so one or two joints in the first minutes of
  /// a stream do not make a file look busy. A steady file is used only when `steadyToo` is true.
  public func usable(steadyToo: Bool) -> Bool {
    guard steadyToo || !steady, !overflowed, seconds.isFinite, seconds > 0, !times.isEmpty
    else { return false }
    return Double(times.count) * 3600 <= JointSnap.maxPerHour * max(seconds, JointSnap.shortestWindow)
  }
}

/// Finds the joints of an MP3 file in one pass: frames go in as they come, in order, in as many
/// calls as you like, and `joints` can be read at any point. What it holds does not grow with the
/// file: a few counters, one entry for each bitrate (a frame has one of 18) and at most
/// `keepLimit` joint times.
///
/// A joint is what `SeekDrift.report` lists, with the same rules and the same constants: a change
/// of bitrate, sample rate or channels that holds for `SeekDrift.seamFrames` frames; an Xing or
/// Info tag in a frame after the first; and a frame with an empty bit reservoir after
/// `SeekDrift.resetAfter` frames that reach into it. Two signs at one frame are one joint. The
/// tests compare it with `SeekDrift.report` on made files, so the two cannot drift apart.
public struct JointFinder: Sendable {
  /// At most this many joint times are kept. A file that has more is busy anyway.
  public static let keepLimit = 2000

  private struct Header: Equatable, Sendable {
    var bitrate: Int
    var sampleRate: Int
    var channels: Int

    init(_ frame: MP3Frame) {
      bitrate = frame.bitrate
      sampleRate = frame.sampleRate
      channels = frame.channels
    }
  }

  private var found: [Double] = []
  private var overflowed = false
  private var count = 0  // frames fed so far
  private var seconds = 0.0
  private var perBitrate: [Int: Int] = [:]
  private var run: Header?  // the header of the frames just fed
  private var runStart = 0.0  // where that run began
  private var runLength = 0
  private var held: Header?  // the header of the last run that held for `seamFrames` frames
  private var reaching = 0  // frames in a row that reach back into the reservoir

  public init() {}

  public mutating func feed(_ frames: [MP3Frame]) {
    for frame in frames { feed(frame) }
  }

  public mutating func feed(_ frame: MP3Frame) {
    defer { count += 1 }
    let end = frame.start + frame.duration
    if end.isFinite, end > seconds { seconds = end }
    perBitrate[frame.bitrate, default: 0] += 1

    let header = Header(frame)
    if header == run {
      runLength += 1
    } else {
      run = header
      runStart = frame.start
      runLength = 1
    }
    // A run counts once it has held for `seamFrames` frames; as in `SeekDrift`, its joint is its
    // first frame.
    if runLength == SeekDrift.seamFrames {
      if let held, held != header { add(runStart) }
      held = header
    }

    if frame.hasInfoTag, count > 0 { add(frame.start) }

    if let pointer = frame.mainDataBegin {
      if pointer > 0 {
        reaching += 1
      } else {
        if reaching >= SeekDrift.resetAfter { add(frame.start) }
        reaching = 0
      }
    } else {
      reaching = 0
    }
  }

  /// The joints of the frames fed so far.
  public var joints: Joints {
    var times: [Double] = []
    for time in found.sorted() where time != times.last { times.append(time) }
    let most = perBitrate.values.max() ?? 0
    return Joints(
      times: times, seconds: seconds,
      steady: count > 0 && Double(most) >= SeekDrift.steadyShare * Double(count),
      overflowed: overflowed)
  }

  private mutating func add(_ time: Double) {
    guard time.isFinite, time >= 0 else { return }
    if found.count < JointFinder.keepLimit { found.append(time) } else { overflowed = true }
  }
}

public enum JointSnap {
  /// How far a start may move to a joint before it or after it, in seconds.
  public static let startEarlier = 3.0
  public static let startLater = 1.0
  /// The same for an end.
  public static let endEarlier = 2.0
  public static let endLater = 4.0
  /// A file with more joints than this an hour is not used.
  public static let maxPerHour = 60.0
  /// Audio shorter than this counts as this long when joints an hour are worked out.
  public static let shortestWindow = 600.0

  /// Two distances this close (in seconds) are the same distance.
  private static let tie = 1e-6
  /// What a time may be off its window's edge and still count (rounding of seconds).
  private static let slack = 1e-9

  /// The start and the end of one ad stretch, each moved onto the nearest joint inside its
  /// window. Each border is looked at on its own against the borders as they were given. Two joints
  /// that are as near go to the earlier one.
  ///
  /// A border never moves outside 0 to the length of the file, a start never goes before
  /// `previousEnd` (where the ad before this one ends) and an end never goes after `nextStart`
  /// (where the ad after it starts). Touching a neighbour is allowed. A snap that would leave the
  /// start at or after the end moves neither. A file that is not usable (see
  /// `Joints.usable(steadyToo:)`) and any number that is not finite or is below 0 give the stretch
  /// back as it came. A steady file is not used unless `steadyToo` is true; the busy rule and
  /// `overflowed` hold either way.
  public static func snap(
    start: Double, end: Double, joints: Joints, previousEnd: Double? = nil,
    nextStart: Double? = nil, steadyToo: Bool = false
  ) -> (start: Double, end: Double) {
    let unchanged = (start: start, end: end)
    guard start.isFinite, end.isFinite, start >= 0, end > start,
      joints.usable(steadyToo: steadyToo),
      isLimit(previousEnd), isLimit(nextStart)
    else { return unchanged }
    let after = previousEnd ?? 0
    let before = nextStart ?? .infinity
    let first = nearest(to: start, earlier: startEarlier, later: startLater, in: joints) {
      $0 >= after && $0 < end
    }
    let last = nearest(to: end, earlier: endEarlier, later: endLater, in: joints) {
      $0 > start && $0 <= before
    }
    let moved = (start: first ?? start, end: last ?? end)
    return moved.start < moved.end ? moved : unchanged
  }

  private static func isLimit(_ limit: Double?) -> Bool {
    guard let limit else { return true }
    return limit.isFinite && limit >= 0
  }

  /// The joint nearest to `border` among those inside its window and inside the file that
  /// `allowed` accepts, the earlier one when two are as near.
  private static func nearest(
    to border: Double, earlier: Double, later: Double, in joints: Joints,
    allowed: (Double) -> Bool
  ) -> Double? {
    var best: Double?
    for joint in joints.times
    where joint.isFinite && joint >= 0 && joint <= joints.seconds
      && joint >= border - earlier - slack && joint <= border + later + slack && allowed(joint) {
      guard let held = best else {
        best = joint
        continue
      }
      let near = abs(joint - border)
      let heldNear = abs(held - border)
      if near < heldNear - tie || (abs(near - heldNear) <= tie && joint < held) { best = joint }
    }
    return best
  }
}
