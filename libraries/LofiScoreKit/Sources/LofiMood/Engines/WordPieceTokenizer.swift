import Foundation

/// BERT's uncased WordPiece tokenizer, as Hugging Face's `BertTokenizerFast`
/// runs it (normalizer, pre-tokenizer, WordPiece), so the app feeds a
/// fine-tuned transformer exactly the ids it was trained on.
///
/// Steps, on Unicode scalars like the Rust original: drop control characters
/// and turn every whitespace character into a space; put spaces around CJK
/// ideographs; when lowercasing, strip accents (NFD, then drop non-spacing
/// marks) and lowercase; split on whitespace and around each punctuation
/// character; then match each word greedily, longest piece first, with "##"
/// on pieces after the first. A word with no match, or over 100 characters,
/// becomes the unknown token. Pure Swift and Foundation, so it is tested on
/// Linux against the Python tokenizer's output.
public struct WordPieceTokenizer: Sendable {
    public let lowercase: Bool
    public let maxCharactersPerWord: Int
    public let unknown: String
    public let classify: String
    public let separator: String
    public let padding: String
    private let ids: [String: Int32]

    public init(vocabulary: [String], lowercase: Bool = true, unknown: String = "[UNK]", classify: String = "[CLS]",
                separator: String = "[SEP]", padding: String = "[PAD]", maxCharactersPerWord: Int = 100) throws {
        var ids: [String: Int32] = [:]
        for (i, piece) in vocabulary.enumerated() where ids[piece] == nil { ids[piece] = Int32(i) }
        for special in [unknown, classify, separator, padding] where ids[special] == nil {
            throw MoodEngineError.unavailable("the vocabulary has no \(special)")
        }
        self.ids = ids
        self.lowercase = lowercase
        self.unknown = unknown
        self.classify = classify
        self.separator = separator
        self.padding = padding
        self.maxCharactersPerWord = maxCharactersPerWord
    }

    public var paddingID: Int32 { ids[padding]! }

    /// The word pieces of `text`, without the special tokens.
    public func pieces(_ text: String) -> [String] {
        words(normalize(text)).flatMap(wordPieces)
    }

    public func id(of piece: String) -> Int32 { ids[piece] ?? ids[unknown]! }

    /// `[CLS]` + the LAST `length - 2` pieces of `text` + `[SEP]`, padded to
    /// `length`, with the attention mask (1 for real tokens). Keeping the end
    /// matches training, where the tokenizer truncated from the left: the
    /// newest words are the ones the label describes.
    public func encode(_ text: String, length: Int) -> (ids: [Int32], mask: [Int32]) {
        let body = pieces(text).suffix(max(0, length - 2)).map(id(of:))
        var tokens = [ids[classify]!] + body + [ids[separator]!]
        var mask = [Int32](repeating: 1, count: tokens.count)
        if tokens.count < length {
            tokens += [Int32](repeating: paddingID, count: length - tokens.count)
            mask += [Int32](repeating: 0, count: length - mask.count)
        }
        return (tokens, mask)
    }

    // MARK: - Normalizer

    func normalize(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for s in text.unicodeScalars {
            if s.value == 0 || s.value == 0xFFFD || isControl(s) { continue }
            if isWhitespace(s) {
                out.append(" ")
            } else if isChineseCharacter(s) {
                out.append(" "); out.append(s); out.append(" ")
            } else {
                out.append(s)
            }
        }
        var result = String(out)
        if lowercase {
            var stripped = String.UnicodeScalarView()
            for s in result.decomposedStringWithCanonicalMapping.unicodeScalars where s.properties.generalCategory != .nonspacingMark {
                stripped.append(s)
            }
            // Character by character, like Rust's char::to_lowercase (so no
            // context rules such as a word-final sigma).
            var lowered = String.UnicodeScalarView()
            for s in stripped {
                if s.value < 0x80 {
                    lowered.append(s.value >= 65 && s.value <= 90 ? Unicode.Scalar(s.value + 32)! : s)
                } else if s.properties.changesWhenLowercased {
                    lowered.append(contentsOf: s.properties.lowercaseMapping.unicodeScalars)
                } else {
                    lowered.append(s)
                }
            }
            result = String(lowered)
        }
        return result
    }

    /// Unicode's White_Space property, as Rust's char::is_whitespace.
    func isWhitespace(_ s: Unicode.Scalar) -> Bool {
        s == " " || s == "\t" || s == "\n" || s == "\r" || s.properties.isWhitespace
    }

    func isControl(_ s: Unicode.Scalar) -> Bool {
        if s == "\t" || s == "\n" || s == "\r" { return false }
        switch s.properties.generalCategory {
        case .control, .format, .surrogate, .privateUse, .unassigned: return true
        default: return false
        }
    }

    func isChineseCharacter(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2A6DF, 0x2A700...0x2B73F,
             0x2B740...0x2B81F, 0x2B820...0x2CEAF, 0xF900...0xFAFF, 0x2F800...0x2FA1F: return true
        default: return false
        }
    }

    func isPunctuation(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        if (33...47).contains(v) || (58...64).contains(v) || (91...96).contains(v) || (123...126).contains(v) { return true }
        switch s.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation: return true
        default: return false
        }
    }

    // MARK: - Pre-tokenizer and WordPiece

    func words(_ text: String) -> [[Unicode.Scalar]] {
        var words: [[Unicode.Scalar]] = []
        var current: [Unicode.Scalar] = []
        func flush() { if !current.isEmpty { words.append(current); current = [] } }
        for s in text.unicodeScalars {
            if isWhitespace(s) {
                flush()
            } else if isPunctuation(s) {
                flush()
                words.append([s])
            } else {
                current.append(s)
            }
        }
        flush()
        return words
    }

    func wordPieces(_ word: [Unicode.Scalar]) -> [String] {
        if word.count > maxCharactersPerWord { return [unknown] }
        var pieces: [String] = []
        var start = 0
        while start < word.count {
            var end = word.count
            var found: String?
            while start < end {
                var piece = String(String.UnicodeScalarView(word[start..<end]))
                if start > 0 { piece = "##" + piece }
                if ids[piece] != nil { found = piece; break }
                end -= 1
            }
            guard let found else { return [unknown] }
            pieces.append(found)
            start = end
        }
        return pieces
    }
}

/// The settings file next to a fine-tuned transformer (`LofiMood-lm-*.json`,
/// written by `Tools/eval/finetune_mood.py coreml`): which compiled Core ML
/// model to load, its word pieces and how it reads a window.
public struct TransformerMoodConfig: Codable, Sendable {
    public static let kind = "wordpiece-transformer"

    public struct Special: Codable, Sendable {
        public var cls: String
        public var sep: String
        public var pad: String
        public var unk: String
    }

    public var format: Int
    public var kind: String
    /// The compiled model (`.mlmodelc`), relative to this file's folder.
    public var model: String
    public var moods: [String]
    public var maxTokens: Int
    public var lowercase: Bool
    public var chunkWords: Int
    public var earlierWeight: Double
    public var base: String?
    public var variant: String?
    public var special: Special
    public var vocab: [String]

    public static func load(from url: URL) throws -> TransformerMoodConfig {
        try JSONDecoder().decode(TransformerMoodConfig.self, from: Data(contentsOf: url))
    }

    /// Whether the JSON file at `url` is one of these (and not, say, a
    /// `lofi-train embed` model), without decoding the vocabulary.
    public static func isConfig(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "json",
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = String(decoding: handle.readData(ofLength: 512), as: UTF8.self)
        return head.contains("\"kind\":\"\(kind)\"") || head.contains("\"kind\": \"\(kind)\"")
    }

    public func tokenizer() throws -> WordPieceTokenizer {
        try WordPieceTokenizer(vocabulary: vocab, lowercase: lowercase, unknown: special.unk, classify: special.cls,
                               separator: special.sep, padding: special.pad)
    }
}
