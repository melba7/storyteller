import Foundation
import LofiScoreCore

/// The one-line answer format used by language-model engines:
///
///     bucket=tense; valence=-0.6; arousal=0.8; confidence=0.7
///
/// A plain `String` answer is used on purpose: Apple's permissive guardrails
/// only stop guardrail errors for `String` responses, and dark passages are
/// where mood matters most.
public enum MoodLine {
    /// Formats a reading as a mood line. Used for prompts' examples and logs.
    public static func format(_ reading: MoodReading) -> String {
        "bucket=\(reading.bucket.rawValue); valence=\(fmt(reading.valence)); arousal=\(fmt(reading.arousal)); confidence=\(fmt(reading.confidence))"
    }

    /// Parses a model's answer. Tolerates extra words, different separators,
    /// "mood" instead of "bucket", ":" instead of "=", capitals, and missing
    /// numbers (which fall back to the bucket's anchor and 0.5 confidence).
    ///
    /// - Throws: `MoodEngineError.unparseable` when no bucket can be found,
    ///   which is what a refusal looks like.
    public static func parse(_ answer: String, engineID: String) throws -> MoodReading {
        let text = answer.lowercased()
        let bucket = value(after: ["bucket", "mood"], in: text, numeric: false).flatMap(MoodBucket.init(lenient:))
            ?? soleBucketMention(in: text)
        guard let bucket else { throw MoodEngineError.unparseable(answer) }

        let anchor = bucket.anchor
        let valence = value(after: ["valence"], in: text, numeric: true).flatMap(Double.init) ?? anchor.valence
        let arousal = value(after: ["arousal", "energy"], in: text, numeric: true).flatMap(Double.init) ?? anchor.arousal
        let confidence = value(after: ["confidence"], in: text, numeric: true).flatMap(Double.init) ?? 0.5
        return MoodReading(
            bucket: bucket,
            valence: valence,
            arousal: arousal,
            confidence: confidence,
            engineID: engineID
        )
    }

    // MARK: - Internals

    private static func fmt(_ x: Double) -> String {
        String(format: "%.2f", x)
    }

    /// Finds `key` followed by "=" or ":" and returns the value token after it.
    private static func value(after keys: [String], in text: String, numeric: Bool) -> String? {
        for key in keys {
            var searchStart = text.startIndex
            while let range = text.range(of: key, range: searchStart..<text.endIndex) {
                searchStart = range.upperBound
                // The key must start a word ("valence", not "ambivalence").
                if range.lowerBound > text.startIndex {
                    let before = text[text.index(before: range.lowerBound)]
                    if before.isLetter { continue }
                }
                var i = range.upperBound
                while i < text.endIndex, text[i] == " " || text[i] == "*" || text[i] == "\"" { i = text.index(after: i) }
                guard i < text.endIndex, text[i] == "=" || text[i] == ":" else { continue }
                i = text.index(after: i)
                while i < text.endIndex, text[i] == " " || text[i] == "*" || text[i] == "\"" || text[i] == "'" {
                    i = text.index(after: i)
                }
                var token = ""
                while i < text.endIndex {
                    let c = text[i]
                    let ok = numeric ? (c.isNumber || c == "." || c == "-" || c == "+" || c == "\u{2212}") : c.isLetter
                    guard ok else { break }
                    token.append(c == "\u{2212}" ? "-" : c)
                    i = text.index(after: i)
                }
                if numeric { while token.hasSuffix(".") { token.removeLast() } }
                if numeric, token.hasPrefix("+") { token.removeFirst() }
                if numeric, token.hasPrefix("-.") { token = "-0" + token.dropFirst() }
                if numeric, token.hasPrefix(".") { token = "0" + token }
                if !token.isEmpty { return token }
            }
        }
        return nil
    }

    /// For short answers like "Tense." accept a single bucket name.
    private static func soleBucketMention(in text: String) -> MoodBucket? {
        guard text.count <= 60 else { return nil }
        let words = text.split(whereSeparator: { !$0.isLetter }).map(String.init)
        let found = Set(words.compactMap { MoodBucket(rawValue: $0) ?? ($0 == "sombre" ? .somber : nil) })
        return found.count == 1 ? found.first : nil
    }
}
