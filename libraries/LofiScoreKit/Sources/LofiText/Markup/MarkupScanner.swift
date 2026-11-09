import Foundation

/// One event from `MarkupScanner`.
enum MarkupEvent: Equatable {
    /// An opening tag. Names are lowercased; attribute values are entity-decoded.
    case start(name: String, attributes: [String: String], selfClosing: Bool)
    /// A closing tag, lowercased.
    case end(name: String)
    /// Character data with entities decoded. CDATA sections arrive as text too.
    case text(String)
}

/// A forgiving tokenizer for the XML and XHTML found in EPUB files.
///
/// It never throws. Malformed or truncated input yields every event that can be
/// recovered, which matters for the spoiler guard: cutting a chapter file off
/// after the sentence being narrated must not change what is read before it.
///
/// It does not validate, resolve namespaces, or load DTDs. Element and attribute
/// names keep their prefixes (`epub:type`) and are lowercased.
struct MarkupScanner {
    private let bytes: [UInt8]

    init(data: Data) {
        self.bytes = MarkupScanner.utf8Bytes(from: data)
    }

    init(string: String) {
        self.bytes = Array(string.utf8)
    }

    /// Calls `handle` for every event, in document order.
    func scan(_ handle: (MarkupEvent) -> Void) {
        let n = bytes.count
        var i = 0
        while i < n {
            if bytes[i] == UInt8(ascii: "<") {
                i = scanMarkup(at: i, handle)
            } else {
                var j = i
                while j < n && bytes[j] != UInt8(ascii: "<") { j += 1 }
                let raw = String(decoding: bytes[i..<j], as: UTF8.self)
                handle(.text(MarkupScanner.decodeEntities(raw)))
                i = j
            }
        }
    }

    /// Collects all events into an array. Convenient for small documents and tests.
    func events() -> [MarkupEvent] {
        var all: [MarkupEvent] = []
        scan { all.append($0) }
        return all
    }

    // MARK: - Markup

    /// Scans markup starting at a `<` and returns the index just past it.
    private func scanMarkup(at start: Int, _ handle: (MarkupEvent) -> Void) -> Int {
        let n = bytes.count
        let next = start + 1
        guard next < n else { return n }  // a lone '<' at the very end: drop it

        switch bytes[next] {
        case UInt8(ascii: "!"):
            if hasPrefix("<!--", at: start) {
                return indexAfter("-->", from: start + 4) ?? n
            }
            if hasPrefix("<![CDATA[", at: start) {
                let contentStart = start + 9
                if let close = index(of: "]]>", from: contentStart) {
                    handle(.text(String(decoding: bytes[contentStart..<close], as: UTF8.self)))
                    return close + 3
                }
                handle(.text(String(decoding: bytes[contentStart..<n], as: UTF8.self)))
                return n
            }
            return skipDeclaration(from: next + 1)
        case UInt8(ascii: "?"):
            return indexAfter("?>", from: next + 1) ?? n
        case UInt8(ascii: "/"):
            var j = next + 1
            while j < n && bytes[j] != UInt8(ascii: ">") { j += 1 }
            guard j < n else { return n }  // truncated closing tag: drop it
            let name = String(decoding: bytes[(next + 1)..<j], as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if !name.isEmpty { handle(.end(name: name)) }
            return j + 1
        default:
            guard MarkupScanner.isNameStart(bytes[next]) else {
                // Not a tag after all ("a < b"): keep the '<' as text.
                handle(.text("<"))
                return next
            }
            return scanStartTag(at: start, handle)
        }
    }

    private func scanStartTag(at start: Int, _ handle: (MarkupEvent) -> Void) -> Int {
        let n = bytes.count
        var j = start + 1
        let nameStart = j
        while j < n && MarkupScanner.isNameChar(bytes[j]) { j += 1 }
        let name = String(decoding: bytes[nameStart..<j], as: UTF8.self).lowercased()

        var attributes: [String: String] = [:]
        while j < n {
            // Skip whitespace between attributes.
            while j < n && MarkupScanner.isSpace(bytes[j]) { j += 1 }
            guard j < n else { return n }  // truncated inside a tag: drop the tag

            let c = bytes[j]
            if c == UInt8(ascii: ">") {
                handle(.start(name: name, attributes: attributes, selfClosing: false))
                return j + 1
            }
            if c == UInt8(ascii: "/") {
                if j + 1 < n && bytes[j + 1] == UInt8(ascii: ">") {
                    handle(.start(name: name, attributes: attributes, selfClosing: true))
                    return j + 2
                }
                j += 1
                continue
            }

            // Attribute name.
            let attrStart = j
            while j < n && !MarkupScanner.isSpace(bytes[j])
                && bytes[j] != UInt8(ascii: "=") && bytes[j] != UInt8(ascii: ">")
                && !(bytes[j] == UInt8(ascii: "/") && j + 1 < n && bytes[j + 1] == UInt8(ascii: ">"))
            {
                j += 1
            }
            let attrName = String(decoding: bytes[attrStart..<j], as: UTF8.self).lowercased()
            if j == attrStart {
                j += 1  // a stray character; skip it
                continue
            }
            while j < n && MarkupScanner.isSpace(bytes[j]) { j += 1 }
            guard j < n else { return n }

            var value = ""
            if bytes[j] == UInt8(ascii: "=") {
                j += 1
                while j < n && MarkupScanner.isSpace(bytes[j]) { j += 1 }
                guard j < n else { return n }
                let quote = bytes[j]
                if quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'") {
                    let valueStart = j + 1
                    var k = valueStart
                    while k < n && bytes[k] != quote { k += 1 }
                    guard k < n else { return n }  // unterminated value: truncated tag
                    value = String(decoding: bytes[valueStart..<k], as: UTF8.self)
                    j = k + 1
                } else {
                    let valueStart = j
                    while j < n && !MarkupScanner.isSpace(bytes[j]) && bytes[j] != UInt8(ascii: ">") { j += 1 }
                    value = String(decoding: bytes[valueStart..<j], as: UTF8.self)
                }
            }
            if attributes[attrName] == nil {
                attributes[attrName] = MarkupScanner.decodeEntities(value)
            }
        }
        return n
    }

    /// Skips `<!DOCTYPE ...>` and similar, including an internal subset in brackets.
    private func skipDeclaration(from start: Int) -> Int {
        let n = bytes.count
        var j = start
        var depth = 0
        var quote: UInt8? = nil
        while j < n {
            let c = bytes[j]
            if let q = quote {
                if c == q { quote = nil }
            } else if c == UInt8(ascii: "\"") || c == UInt8(ascii: "'") {
                quote = c
            } else if c == UInt8(ascii: "[") {
                depth += 1
            } else if c == UInt8(ascii: "]") {
                depth = max(0, depth - 1)
            } else if c == UInt8(ascii: ">") && depth == 0 {
                return j + 1
            }
            j += 1
        }
        return n
    }

    // MARK: - Byte helpers

    private func hasPrefix(_ prefix: StaticString, at index: Int) -> Bool {
        let p = prefix.utf8Start
        let count = prefix.utf8CodeUnitCount
        guard index + count <= bytes.count else { return false }
        for k in 0..<count where bytes[index + k] != p[k] {
            return false
        }
        return true
    }

    private func index(of needle: StaticString, from start: Int) -> Int? {
        let count = needle.utf8CodeUnitCount
        guard count > 0, bytes.count >= count else { return nil }
        var i = max(0, start)
        while i + count <= bytes.count {
            if hasPrefix(needle, at: i) { return i }
            i += 1
        }
        return nil
    }

    private func indexAfter(_ needle: StaticString, from start: Int) -> Int? {
        index(of: needle, from: start).map { $0 + needle.utf8CodeUnitCount }
    }

    private static func isSpace(_ c: UInt8) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C
    }

    private static func isNameStart(_ c: UInt8) -> Bool {
        (c >= UInt8(ascii: "a") && c <= UInt8(ascii: "z"))
            || (c >= UInt8(ascii: "A") && c <= UInt8(ascii: "Z"))
            || c == UInt8(ascii: "_") || c == UInt8(ascii: ":") || c >= 0x80
    }

    private static func isNameChar(_ c: UInt8) -> Bool {
        isNameStart(c) || (c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9"))
            || c == UInt8(ascii: "-") || c == UInt8(ascii: ".")
    }

    /// Returns UTF-8 bytes for the document, transcoding UTF-16 and dropping a BOM.
    private static func utf8Bytes(from data: Data) -> [UInt8] {
        let raw = [UInt8](data)
        if raw.starts(with: [0xEF, 0xBB, 0xBF]) { return Array(raw.dropFirst(3)) }
        if raw.starts(with: [0xFF, 0xFE]) || raw.starts(with: [0xFE, 0xFF]) {
            if let s = String(data: data, encoding: .utf16) { return Array(s.utf8) }
        }
        return raw
    }

    // MARK: - Entities

    /// Decodes `&amp;`, `&#160;`, `&#xA0;` and the HTML 4 named entities.
    /// Unknown or malformed references are left as written.
    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = String.UnicodeScalarView()
        let scalars = Array(s.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            guard c == "&" else {
                out.append(c)
                i += 1
                continue
            }
            // Look for ';' within a short distance.
            var j = i + 1
            while j < scalars.count && j - i <= 32 && scalars[j] != ";" && scalars[j] != "&"
                && !scalars[j].properties.isWhitespace
            {
                j += 1
            }
            guard j < scalars.count, scalars[j] == ";", j > i + 1 else {
                out.append(c)
                i += 1
                continue
            }
            let body = String(String.UnicodeScalarView(scalars[(i + 1)..<j]))
            if let scalar = resolveEntity(body) {
                out.append(scalar)
                i = j + 1
            } else {
                out.append(c)
                i += 1
            }
        }
        return String(out)
    }

    private static func resolveEntity(_ body: String) -> Unicode.Scalar? {
        if body.hasPrefix("#x") || body.hasPrefix("#X") {
            return UInt32(body.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init)
        }
        if body.hasPrefix("#") {
            return UInt32(body.dropFirst(), radix: 10).flatMap(Unicode.Scalar.init)
        }
        return HTMLEntities.table[body].flatMap(Unicode.Scalar.init)
    }
}
