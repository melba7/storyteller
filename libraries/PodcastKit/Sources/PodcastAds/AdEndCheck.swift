// LOFI-FORK: the ad-end check: a skip's end moves on while the next transcript lines still sell
// (see FORK.md, CueAds.swift and docs/PLAN.md, Z12). Foundation and PodcastTranscripts only.
//
// A skip often ends a line or two early: the read is over for the finder, but the host still gives
// the promo code or spells the web address. So after the phone's finders made their ends, the lines
// that start within `reach` seconds after an end are read. While they carry a cue, the end moves to
// the end of the last cue line. One line without a cue may lie between two cue lines. The cues and
// the limits were picked on 1,170 teaching episodes and passed the test on the shelf; do not
// change one without running that test again. The idea follows MinusPod (MIT,
// github.com/ttlequals0/MinusPod); see FORK.md.
//
// It is for the phone's own finders. A mark of the Mac (`ShowTuning.ahead`) is left alone, because
// Claude read those lines already, and a prepared copy never comes here. A mark that was joined with
// an ad of the phone has lost its finder's name (`AdJoin`), so the caller also hands over the marks
// themselves: an end that is a mark's end stays as well.
import Foundation
import PodcastTranscripts

public enum AdEndCheck {
  /// An end moves at most this many seconds, and only lines that start within it are read.
  public static let reach = 15.0
  /// This many lines in a row without a cue may be passed over.
  static let bridged = 1
  /// The first line read is the one still spoken this long after the end.
  static let into = 1.0
  /// What is added carries the name of the filled holes: on the phone it runs with them, under
  /// their mark and their level, and an Undo takes back only this stretch (`AdSkip.takenBack`).
  static let source = ShowTuning.filledHoles
  /// A mark of the Mac ends a stretch when its end is this close to the stretch's end (the
  /// distance `AdJoin` calls touching).
  static let markSlack = 0.5

  /// The cues: a promo code, a web address, "com slash word", the terms, and "that's word dot com".
  private static let cues = AdSignals.regexes([
    #"\b(?:promo|discount|offer|coupon|use|enter|with|the)\s+code\b|\bcode\s+\w+\s+(?:at|for|to get)\b"#,
    #"\b[a-z0-9][a-z0-9-]{2,}\s?(?:\.|\sdot\s)\s?(?:com|co|org|net|io|ai|app|shop|tv|fm|us)\b"#,
    #"\b(?:com|org|net|co|io)\s?(?:/|\sslash\s)\s?\w+"#,
    #"\bterms (?:and conditions )?apply\b|\brestrictions apply\b|\bsee (?:site|website) for details\b|\bmember fdic\b|\bexclusions apply\b"#,
    #"\b(?:that's|that is|again,? that's)\s+[a-z0-9-]+\s?(?:\.|\sdot\s)\s?com\b"#,
  ])

  /// Whether a line carries one of the cues.
  static func sells(_ text: String) -> Bool {
    AdSignals.matches(cues, text)
  }

  /// Where an end at `end` moves to (`end` itself when it stays). `starts` are the lines' starts in
  /// order of time, `sells` says which lines carry a cue and `last` is where the transcript ends. A
  /// line ends where the next one starts. The walk begins at the line that is spoken `into`
  /// seconds after the end and goes on while the lines start within `reach`; it stops after more
  /// than `bridged` lines in a row without a cue.
  static func moved(_ end: Double, starts: [Double], sells: [Bool], last: Double) -> Double {
    guard end < last - 0.01, !starts.isEmpty else { return end }
    func endOf(_ index: Int) -> Double { index + 1 < starts.count ? starts[index + 1] : last }
    var index = max(0, starts.prefix { $0 <= end + into }.count - 1)
    if endOf(index) <= end + into { index += 1 }
    var result = end
    var missed = 0
    while index < starts.count, starts[index] - end < reach {
      if sells[index] {
        result = max(result, min(endOf(index), end + reach))
        missed = 0
      } else {
        missed += 1
        if missed > bridged { break }
      }
      index += 1
    }
    return result
  }

  /// The skips joined by time into stretches, each with the skips that end where the stretch ends.
  private static func joined(_ skips: [FoundAd]) -> [(start: Double, end: Double, closing: [FoundAd])] {
    var result: [(start: Double, end: Double, closing: [FoundAd])] = []
    let sound = skips.filter { $0.start.isFinite && $0.end.isFinite && $0.end > $0.start }
    for ad in sound.sorted(by: { $0.start < $1.start }) {
      guard let before = result.last, ad.start <= before.end else {
        result.append((ad.start, ad.end, [ad]))
        continue
      }
      if ad.end > before.end + 0.01 {
        result[result.count - 1] = (before.start, ad.end, [ad])
      } else if ad.end >= before.end - 0.01 {
        result[result.count - 1].end = max(before.end, ad.end)
        result[result.count - 1].closing.append(ad)
      }
    }
    return result
  }

  /// What the check adds to `skips`: for each stretch of skips that overlap or touch, the stretch
  /// from its end to where the end moves, as an unsure ad of the kind of the skip that ends there.
  /// It never reaches into the next stretch, and nothing is added after a stretch that a mark of
  /// the Mac ends: a skip with the Mac's name that closes it, or one of `marks` (the Mac's marks in
  /// this copy's seconds) that lies in it and ends within `markSlack` of its end. Lines and skips
  /// that are not finite are left out. Bad input adds nothing.
  public static func stretches(
    lines: [TranscriptLine], skips: [FoundAd], marks: [FoundAd] = []
  ) -> [FoundAd] {
    let lines = lines.filter { $0.start.isFinite }.sorted { $0.start < $1.start }
    let joined = Self.joined(skips)
    guard let final = lines.last, !joined.isEmpty else { return [] }
    let starts = lines.map(\.start)
    let sells = lines.map { Self.sells($0.text) }
    // The transcript ends where its last word does.
    let last = max(final.start, lines.map(\.end).filter(\.isFinite).max() ?? final.start)
    var added: [FoundAd] = []
    for (index, stretch) in joined.enumerated() {
      guard let closing = stretch.closing.first,
        !stretch.closing.contains(where: { $0.source == ShowTuning.ahead }),
        !marks.contains(where: {
          $0.start < stretch.end && $0.end > stretch.start
            && abs($0.end - stretch.end) <= markSlack
        })
      else { continue }
      var end = moved(stretch.end, starts: starts, sells: sells, last: last)
      if index + 1 < joined.count { end = min(end, joined[index + 1].start) }
      guard end > stretch.end else { continue }
      added.append(
        FoundAd(
          start: stretch.end, end: end, kind: closing.kind, advertiser: "", confidence: .unsure,
          firstWords: "", source: source))
    }
    return added
  }
}
