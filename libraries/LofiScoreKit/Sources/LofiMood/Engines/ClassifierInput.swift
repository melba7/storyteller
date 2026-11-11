import Foundation

/// The text a Create ML mood classifier sees, shared by the Fast engine and
/// `lofi-train` so the model is trained on exactly the slice of the window it
/// is later asked about.
///
/// Labels describe the end of a causal window (the sentence being narrated and
/// the lines just before it), so the classifier works on the newest words only.
public enum ClassifierInput {
    /// How many of the newest words the classifier reads.
    public static let defaultChunkWords = 160

    /// The earlier chunk is only read when it has at least this many words.
    public static let minimumEarlierWords = 40

    /// Words in `text`, split on whitespace like the chunks.
    public static func wordCount(_ text: String) -> Int {
        tokens(text).count
    }

    /// The newest `words` words of `text`, joined by single spaces.
    public static func recentChunk(of text: String, words: Int = defaultChunkWords) -> String {
        tokens(text).suffix(max(words, 1)).joined(separator: " ")
    }

    /// The `words` words that come just before the recent chunk, or "" when the text is shorter.
    public static func earlierChunk(of text: String, words: Int = defaultChunkWords) -> String {
        tokens(text).dropLast(max(words, 1)).suffix(max(words, 1)).joined(separator: " ")
    }

    private static func tokens(_ text: String) -> [Substring] {
        text.split(whereSeparator: { $0.isWhitespace })
    }
}
