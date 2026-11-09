import Foundation

/// One `<par>` of a media overlay: a piece of text and its audio clip.
struct OverlayEntry: Equatable {
    /// Container-relative path of the content document.
    let textPath: String
    /// The id the `<text src>` points at: a sentence ("<chapterId>-s<n>")
    /// or, in word-level books, a word ("<chapterId>-s<n>-w<m>").
    let fragmentID: String
    /// The sentence this par belongs to. Equal to `fragmentID` unless the par
    /// sits inside a word-level `<seq epub:textref="...#sentence">`.
    let sentenceFragmentID: String
    /// Storyteller marks untranscribed audio between sentences ("holes") as
    /// `storyteller:audio-only`. Such a par points at a neighbouring sentence.
    let isAudioOnly: Bool
    /// Container-relative path of the audio file, if any.
    let audioPath: String?
    /// clipBegin in seconds, if present and parseable.
    let clipBegin: Double?
}

/// Reads the ordered `<par>` list of a SMIL file.
///
/// Order is document order, which is narration order. Nested `<seq>` elements
/// (sections, word-level sentence groups, footnotes) are flattened in place.
enum SMILDocument {
    static func entries(_ data: Data, smilPath: String) -> [OverlayEntry] {
        var entries: [OverlayEntry] = []

        // Stack of open <seq> elements: the sentence fragment each one stands for, if any.
        var seqStack: [String?] = []
        var inPar = false
        var parIsAudioOnly = false
        var parText: (path: String, fragment: String)? = nil
        var parAudio: (path: String, begin: Double?)? = nil

        func flushPar() {
            if let text = parText {
                let sentence = seqStack.compactMap { $0 }.last ?? text.fragment
                entries.append(OverlayEntry(
                    textPath: text.path,
                    fragmentID: text.fragment,
                    sentenceFragmentID: sentence,
                    isAudioOnly: parIsAudioOnly,
                    audioPath: parAudio?.path,
                    clipBegin: parAudio?.begin
                ))
            }
            inPar = false
            parText = nil
            parAudio = nil
            parIsAudioOnly = false
        }

        MarkupScanner(data: data).scan { event in
            switch event {
            case let .start(name, attributes, selfClosing):
                switch localName(name) {
                case "seq":
                    guard !selfClosing else { return }
                    var sentence: String? = nil
                    let type = attributes["epub:type"] ?? ""
                    if type.contains("text-range-small"), let ref = attributes["epub:textref"] {
                        let fragment = EPUBPath.resolve(ref, relativeTo: smilPath).fragment
                        if let fragment, !fragment.isEmpty, !fragment.hasPrefix(":~:") {
                            sentence = fragment
                        }
                    }
                    seqStack.append(sentence)
                case "par":
                    if inPar { flushPar() }
                    guard !selfClosing else { return }
                    inPar = true
                    parIsAudioOnly = (attributes["epub:type"] ?? "").contains("audio-only")
                case "text" where inPar && parText == nil:
                    guard let src = attributes["src"] else { return }
                    let (path, fragment) = EPUBPath.resolve(src, relativeTo: smilPath)
                    // Text-fragment directives ("#:~:text=") are experimental upstream and
                    // name no element, so they are skipped.
                    guard let fragment, !fragment.isEmpty, !fragment.hasPrefix(":~:") else { return }
                    parText = (path, fragment)
                case "audio" where inPar && parAudio == nil:
                    guard let src = attributes["src"] else { return }
                    let path = EPUBPath.resolve(src, relativeTo: smilPath).path
                    let begin = (attributes["clipbegin"]).flatMap(SMILClock.seconds)
                    parAudio = (path, begin)
                default: break
                }
            case let .end(name):
                switch localName(name) {
                case "par": if inPar { flushPar() }
                case "seq": if !seqStack.isEmpty { seqStack.removeLast() }
                default: break
                }
            case .text: break
            }
        }
        // A truncated file can end inside a <par>; its text reference is still valid.
        if inPar { flushPar() }
        return entries
    }
}

/// Parses SMIL clock values: "12.5s", "500ms", "1.5min", "2h", "01:02.5", "00:01:02.500", "12.5".
enum SMILClock {
    static func seconds(_ raw: String) -> Double? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        if value.contains(":") {
            let parts = value.split(separator: ":").map(String.init)
            guard parts.count == 2 || parts.count == 3 else { return nil }
            var total = 0.0
            for part in parts {
                guard let number = Double(part) else { return nil }
                total = total * 60 + number
            }
            return total
        }
        let units: [(String, Double)] = [("ms", 0.001), ("min", 60), ("h", 3600), ("s", 1)]
        for (suffix, factor) in units where value.hasSuffix(suffix) {
            return Double(value.dropLast(suffix.count)).map { $0 * factor }
        }
        return Double(value)
    }
}
