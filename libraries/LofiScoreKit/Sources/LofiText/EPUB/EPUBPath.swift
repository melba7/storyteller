import Foundation

/// Paths inside an EPUB container, always relative to the container root
/// ("OEBPS/Text/chapter1.xhtml"), percent-decoded, without fragment or query.
enum EPUBPath {
    /// Resolves `reference` (an href as written in an OPF, SMIL or XHTML file)
    /// against the file it appears in. Returns the container-relative path and
    /// the fragment, if any.
    static func resolve(_ reference: String, relativeTo baseFile: String) -> (path: String, fragment: String?) {
        var ref = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        var fragment: String? = nil
        if let hash = ref.firstIndex(of: "#") {
            let frag = String(ref[ref.index(after: hash)...])
            fragment = frag.removingPercentEncoding ?? frag
            ref = String(ref[..<hash])
        }
        if let query = ref.firstIndex(of: "?") {
            ref = String(ref[..<query])
        }
        let decoded = ref.removingPercentEncoding ?? ref

        // An empty reference ("#id") points into the base file itself.
        if decoded.isEmpty {
            return (normalize(baseFile), fragment)
        }

        let combined: String
        if decoded.hasPrefix("/") {
            combined = decoded
        } else {
            combined = directory(of: baseFile) + decoded
        }
        return (normalize(combined), fragment)
    }

    /// "OEBPS/Text/ch1.xhtml" -> "OEBPS/Text/". A bare file name -> "".
    static func directory(of file: String) -> String {
        guard let slash = file.lastIndex(of: "/") else { return "" }
        return String(file[...slash])
    }

    /// Removes "." and ".." segments, duplicate and leading slashes.
    static func normalize(_ path: String) -> String {
        var parts: [Substring] = []
        for segment in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch segment {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(segment)
            }
        }
        return parts.joined(separator: "/")
    }

    /// Normalizes a resource path reported by a player (Readium's `textResource`,
    /// v3's `textHref`) so it can be compared with container-relative paths.
    static func normalizeReported(_ resource: String) -> String {
        var r = resource.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hash = r.firstIndex(of: "#") { r = String(r[..<hash]) }
        if let query = r.firstIndex(of: "?") { r = String(r[..<query]) }
        // Drop a scheme and host if a full URL slipped through.
        if let scheme = r.range(of: "://") {
            let afterScheme = r[scheme.upperBound...]
            if let slash = afterScheme.firstIndex(of: "/") {
                r = String(afterScheme[slash...])
            }
        }
        return normalize(r.removingPercentEncoding ?? r)
    }
}
