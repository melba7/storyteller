import Foundation

/// The music folder's `SOURCES.csv`: where each track came from, with its title, artist and
/// license. The library's install script writes it beside `library.json`; the player only
/// reads the names, for the music panel's "now playing" line.
///
/// Columns used (by header name, any order): `file`, `title`, `artist`, `license_name`.
public struct TrackSources: Sendable, Hashable {
    public struct Entry: Sendable, Hashable {
        public var title: String?
        public var artist: String?
        public var licenseName: String?
    }

    public static let fileName = "SOURCES.csv"

    /// Entries by the track's path inside the library, such as "Calm/Calm Waters - Purrple Cat.mp3".
    public var entries: [String: Entry]

    public init(entries: [String: Entry] = [:]) {
        self.entries = entries
    }

    /// Reads `SOURCES.csv` from `folder`, or returns nil when there is none or it has no
    /// `file` column.
    public static func load(from folder: URL) -> TrackSources? {
        let url = folder.appendingPathComponent(fileName)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    public static func parse(_ text: String) -> TrackSources? {
        let rows = CSV.rows(text)
        guard let header = rows.first else { return nil }
        let names = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let file = names.firstIndex(of: "file") else { return nil }
        let title = names.firstIndex(of: "title")
        let artist = names.firstIndex(of: "artist")
        let license = names.firstIndex(of: "license_name")
        func value(_ row: [String], _ index: Int?) -> String? {
            guard let index, index < row.count else { return nil }
            let trimmed = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        var entries: [String: Entry] = [:]
        for row in rows.dropFirst() {
            guard let path = value(row, file) else { continue }
            entries[path] = Entry(title: value(row, title), artist: value(row, artist), licenseName: value(row, license))
        }
        return TrackSources(entries: entries)
    }

    /// `tracks` with any missing title, artist or license name filled in from here.
    public func filling(_ tracks: [LibraryTrack]) -> [LibraryTrack] {
        tracks.map { track in
            guard let entry = entries[track.file] else { return track }
            var filled = track
            filled.title = filled.title ?? entry.title
            filled.artist = filled.artist ?? entry.artist
            filled.licenseName = filled.licenseName ?? entry.licenseName
            return filled
        }
    }
}

/// A small RFC 4180 reader: commas, double-quoted fields with "" for a quote, and line
/// breaks inside quotes.
enum CSV {
    static func rows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var iterator = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar?
        func next() -> Unicode.Scalar? {
            if let scalar = pending {
                pending = nil
                return scalar
            }
            return iterator.next()
        }
        func endRow() {
            row.append(field)
            field = ""
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }
        while let scalar = next() {
            if quoted {
                if scalar == "\"" {
                    if let following = next() {
                        if following == "\"" {
                            field.unicodeScalars.append("\"")
                        } else {
                            quoted = false
                            pending = following
                        }
                    } else {
                        quoted = false
                    }
                } else {
                    field.unicodeScalars.append(scalar)
                }
                continue
            }
            switch scalar {
            case "\"" where field.isEmpty:
                quoted = true
            case ",":
                row.append(field)
                field = ""
            case "\r":
                break
            case "\n":
                endRow()
            case "\u{FEFF}" where rows.isEmpty && row.isEmpty && field.isEmpty:
                break
            default:
                field.unicodeScalars.append(scalar)
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}
