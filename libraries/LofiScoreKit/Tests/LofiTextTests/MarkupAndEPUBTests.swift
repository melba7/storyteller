import Foundation
import Testing

@testable import LofiText

@Suite("Markup scanner")
struct MarkupScannerTests {
    @Test func decodesEntities() {
        #expect(MarkupScanner.decodeEntities("a &amp; b &lt;c&gt; &quot;d&quot; &apos;e&apos;") == "a & b <c> \"d\" 'e'")
        #expect(MarkupScanner.decodeEntities("x&nbsp;y&mdash;z &#8217; &#x2014;") == "x\u{00A0}y\u{2014}z \u{2019} \u{2014}")
        #expect(MarkupScanner.decodeEntities("AT&T & co &bogus; &#xZZ;") == "AT&T & co &bogus; &#xZZ;")
    }

    @Test func tokenizesTagsAttributesAndText() {
        let events = MarkupScanner(string: """
            <?xml version="1.0"?><!DOCTYPE html [ <!ENTITY x "y"> ]><!-- c --><p class='a > b' data-x=1 hidden>Hi <br/>there<![CDATA[ <raw> ]]></p>
            """).events()
        #expect(events == [
            .start(name: "p", attributes: ["class": "a > b", "data-x": "1", "hidden": ""], selfClosing: false),
            .text("Hi "),
            .start(name: "br", attributes: [:], selfClosing: true),
            .text("there"),
            .text(" <raw> "),
            .end(name: "p"),
        ])
    }

    @Test func survivesTruncatedInput() {
        let full = "<p><span id=\"a\">One.</span><span id=\"b\" epub:type=\"x\">Two"
        for cut in 0...full.utf8.count {
            let prefix = String(decoding: Array(full.utf8.prefix(cut)), as: UTF8.self)
            _ = MarkupScanner(string: prefix).events()  // must not crash or hang
        }
        let events = MarkupScanner(string: "<p><span id=\"a\">One.</span><span id=\"b").events()
        #expect(events == [
            .start(name: "p", attributes: [:], selfClosing: false),
            .start(name: "span", attributes: ["id": "a"], selfClosing: false),
            .text("One."),
            .end(name: "span"),
        ])
    }

    @Test func handlesUTF16AndBOM() {
        let bom = Data([0xEF, 0xBB, 0xBF]) + Data("<a>é</a>".utf8)
        #expect(MarkupScanner(data: bom).events().contains(.text("é")))
        let utf16 = "<a>ü</a>".data(using: .utf16)!
        #expect(MarkupScanner(data: utf16).events().contains(.text("ü")))
    }
}

@Suite("EPUB parsing")
struct EPUBParsingTests {
    @Test func resolvesPaths() {
        #expect(EPUBPath.resolve("../Text/ch1.xhtml#s1", relativeTo: "OEBPS/MediaOverlays/ch1.smil") == ("OEBPS/Text/ch1.xhtml", "s1"))
        #expect(EPUBPath.resolve("Text/a%20b.xhtml", relativeTo: "OEBPS/content.opf") == ("OEBPS/Text/a b.xhtml", nil))
        #expect(EPUBPath.resolve("#x", relativeTo: "OEBPS/Text/ch1.xhtml") == ("OEBPS/Text/ch1.xhtml", "x"))
        #expect(EPUBPath.resolve("/OEBPS/./Text//c.xhtml", relativeTo: "OEBPS/content.opf").path == "OEBPS/Text/c.xhtml")
        #expect(EPUBPath.normalizeReported("/OEBPS/Text/ch%201.xhtml#frag") == "OEBPS/Text/ch 1.xhtml")
        #expect(EPUBPath.normalizeReported("https://localhost:1234/OEBPS/a.xhtml") == "OEBPS/a.xhtml")
    }

    @Test func parsesSMILClockValues() {
        #expect(SMILClock.seconds("12.5s") == 12.5)
        #expect(SMILClock.seconds("500ms") == 0.5)
        #expect(SMILClock.seconds("1.5min") == 90)
        #expect(SMILClock.seconds("2h") == 7200)
        #expect(SMILClock.seconds("01:02.5") == 62.5)
        #expect(SMILClock.seconds("00:01:02.500") == 62.5)
        #expect(SMILClock.seconds("7") == 7)
        #expect(SMILClock.seconds("soon") == nil)
    }

    @Test func readsWordLevelOverlaysAndAudioOnlyGaps() {
        let smil = """
            <smil xmlns="http://www.w3.org/ns/SMIL" xmlns:epub="http://www.idpf.org/2007/ops"><body>
            <seq epub:textref="../Text/c.xhtml" epub:type="chapter">
              <par id="c-s0-before0" epub:type="storyteller:audio-only"><text src="../Text/c.xhtml#c-s0"/><audio src="../Audio/a.mp3" clipBegin="0s" clipEnd="2s"/></par>
              <seq id="c-s0" epub:type="text-range-small" epub:textref="../Text/c.xhtml#c-s0">
                <par id="c-s0-w0"><text src="../Text/c.xhtml#c-s0-w0"/><audio src="../Audio/a.mp3" clipBegin="2s" clipEnd="2.4s"/></par>
                <par id="c-s0-w1"><text src="../Text/c.xhtml#c-s0-w1"/><audio src="../Audio/a.mp3" clipBegin="2.4s" clipEnd="3s"/></par>
              </seq>
              <par id="c-s1"><text src="../Text/c.xhtml#c-s1"/><audio src="../Audio/a.mp3" clipBegin="3s" clipEnd="5s"/></par>
              <par id="c-s1-a1"><text src="../Text/c.xhtml#c-s1"/><audio src="../Audio/b.mp3" clipBegin="0s" clipEnd="1s"/></par>
            </seq></body></smil>
            """
        let entries = SMILDocument.entries(Data(smil.utf8), smilPath: "OEBPS/MediaOverlays/c.smil")
        #expect(entries.map(\.fragmentID) == ["c-s0", "c-s0-w0", "c-s0-w1", "c-s1", "c-s1"])
        #expect(entries.map(\.sentenceFragmentID) == ["c-s0", "c-s0", "c-s0", "c-s1", "c-s1"])
        #expect(entries.map(\.isAudioOnly) == [true, false, false, false, false])
        #expect(entries[1].clipBegin == 2)
        #expect(entries[0].audioPath == "OEBPS/Audio/a.mp3")

        let grouped = EPUBReadaloudSource.group(entries)
        #expect(grouped.order.map(\.fragment) == ["c-s0", "c-s1"])
        #expect(grouped.indexByFragment["OEBPS/Text/c.xhtml#c-s0-w1"] == 0)
        #expect(grouped.indexByFragment["OEBPS/Text/c.xhtml#c-s1"] == 1)
        // The gap before the first sentence belongs to whatever came before the chapter.
        #expect(grouped.beforeHoles[ChapterSentences.clipKey(audioPath: "OEBPS/Audio/a.mp3", clipBegin: 0)] == -1)
    }

    @Test func audioOnlyChapterHeadingStillCountsAsNarrated() {
        let smil = """
            <smil><body><seq>
              <par id="c-a0" epub:type="storyteller:audio-only"><text src="c.xhtml#heading"/><audio src="a.mp3" clipBegin="0s" clipEnd="9s"/></par>
            </seq></body></smil>
            """
        let grouped = EPUBReadaloudSource.group(SMILDocument.entries(Data(smil.utf8), smilPath: "c.smil"))
        #expect(grouped.order.map(\.fragment) == ["heading"])
    }

    @Test func extractsSentenceTextLikeStorytellerMarksItUp() {
        // Mirrors upstream's markup snapshots: formatting marks inside spans, a
        // sentence split across paragraphs (the second piece loses its id),
        // footnote references, ruby, page breaks and entities.
        let xhtml = """
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>T</title></head><body>
            <p>
                <span id="ch-s0" epub:type="storyteller:sentence-span">Call me <strong>Ishmael. </strong></span><span id="ch-s1" epub:type="storyteller:sentence-span"><strong>Some years ago</strong>&mdash;never mind how long
                precisely&#8212;having little or no money,
            </span></p>
            <p><span epub:type="storyteller:sentence-span">I thought I would sail.</span><a href="#n1" epub:type="noteref">1</a></p>
            <p><span epub:type="pagebreak" id="page_9" title="9">9</span><span id="ch-s2" epub:type="storyteller:sentence-span">Tokyo is <ruby>東京<rp>(</rp><rt>とうきょう</rt><rp>)</rp></ruby>,&nbsp;friend.</span></p>
            <p><span id="unrelated">Not narrated.</span></p>
            </body></html>
            """
        let texts = ChapterText.texts(Data(xhtml.utf8), wanted: ["ch-s0", "ch-s1", "ch-s2", "missing"])
        #expect(texts["ch-s0"] == "Call me Ishmael.")
        #expect(texts["ch-s1"] == "Some years ago\u{2014}never mind how long precisely\u{2014}having little or no money, I thought I would sail.")
        #expect(texts["ch-s2"] == "Tokyo is 東京, friend.")
        #expect(texts["missing"] == nil)
        #expect(texts["unrelated"] == nil)
    }

    @Test func normalizesWhitespace() {
        #expect(TextNormalizer.clean("  a\u{00A0}\n\tb\u{200B}  c ") == "a b c")
        #expect(TextNormalizer.clean("e\u{0301}") == "\u{00E9}")
        #expect(TextNormalizer.wordCount(" one  two\nthree ") == 3)
        #expect(TextNormalizer.suffix("a b c d", maxWords: 2) == "c d")
    }
}

@Suite("Upstream fixture")
struct UpstreamFixtureTests {
    /// `reader.epub` from upstream's StorytellerKit tests (MIT, (c) Shane Friedman),
    /// unzipped. Ids are "sentence-<n>" rather than "<chapterId>-s<n>".
    static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/storyteller-reader")

    @Test func readsTheUpstreamReaderFixture() throws {
        let guardian = try SpoilerGuard(epubDirectory: Self.fixture, policy: .init(maxWords: 400))
        let position = try #require(try guardian.position(textResource: "OEBPS/chapter.xhtml", fragmentId: "sentence-79"))
        #expect(position.globalIndex == 79)
        let window = try guardian.window(at: position)
        #expect(window.lines.last?.text.hasPrefix("Sentence 79. The quiet reader keeps its place") == true)
        #expect(window.wordCount <= 400)
        // Readium may report the path relative to the package document.
        let relative = try guardian.position(textResource: "chapter.xhtml", fragmentId: "#sentence-3")
        #expect(relative?.sentenceIndex == 3)
    }
}
