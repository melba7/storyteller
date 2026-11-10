import Foundation
import Testing
@testable import LofiMood

/// Expected pieces and ids come from Hugging Face's BertTokenizerFast
/// (transformers 5.22, lowercase, left truncation) on the same small vocabulary.
@Suite struct WordPieceTokenizerTests {
    static let vocabulary = [
        "[PAD]", "[UNK]", "[CLS]", "[SEP]", "[MASK]", "the", "cat", "cats", "sat", "on", "mat", ".", ",", "!", "?", "'", "\"",
        "-", "—", "“", "”", "un", "##aff", "##able", "run", "##ning", "cafe", "naive", "resume", "he", "said", "no", "tab",
        "and", "newline", "nbsp", "中", "国", "人", "οδοσ", "οδος", "bell", "ab", "a", "b", "istanbul", "i", "##stanbul",
        "##\u{307}", "s", "##s", "hello", "world", "x", "##y", "##z", "quiet", "evening", "by", "fire", "it", "was",
    ]

    func tokenizer() throws -> WordPieceTokenizer {
        try WordPieceTokenizer(vocabulary: Self.vocabulary)
    }

    @Test func piecesMatchThePythonTokenizer() throws {
        let t = try tokenizer()
        let cases: [(String, [String])] = [
            ("The cat sat on the mat.", ["the", "cat", "sat", "on", "the", "mat", "."]),
            ("Unaffable cats, running!", ["un", "##aff", "##able", "cats", ",", "run", "##ning", "!"]),
            ("Café naïve résumé", ["cafe", "naive", "resume"]),
            ("He said—“no.”", ["he", "said", "—", "“", "no", ".", "”"]),
            ("Tab\tand\nnewline\u{00A0}nbsp", ["tab", "and", "newline", "nbsp"]),
            ("中国人", ["中", "国", "人"]),
            ("ΟΔΟΣ", ["οδοσ"]),
            (String(repeating: "a", count: 101), ["[UNK]"]),
            ("xyzzy hello", ["x", "##y", "##z", "##z", "##y", "hello"]),
            ("\u{0007}bell a\u{200B}b", ["bell", "ab"]),
            ("İstanbul", ["istanbul"]),
        ]
        for (text, expected) in cases {
            #expect(t.pieces(text) == expected, "\(text)")
        }
    }

    @Test func encodeKeepsTheNewestPiecesAndPads() throws {
        let t = try tokenizer()
        let long = t.encode("It was a quiet evening by the fire, the cat sat on the mat and the cat sat on the mat.", length: 12)
        #expect(long.ids == [2, 5, 10, 33, 5, 6, 8, 9, 5, 10, 11, 3])
        #expect(long.mask == [Int32](repeating: 1, count: 12))
        let short = t.encode("hello world", length: 8)
        #expect(short.ids == [2, 51, 52, 3, 0, 0, 0, 0])
        #expect(short.mask == [1, 1, 1, 1, 0, 0, 0, 0])
    }

    @Test func settingsFileIsRecognisedWithoutDecodingIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lofi-wp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let config = folder.appendingPathComponent("LofiMood-lm-test.json")
        let json = #"{"format":1,"kind":"wordpiece-transformer","model":"LofiMood-lm-test.mlmodelc","moods":["calm"],"maxTokens":8,"lowercase":true,"chunkWords":160,"earlierWeight":0.2,"base":"x","variant":"soft","special":{"cls":"[CLS]","sep":"[SEP]","pad":"[PAD]","unk":"[UNK]"},"vocab":["[PAD]","[UNK]","[CLS]","[SEP]","hello"]}"#
        try Data(json.utf8).write(to: config)
        #expect(TransformerMoodConfig.isConfig(config))
        let loaded = try TransformerMoodConfig.load(from: config)
        #expect(try loaded.tokenizer().encode("Hello", length: 5).ids == [2, 4, 3, 0, 0])
        let embed = folder.appendingPathComponent("LofiMood-embed-word-9.json")
        try Data(#"{"classes":["calm"],"features":"word.en/1"}"#.utf8).write(to: embed)
        #expect(!TransformerMoodConfig.isConfig(embed))
    }

    @Test func missingSpecialTokenIsAnError() {
        #expect(throws: (any Error).self) { try WordPieceTokenizer(vocabulary: ["[PAD]", "[CLS]", "[SEP]", "hello"]) }
    }
}
