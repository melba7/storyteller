import Foundation

/// Finds the file in a few folders that holds a book's track, and remembers the answer.
///
/// The finders match a track to its book by the digests of its first sentences, which
/// means decoding candidate files until one matches. With hundreds of scored books in
/// `MoodTracks/` that is too slow to do on every open, so the answer is kept in
/// `.matches.json` in the first folder that exists: which file matched the book, or that
/// nothing did while the folders held these files. Once the folders change (a new score
/// arrives), the book is looked for again.
///
/// Nothing read here reaches the music: the memory holds file names and sizes.
enum TrackMatchMemory {
    static let fileName = ".matches.json"

    struct Entry: Codable, Equatable {
        /// The file that matched, as "<folder index>/<name>"; nil when nothing matched.
        var file: String?
        /// What the folders held when the book was looked for.
        var signature: String
    }

    struct Candidate {
        var url: URL
        var folderIndex: Int
        var modified: Date
        var size: Int

        var key: String { "\(folderIndex)/\(url.lastPathComponent)" }
    }

    /// Looks for the book: the remembered file first, then the files named after the book,
    /// then the rest, newest first, until `matches` says one is the book's.
    static func lookUp<Track>(
        key: String,
        bookID: String,
        folders: [URL],
        isCandidate: (URL) -> Bool,
        bookName: (URL) -> String,
        decode: (URL) -> Track?,
        matches: (Track) -> Bool,
        fileManager: FileManager = .default
    ) -> (track: Track, file: URL)? {
        let candidates = self.candidates(in: folders, isCandidate: isCandidate, fileManager: fileManager)
        guard !candidates.isEmpty else { return nil }
        let signature = self.signature(of: candidates)
        let memoryFolder = folders.first { fileManager.fileExists(atPath: $0.path) }
        let memory = memoryFolder.flatMap { load(from: $0) } ?? [:]
        let remembered = memory[key]

        func check(_ candidate: Candidate) -> (Track, URL)? {
            guard let track = decode(candidate.url), matches(track) else { return nil }
            return (track, candidate.url)
        }
        func remember(_ file: String?) {
            guard let memoryFolder else { return }
            var updated = memory
            updated[key] = Entry(file: file, signature: signature)
            save(updated, to: memoryFolder)
        }

        var tried: Set<String> = []
        if let remembered {
            if let file = remembered.file, let candidate = candidates.first(where: { $0.key == file }) {
                tried.insert(file)
                if let found = check(candidate) {
                    if remembered.signature != signature { remember(file) }
                    return found
                }
            } else if remembered.file == nil, remembered.signature == signature {
                return nil
            }
        }

        let named = candidates.filter { bookName($0.url) == bookID && !tried.contains($0.key) }
        let others = candidates
            .filter { bookName($0.url) != bookID && !tried.contains($0.key) }
            .sorted { ($0.modified, $0.url.lastPathComponent) > ($1.modified, $1.url.lastPathComponent) }
        for candidate in named + others {
            if let found = check(candidate) {
                remember(candidate.key)
                return found
            }
        }
        remember(nil)
        return nil
    }

    static func candidates(in folders: [URL], isCandidate: (URL) -> Bool, fileManager: FileManager) -> [Candidate] {
        var result: [Candidate] = []
        for (index, folder) in folders.enumerated() {
            let files = (try? fileManager.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
            )) ?? []
            for file in files where !file.lastPathComponent.hasPrefix(".") && isCandidate(file) {
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                result.append(Candidate(
                    url: file, folderIndex: index, modified: values?.contentModificationDate ?? .distantPast, size: values?.fileSize ?? 0
                ))
            }
        }
        return result
    }

    static func signature(of candidates: [Candidate]) -> String {
        let lines = candidates
            .map { "\($0.key)|\($0.size)|\(Int($0.modified.timeIntervalSince1970))" }
            .sorted()
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in lines.joined(separator: "\n").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    static func load(from folder: URL) -> [String: Entry]? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(fileName)) else { return nil }
        return try? JSONDecoder().decode([String: Entry].self, from: data)
    }

    static func save(_ memory: [String: Entry], to folder: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(memory) else { return }
        try? data.write(to: folder.appendingPathComponent(fileName), options: .atomic)
    }
}
