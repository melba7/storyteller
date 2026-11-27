// LOFI-FORK: two finders that move skips with the cues the Mac learned (`ad-cues.json`): opening
// lines pull the start of a skip back to the line that opens the break, and filled holes close the
// short gap between two skips when the words of the gap belong to the ads (see FORK.md, AdCues.swift
// and the round plan, "Ad skipping: timing fixes"). Foundation and PodcastTranscripts only.
import Foundation
import PodcastTranscripts

public enum CueAds {
  /// An opening line may lie at most this many seconds before the skip it is pulled to. A minute:
  /// a longer pull cuts too much of the show when the line is not the start of an ad (on the
  /// teaching episodes about 1 matching line in 250 is not), and on the shelf no right pull was
  /// longer than 50 seconds.
  public static let reach = 60.0
  /// A hole between two skips is filled only when it is no longer than this.
  public static let longestHole = 60.0
  /// The hole's lines start from this long before its start to this long before its end.
  private static let edge = 0.2

  /// One stretch: the skips that overlap or touch, with the kind of the first of them.
  private struct Stretch {
    var start: Double
    var end: Double
    var kind: AdKind
  }

  /// The skips joined by time into stretches, whatever their kind. Skips that are not finite
  /// stretches are left out.
  private static func stretches(_ skips: [FoundAd]) -> [Stretch] {
    var result: [Stretch] = []
    let sound = skips.filter { $0.start.isFinite && $0.end.isFinite && $0.end > $0.start }
    for ad in sound.sorted(by: { $0.start < $1.start }) {
      if let last = result.last, ad.start <= last.end {
        result[result.count - 1].end = max(last.end, ad.end)
      } else {
        result.append(Stretch(start: ad.start, end: ad.end, kind: ad.kind))
      }
    }
    return result
  }

  /// The lines with a finite start, in order of time, and the words of each.
  private static func read(_ lines: [TranscriptLine]) -> (lines: [TranscriptLine], words: [[String]]) {
    let sound = lines.filter { $0.start.isFinite }.sorted { $0.start < $1.start }
    return (sound, sound.map { AdWordModel.tokens($0.text) })
  }

  private static func ad(
    _ start: Double, _ end: Double, _ kind: AdKind, words: [String], source: String
  ) -> FoundAd {
    FoundAd(
      start: start, end: end, kind: kind, advertiser: "", confidence: .unsure,
      firstWords: words.prefix(AdRules.firstWords).joined(separator: " "), source: source)
  }

  // MARK: Opening lines

  /// For each line, in order of time, that is outside every stretch and opens an ad on `show`: the
  /// stretch whose start is the nearest after the line, at most `reach` seconds later, is pulled
  /// back to the line, unless a return line starts between the two. What is returned is the
  /// stretch from the line to that start, as an unsure ad of the kind of the stretch's first ad.
  /// A stretch is pulled back once: after that the line lies inside it. Bad input adds nothing.
  public static func openings(
    lines: [TranscriptLine], skips: [FoundAd], cues: AdCues, show: String
  ) -> [FoundAd] {
    var stretches = stretches(skips)
    guard !cues.isEmpty, !stretches.isEmpty else { return [] }
    let (lines, words) = read(lines)
    let returning = lines.indices.filter { cues.returns(words[$0], show: show) }.map { lines[$0].start }
    var added: [FoundAd] = []
    for index in lines.indices where cues.opens(words[index], show: show) {
      let time = lines[index].start
      if stretches.contains(where: { $0.start <= time && time < $0.end }) { continue }
      let after = stretches.indices.filter {
        stretches[$0].start > time && stretches[$0].start - time <= reach
      }
      guard let next = after.min(by: { stretches[$0].start < stretches[$1].start }) else { continue }
      if returning.contains(where: { time < $0 && $0 < stretches[next].start }) { continue }
      added.append(
        ad(time, stretches[next].start, stretches[next].kind, words: words[index], source: ShowTuning.openingLines))
      stretches[next].start = time
    }
    return added
  }

  // MARK: Filled holes

  /// For two stretches next to each other with a hole of more than 0 and at most `longestHole`
  /// seconds between them and no return line in it: the hole is filled when (echo) a rare word of
  /// the hole is also in a line of one of the two stretches and in no line of the show outside the
  /// hole and the stretches, and (topic) at most a quarter of the hole's content words, counted as
  /// often as they occur, are in a line of the show outside the hole and the stretches. A filled
  /// hole is returned as an unsure ad of the kind of the stretch before it; the three then count as
  /// one stretch (for the echo of the next hole) and the next hole is looked at. The lines of the
  /// show are counted once, from the skips as they were given, so the lines of a hole that was
  /// filled still count as the show's for the holes after it. A hole with no content word is not
  /// filled. Call it with the skips plus what `openings` returned. Bad input adds nothing.
  public static func holes(
    lines: [TranscriptLine], skips: [FoundAd], cues: AdCues, show: String
  ) -> [FoundAd] {
    let first = stretches(skips)
    guard !cues.isEmpty, first.count >= 2 else { return [] }
    let (lines, words) = read(lines)
    let content = words.map { $0.filter(cues.isContent) }
    let returning = lines.indices.filter { cues.returns(words[$0], show: show) }.map { lines[$0].start }
    // The lines outside every stretch as the skips stood at the start, and how many of them
    // each word is in.
    let counted = lines.map { line in !first.contains { $0.start <= line.start && line.start < $0.end } }
    var inShow: [String: Int] = [:]
    for index in lines.indices where counted[index] {
      for word in Set(content[index]) { inShow[word, default: 0] += 1 }
    }
    var stretches = first
    var added: [FoundAd] = []
    var at = 0
    while at + 1 < stretches.count {
      let before = stretches[at]
      let after = stretches[at + 1]
      let gap = after.start - before.end
      let inHole = lines.indices.filter {
        before.end - edge <= lines[$0].start && lines[$0].start < after.start - edge
      }
      let holeWords = inHole.flatMap { content[$0] }
      if gap > 0, gap <= longestHole, !holeWords.isEmpty,
        !returning.contains(where: { before.end <= $0 && $0 < after.start })
      {
        var outside = inShow
        for index in inHole where counted[index] {
          for word in Set(content[index]) { outside[word, default: 0] -= 1 }
        }
        let known = holeWords.filter { outside[$0, default: 0] >= 1 }.count
        var near: Set<String> = []
        for (index, line) in lines.enumerated() {
          let inside =
            (before.start <= line.start && line.start < before.end)
            || (after.start <= line.start && line.start < after.end)
          if inside { near.formUnion(content[index].filter(cues.isRare)) }
        }
        let echo = Set(holeWords.filter(cues.isRare)).contains {
          near.contains($0) && outside[$0, default: 0] == 0
        }
        if echo, known * 4 <= holeWords.count {
          added.append(
            ad(before.end, after.start, before.kind, words: words[inHole[0]], source: ShowTuning.filledHoles))
          stretches[at].end = after.end
          stretches.remove(at: at + 1)
          continue
        }
      }
      at += 1
    }
    return added
  }
}
