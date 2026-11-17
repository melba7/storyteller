import Foundation

@testable import PodcastAds
@testable import PodcastTranscripts

/// A transcript of lines of ten seconds each: line n (counted from 1) covers seconds
/// (n-1)*10 to (n-1)*10+9, its words fill that time without a pause, and the one-second
/// gap before the next line is the only pause.
func makeTranscript(_ texts: [String], sha: String = "aa") -> Transcript {
  var lines: [TranscriptLine] = []
  var words: [TranscriptWord] = []
  for (index, text) in texts.enumerated() {
    let start = Double(index) * 10
    lines.append(TranscriptLine(start: start, end: start + 9, text: text))
    let pieces = text.split(separator: " ").map(String.init)
    let step = 9.0 / Double(max(1, pieces.count))
    for (i, word) in pieces.enumerated() {
      words.append(
        TranscriptWord(text: word, start: start + Double(i) * step, end: start + Double(i + 1) * step))
    }
  }
  let identity = TranscriptIdentity(
    locale: "en-US", recogniser: "Fake", recogniserVersion: "1", osVersion: "26.0", sha256: sha)
  return Transcript(
    identity: identity, duration: Double(texts.count) * 10, lines: lines, words: words)
}

/// `count` lines of plain talk, with the lines in `ad` (counted from 1) replaced by ad copy.
func talk(_ count: Int, ad: ClosedRange<Int>? = nil) -> [String] {
  (1...count).map { ad?.contains($0) == true ? "ad copy \($0) from our sponsor" : "plain talk number \($0) here" }
}

func range(
  _ first: Int, _ last: Int, kind: AdKind = .ad, _ confidence: AdConfidence = .sure,
  advertiser: String = "Acme"
) -> AdRange {
  AdRange(
    startLine: first, endLine: last, advertiser: advertiser, kind: kind, confidence: confidence)
}

func temporaryFolder() throws -> URL {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
    "ads-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  return folder
}

/// A detector that answers from a closure.
struct FakeDetector: AdDetector {
  var name = "fake"
  var version = "1"
  var tokenBudget = 150
  var answer: @Sendable (TranscriptPiece) throws -> [AdRange]

  func findAds(in piece: TranscriptPiece) async throws -> [AdRange] { try answer(piece) }
}
