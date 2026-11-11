import Foundation

/// A small deterministic random number generator so property tests replay exactly.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A readaloud book model that renders to an unzipped EPUB 3 directory shaped
/// like Storyteller's output: `<span id="<chapterId>-s<n>"
/// epub:type="storyteller:sentence-span">`, one SMIL per chapter under
/// MediaOverlays/, optional word-level overlays and audio-only gaps.
struct FixtureBook {
    struct Sentence {
        var text: String
        /// Split the sentence across a paragraph break after this many words.
        /// The second piece keeps the sentence-span type but loses the id, as upstream does.
        var splitAfterWord: Int? = nil
        /// Start a new paragraph after this sentence.
        var paragraphBreakAfter = false
        /// An audio-only gap plays before this sentence.
        var holeBefore = false
        /// An audio-only gap plays after this sentence.
        var holeAfter = false
        /// Add a footnote reference after the sentence (its text is not narrated).
        var noteRef = false
    }

    struct Chapter {
        var id: String
        var sentences: [Sentence]
        var linear = true
        var hasOverlay = true
    }

    var chapters: [Chapter]
    var wordLevel = false

    func textPath(_ chapter: Chapter) -> String { "OEBPS/Text/\(chapter.id).xhtml" }
    func smilPath(_ chapter: Chapter) -> String { "OEBPS/MediaOverlays/\(chapter.id).smil" }
    static let audioPath = "OEBPS/Audio/book.mp3"

    /// Expected normalized text of a sentence, as the guard should read it.
    static func expectedText(_ sentence: Sentence) -> String {
        sentence.text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    // MARK: - Rendering

    func write(to root: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: root)
        for dir in ["META-INF", "OEBPS/Text", "OEBPS/MediaOverlays", "OEBPS/Audio"] {
            try fm.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        try Data("application/epub+zip".utf8).write(to: root.appendingPathComponent("mimetype"))
        try Data(containerXML.utf8).write(to: root.appendingPathComponent("META-INF/container.xml"))
        try Data(opf().utf8).write(to: root.appendingPathComponent("OEBPS/content.opf"))
        try Data(nav().utf8).write(to: root.appendingPathComponent("OEBPS/nav.xhtml"))
        for chapter in chapters {
            try Data(xhtml(chapter).utf8).write(to: root.appendingPathComponent(textPath(chapter)))
            if chapter.hasOverlay {
                try Data(smil(chapter).utf8).write(to: root.appendingPathComponent(smilPath(chapter)))
            }
        }
    }

    let containerXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """

    func opf() -> String {
        var manifest = """
                <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                <item id="audio" href="Audio/book.mp3" media-type="audio/mpeg"/>

            """
        var spine = ""
        for chapter in chapters {
            let overlay = chapter.hasOverlay ? " media-overlay=\"\(chapter.id)_overlay\"" : ""
            manifest += "    <item id=\"\(chapter.id)\" href=\"Text/\(chapter.id).xhtml\" media-type=\"application/xhtml+xml\"\(overlay)/>\n"
            if chapter.hasOverlay {
                manifest += "    <item id=\"\(chapter.id)_overlay\" href=\"MediaOverlays/\(chapter.id).smil\" media-type=\"application/smil+xml\"/>\n"
            }
            spine += "    <itemref idref=\"\(chapter.id)\"\(chapter.linear ? "" : " linear=\"no\"")/>\n"
        }
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id" prefix="storyteller: https://storyteller-platform.dev/docs/vocabulary">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:identifier id="id">urn:uuid:fixture</dc:identifier>
                <dc:title>Fixture &amp; Friends</dc:title>
                <dc:language>en</dc:language>
                <meta property="media:duration">01:00:00</meta>
              </metadata>
              <manifest>
            \(manifest)  </manifest>
              <spine>
            \(spine)  </spine>
            </package>
            """
    }

    func nav() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head>
        <body><nav epub:type="toc"><ol>\(chapters.map { "<li><a href=\"Text/\($0.id).xhtml\">\($0.id)</a></li>" }.joined())</ol></nav></body></html>
        """
    }

    /// Escapes text for XHTML, writing some characters as entities the way real books do.
    static func escape(_ text: String) -> String {
        var out = ""
        for ch in text {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\u{2014}": out += "&mdash;"
            case "\u{00A0}": out += "&nbsp;"
            case "\u{2019}": out += "&#8217;"
            default: out.append(ch)
            }
        }
        return out
    }

    func spanContent(_ chapter: Chapter, _ index: Int, _ text: String, wordOffset: Int) -> String {
        guard wordLevel else { return Self.escape(text) }
        let words = text.split(separator: " ")
        return words.enumerated().map { j, word in
            "<span id=\"\(chapter.id)-s\(index)-w\(j + wordOffset)\" epub:type=\"storyteller:word-span\">\(Self.escape(String(word)))</span>"
        }.joined(separator: " ")
    }

    func xhtml(_ chapter: Chapter) -> String {
        var body = "<h1>\(Self.escape(chapter.id))</h1>\n<p>"
        for (i, sentence) in chapter.sentences.enumerated() {
            let id = "\(chapter.id)-s\(i)"
            let words = sentence.text.split(separator: " ").map(String.init)
            if let split = sentence.splitAfterWord, split > 0, split < words.count {
                let first = words[..<split].joined(separator: " ")
                let second = words[split...].joined(separator: " ")
                body += "<span id=\"\(id)\" epub:type=\"storyteller:sentence-span\">\(spanContent(chapter, i, first, wordOffset: 0)) </span></p>\n<p>"
                body += "<span epub:type=\"storyteller:sentence-span\">\(spanContent(chapter, i, second, wordOffset: split))</span> "
            } else {
                // Some sentences carry inline formatting, as real books do.
                let content = spanContent(chapter, i, sentence.text, wordOffset: 0)
                let formatted = (i % 7 == 3 && !wordLevel) ? "<em>\(content)</em>" : content
                body += "<span id=\"\(id)\" epub:type=\"storyteller:sentence-span\">\(formatted)</span> "
            }
            if sentence.noteRef {
                body += "<a href=\"#fn\(i)\" epub:type=\"noteref\">\(i + 1)</a> "
            }
            if sentence.paragraphBreakAfter { body += "</p>\n<p>" }
        }
        body += "</p>"
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" epub:prefix="storyteller: https://storyteller-platform.dev/docs/vocabulary">
            <head><meta charset="utf-8"/><title>\(Self.escape(chapter.id))</title><style>p { margin: 0 }</style></head>
            <body>
            \(body)
            </body>
            </html>
            """
    }

    func smil(_ chapter: Chapter) -> String {
        var clock = 0.0
        func audio() -> String {
            defer { clock += 2.5 }
            return "<audio src=\"../Audio/book.mp3\" clipBegin=\"\(String(format: "%.3f", clock))s\" clipEnd=\"\(String(format: "%.3f", clock + 2.5))s\"/>"
        }
        let href = "../Text/\(chapter.id).xhtml"
        var pars = ""
        for (i, sentence) in chapter.sentences.enumerated() {
            let id = "\(chapter.id)-s\(i)"
            if sentence.holeBefore {
                pars += "<par id=\"\(id)-before0\" epub:type=\"storyteller:audio-only\"><text src=\"\(href)#\(id)\"/>\(audio())</par>\n"
            }
            if wordLevel {
                let count = sentence.text.split(separator: " ").count
                pars += "<seq id=\"\(id)\" epub:type=\"text-range-small storyteller:aligned\" epub:textref=\"\(href)#\(id)\">\n"
                for j in 0..<count {
                    pars += "  <par id=\"\(id)-w\(j)\"><text src=\"\(href)#\(id)-w\(j)\"/>\(audio())</par>\n"
                }
                pars += "</seq>\n"
            } else {
                pars += "<par id=\"\(id)\" epub:type=\"storyteller:aligned\"><text src=\"\(href)#\(id)\"/>\(audio())</par>\n"
            }
            if sentence.holeAfter {
                pars += "<par id=\"\(id)-after0\" epub:type=\"storyteller:audio-only\"><text src=\"\(href)#\(id)\"/>\(audio())</par>\n"
            }
        }
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <smil xmlns="http://www.w3.org/ns/SMIL" xmlns:epub="http://www.idpf.org/2007/ops" version="3.0">
            <body>
            <seq id="\(chapter.id)_overlay" epub:textref="\(href)" epub:type="chapter">
            \(pars)</seq>
            </body>
            </smil>
            """
    }

    /// Clip start (seconds) of the audio-only gap before sentence `index`, if it has one.
    func holeBeforeClipBegin(chapter: Chapter, index: Int) -> Double? {
        guard chapter.sentences[index].holeBefore else { return nil }
        var clock = 0.0
        for (i, sentence) in chapter.sentences.enumerated() {
            if sentence.holeBefore {
                if i == index { return clock }
                clock += 2.5
            }
            clock += 2.5 * Double(wordLevel ? sentence.text.split(separator: " ").count : 1)
            if sentence.holeAfter { clock += 2.5 }
        }
        return nil
    }

    // MARK: - Random books

    static let vocabulary: [String] = [
        "the", "rain", "lamp", "whisper", "door", "garden", "storm", "letter", "night", "kettle", "river",
        "laughed", "ran", "silent", "strange", "warm", "cold", "she", "he", "they", "said", "softly",
        "never", "again", "under", "above", "shadow", "fire", "bright", "slowly", "suddenly", "home",
        "ship", "sea", "forest", "candle", "voice", "heart", "stone", "window", "morning", "grave",
        "caf\u{00E9}", "na\u{00EF}ve", "it\u{2019}s", "well\u{2014}perhaps", "A&B", "x<y", "Mr.\u{00A0}Fox",
    ]

    static func randomSentence(_ rng: inout SplitMix64) -> Sentence {
        let length = Int.random(in: 1...28, using: &rng)
        var words: [String] = []
        for _ in 0..<length {
            words.append(vocabulary.randomElement(using: &rng)!)
        }
        words[0] = words[0].prefix(1).uppercased() + words[0].dropFirst()
        var sentence = Sentence(text: words.joined(separator: " ") + [".", "!", "?", "\u{2026}"].randomElement(using: &rng)!)
        if length > 3 && Int.random(in: 0..<8, using: &rng) == 0 {
            sentence.splitAfterWord = Int.random(in: 1..<length, using: &rng)
        }
        sentence.paragraphBreakAfter = Int.random(in: 0..<4, using: &rng) == 0
        sentence.holeBefore = Int.random(in: 0..<12, using: &rng) == 0
        sentence.holeAfter = Int.random(in: 0..<12, using: &rng) == 0
        sentence.noteRef = Int.random(in: 0..<15, using: &rng) == 0
        return sentence
    }

    static func random(_ rng: inout SplitMix64, chapterCount: ClosedRange<Int> = 2...6) -> FixtureBook {
        var chapters: [Chapter] = []
        let count = Int.random(in: chapterCount, using: &rng)
        for c in 0..<count {
            let sentences = (0..<Int.random(in: 1...40, using: &rng)).map { _ in randomSentence(&rng) }
            chapters.append(Chapter(id: "chapter_\(c)", sentences: sentences))
        }
        // Sometimes add front matter without narration, or a non-linear notes chapter.
        if Bool.random(using: &rng) {
            chapters.insert(Chapter(id: "cover", sentences: [Sentence(text: "Cover")], hasOverlay: false), at: 0)
        }
        if Bool.random(using: &rng) {
            let notes = Chapter(id: "notes", sentences: [randomSentence(&rng)], linear: false)
            chapters.insert(notes, at: Int.random(in: 0...chapters.count, using: &rng))
        }
        return FixtureBook(chapters: chapters, wordLevel: Int.random(in: 0..<4, using: &rng) == 0)
    }

    /// The chapters that are narrated (linear, with an overlay), in order.
    var narratedChapters: [Chapter] { chapters.filter { $0.linear && $0.hasOverlay } }
}
