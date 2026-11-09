import Foundation

/// Pulls the text of specific elements (by id) out of an XHTML content document.
///
/// Storyteller wraps every sentence in `<span id="<chapterId>-s<n>"
/// epub:type="storyteller:sentence-span">`. When a sentence is split across
/// elements, only the first piece keeps the id; later pieces keep the
/// `storyteller:sentence-span` type, and their text is added to the most recent
/// sentence. Ruby annotations, scripts, styles, note references and page-break
/// markers are left out because they are not narrated.
enum ChapterText {
    /// Returns id -> normalized text for every id in `wanted` found in the document.
    static func texts(_ data: Data, wanted: Set<String>) -> [String: String] {
        var buffers: [String: String] = [:]

        struct Frame {
            let name: String
            /// The id whose text this element contributes to, if any.
            let captureID: String?
            /// True for elements whose text is never narrated.
            let skip: Bool
        }

        var stack: [Frame] = []
        var skipDepth = 0
        var lastSentenceID: String? = nil

        func activeCaptures() -> [String] {
            var ids: [String] = []
            for frame in stack {
                if let id = frame.captureID, !ids.contains(id) { ids.append(id) }
            }
            return ids
        }

        func append(_ text: String) {
            guard skipDepth == 0 else { return }
            for id in activeCaptures() {
                buffers[id, default: ""] += text
            }
        }

        MarkupScanner(data: data).scan { event in
            switch event {
            case let .start(qualified, attributes, selfClosing):
                let name = localName(qualified)
                let type = attributes["epub:type"] ?? ""
                let isVoid = selfClosing || voidElements.contains(name)

                if isVoid {
                    if name == "br" || name == "hr" { append(" ") }
                    if let id = attributes["id"], wanted.contains(id) {
                        buffers[id, default: ""] += ""
                        lastSentenceID = id
                    }
                    return
                }

                if blockElements.contains(name) { append(" ") }

                var captureID: String? = nil
                if let id = attributes["id"], wanted.contains(id) {
                    captureID = id
                    lastSentenceID = id
                    if buffers[id] == nil { buffers[id] = "" }
                } else if attributes["id"] == nil, type.contains("storyteller:sentence-span"),
                    let previous = lastSentenceID
                {
                    // A continuation piece of a sentence split across elements.
                    captureID = previous
                }

                let skip = skippedElements.contains(name)
                    || type.contains("noteref")
                    || type.contains("pagebreak")
                if skip { skipDepth += 1 }
                stack.append(Frame(name: name, captureID: captureID, skip: skip))

            case let .end(qualified):
                let name = localName(qualified)
                // Tolerate mismatched tags: pop up to the nearest element with this name.
                guard let index = stack.lastIndex(where: { $0.name == name }) else { return }
                for frame in stack[index...] where frame.skip {
                    skipDepth -= 1
                }
                stack.removeSubrange(index...)
                if blockElements.contains(name) { append(" ") }

            case let .text(text):
                append(text)
            }
        }

        return buffers.mapValues(TextNormalizer.clean)
    }

    private static let voidElements: Set<String> = [
        "br", "hr", "img", "meta", "link", "input", "area", "base", "col", "embed", "source", "track", "wbr",
    ]

    private static let skippedElements: Set<String> = ["rt", "rp", "script", "style", "head", "title"]

    private static let blockElements: Set<String> = [
        "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote", "section", "article",
        "aside", "header", "footer", "tr", "td", "th", "dt", "dd", "figcaption", "pre", "table",
    ]
}

/// Whitespace and Unicode cleanup shared by everything that compares or counts text.
public enum TextNormalizer {
    /// Collapses every run of whitespace (including no-break and thin spaces) to one
    /// space, trims the ends, and applies canonical composition (NFC).
    public static func clean(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in text.precomposedStringWithCanonicalMapping.unicodeScalars {
            if scalar.properties.isWhitespace || scalar == "\u{200B}" || scalar == "\u{FEFF}" {
                pendingSpace = !out.isEmpty
                continue
            }
            if pendingSpace {
                out.append(" ")
                pendingSpace = false
            }
            out.append(scalar)
        }
        return String(out)
    }

    /// Number of whitespace-separated words.
    public static func wordCount(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                inWord = false
            } else if !inWord {
                inWord = true
                count += 1
            }
        }
        return count
    }

    /// The last `maxWords` words of `text`.
    public static func suffix(_ text: String, maxWords: Int) -> String {
        guard maxWords > 0 else { return "" }
        let words = text.split(whereSeparator: { $0.isWhitespace })
        guard words.count > maxWords else { return text }
        return words.suffix(maxWords).joined(separator: " ")
    }
}
