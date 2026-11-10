import Foundation
import LofiAudio
import LofiScoreCore

/// Measures a music library and writes its `library.json`, so the player can set each
/// track's bed level from its real loudness instead of assuming −16 LUFS.
///
/// The decoding is injected (`lofi-import` uses AVFoundation, which reads MP3 and AAC), so
/// the rest runs and is tested everywhere.
public enum LibraryImporter {
    public struct Measurement: Sendable, Hashable {
        /// Integrated loudness, LUFS.
        public var loudness: Double
        /// dBTP (estimated).
        public var truePeak: Double
        /// Seconds.
        public var duration: Double
    }

    /// Where a track came from, as recorded next to the music (`SOURCES.csv`).
    public struct Provenance: Sendable, Hashable {
        public var source: String?
        public var license: String?
    }

    public struct Outcome: Sendable {
        public var manifest: LibraryManifest
        /// Tracks that could not be decoded, with the reason. They stay in the manifest
        /// unmeasured.
        public var failures: [(file: String, reason: String)]
    }

    public static func measure(_ audio: StereoBuffer) -> Measurement {
        Measurement(
            loudness: rounded(Loudness.integrated(audio)),
            truePeak: rounded(Loudness.truePeak(audio)),
            duration: (audio.duration * 1000).rounded() / 1000
        )
    }

    /// Measures every track of `library` and returns the manifest to write. Fields already
    /// in a previous `library.json` (tempo, key, provenance) are kept; loudness, true peak
    /// and duration are measured again.
    public static func importLibrary(
        _ library: MusicLibrary,
        provenance: [String: Provenance] = [:],
        decode: (URL) throws -> StereoBuffer,
        progress: ((_ done: Int, _ total: Int, _ track: LibraryTrack, _ measurement: Measurement?) -> Void)? = nil
    ) -> Outcome {
        var tracks: [LibraryTrack] = []
        var failures: [(file: String, reason: String)] = []
        for (index, original) in library.tracks.enumerated() {
            var track = original
            var measurement: Measurement?
            do {
                let audio = try decode(library.url(for: track))
                if audio.frames > 0 {
                    let measured = measure(audio)
                    measurement = measured
                    track.loudness = measured.loudness.isFinite ? measured.loudness : nil
                    track.truePeak = measured.truePeak.isFinite ? measured.truePeak : nil
                    track.duration = measured.duration
                } else {
                    failures.append((track.file, "no audio"))
                }
            } catch {
                failures.append((track.file, "\(error)"))
            }
            if let recorded = provenance[key(for: track.file)] {
                if track.source == nil || track.source == "folder scan" {
                    track.source = recorded.source ?? track.source
                }
                if track.license == nil {
                    track.license = recorded.license
                }
            }
            tracks.append(track)
            progress?(index + 1, library.tracks.count, track, measurement)
        }
        return Outcome(manifest: LibraryManifest(version: 1, targetLoudness: nil, tracks: tracks), failures: failures)
    }

    // MARK: - SOURCES.csv

    /// Reads a provenance table: a header row, then one row per track. The file column is
    /// the one whose header mentions "file"; the source is the "page" column (or one that
    /// mentions "url" or "source"); the license is the column that mentions "license".
    /// Rows are matched to tracks by file name, ignoring case and folders.
    public static func provenance(csv text: String) -> [String: Provenance] {
        let rows = parseCSV(text)
        guard let header = rows.first?.map({ $0.lowercased() }) else { return [:] }
        guard let fileColumn = header.firstIndex(where: { $0.contains("file") }) else { return [:] }
        let sourceColumn = header.firstIndex(where: { $0.contains("page") })
            ?? header.firstIndex(where: { $0.contains("url") || $0.contains("source") })
        let licenseColumn = header.firstIndex(where: { $0.contains("license") || $0.contains("licence") })
        var result: [String: Provenance] = [:]
        for row in rows.dropFirst() where row.indices.contains(fileColumn) {
            func value(_ column: Int?) -> String? {
                guard let column, row.indices.contains(column) else { return nil }
                let trimmed = row[column].trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? nil : trimmed
            }
            result[key(for: row[fileColumn])] = Provenance(source: value(sourceColumn), license: value(licenseColumn))
        }
        return result
    }

    /// RFC 4180-style CSV: commas, quoted fields with doubled quotes, CRLF or LF.
    public static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var iterator = Array(text).makeIterator()
        var pending: Character?
        func nextCharacter() -> Character? {
            if let character = pending {
                pending = nil
                return character
            }
            return iterator.next()
        }
        while let character = nextCharacter() {
            if quoted {
                if character == "\"" {
                    if let following = nextCharacter() {
                        if following == "\"" {
                            field.append("\"")
                        } else {
                            quoted = false
                            pending = following
                        }
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"":
                quoted = true
            case ",":
                row.append(field)
                field = ""
            case "\n", "\r\n", "\r":
                row.append(field)
                field = ""
                if !(row.count == 1 && row[0].isEmpty) {
                    rows.append(row)
                }
                row = []
            default:
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    static func key(for file: String) -> String {
        (file as NSString).lastPathComponent.lowercased()
    }

    private static func rounded(_ value: Double) -> Double {
        value.isFinite ? (value * 100).rounded() / 100 : value
    }
}
