import Foundation

/// A more specific kind of one of the built-in sounds: church bells across a town (a kind
/// of `oldTown`), a waterfall (`river`), a café (`crowd`). Claude asks for one while it
/// scores a book when a place clearly calls for it, and a starter set comes with the
/// fetch script.
///
/// Its recordings are fetched online on the Mac (`Tools/atmosphere/fetch_ambience.py`)
/// into `Atmosphere/<Sound>.<Variant>/`, e.g. `OldTown.ChurchBells/`. Until they are
/// imported the phone plays the built-in sound it is a kind of, so a track never depends
/// on a recording being there. It behaves like that sound in every other way: weather or
/// place, whether the music steps aside, its level and its filter.
public struct SoundVariant: Codable, Sendable, Hashable {
    /// camelCase and never a built-in sound's name, e.g. "churchBells".
    public var id: String
    /// The built-in sound it is a kind of, which plays until it has recordings.
    public var of: AmbientSound
    /// What it is, for Claude and for the credits: "church bells ringing across a town".
    public var about: String
    /// Words to search a sound library with: "church bells town ambience".
    public var search: String
    /// Global index of the entry that first asked for it, in a book's track. The scorer
    /// is offered a book's own variants only after that point. Nil in a shared catalog.
    public var firstIndex: Int?

    public static let maxIDLength = 32

    public init(id: String, of sound: AmbientSound, about: String, search: String, firstIndex: Int? = nil) {
        self.id = id
        of = sound
        self.about = about
        self.search = search
        self.firstIndex = firstIndex
    }

    /// A valid id from Claude's or a folder's spelling ("church bells", "ChurchBells",
    /// "church_bells" all give "churchBells"), or nil when it is empty, too long, not
    /// plain letters and digits, or a built-in sound's name.
    public static func normalizedID(_ text: String) -> String? {
        let words = text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard let first = words.first else { return nil }
        var id = first.prefix(1).lowercased() + first.dropFirst()
        for word in words.dropFirst() {
            id += word.prefix(1).uppercased() + word.dropFirst()
        }
        guard id.count <= maxIDLength,
              id.first?.isLetter == true,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              AmbientSound(lenient: id) == nil
        else { return nil }
        return id
    }

    /// Its recordings' folder in the atmosphere library, e.g. "OldTown.ChurchBells".
    public var folderName: String { Self.folderName(of: of, id: id) }

    public static func folderName(of sound: AmbientSound, id: String) -> String {
        sound.folderName + "." + id.prefix(1).uppercased() + id.dropFirst()
    }

    /// Reads a variant folder's name: "OldTown.ChurchBells" is `churchBells`, a kind of `oldTown`.
    public static func parseFolder(_ name: String) -> (sound: AmbientSound, id: String)? {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let sound = AmbientSound(lenient: parts[0]),
              let id = normalizedID(parts[1])
        else { return nil }
        return (sound, id)
    }
}

/// The variants known on the Mac, `Atmosphere/variants.json`, which the fetch script
/// keeps: its starter set plus every variant a scored book asked for, with the books
/// that asked.
public struct SoundVariantCatalog: Codable, Sendable, Hashable {
    public static let fileName = "variants.json"

    public struct Entry: Codable, Sendable, Hashable {
        public var id: String
        public var of: AmbientSound
        public var about: String
        public var search: String
        /// The books (track `bookID`s) that asked for it.
        public var books: [String]?
        /// In the fetch script's starter set: offered to every book.
        public var starter: Bool?

        public init(id: String, of sound: AmbientSound, about: String, search: String, books: [String]? = nil, starter: Bool? = nil) {
            self.id = id
            of = sound
            self.about = about
            self.search = search
            self.books = books
            self.starter = starter
        }
    }

    public var version: Int
    public var variants: [Entry]

    public init(version: Int = 1, variants: [Entry]) {
        self.version = version
        self.variants = variants
    }

    public static func load(from url: URL) throws -> SoundVariantCatalog {
        try JSONDecoder().decode(SoundVariantCatalog.self, from: Data(contentsOf: url))
    }

    /// The variants to offer while scoring `bookID`. A variant only this same book asked
    /// for in an earlier run is left out: it may come from a later chapter, and the book's
    /// own track brings back its variants only after the point that first asked for them.
    /// The starter set and other books' variants say nothing about this book.
    public func offered(toBook bookID: String) -> [SoundVariant] {
        variants.compactMap { entry in
            guard let id = SoundVariant.normalizedID(entry.id) else { return nil }
            if entry.starter != true, (entry.books ?? []).contains(bookID) { return nil }
            return SoundVariant(id: id, of: entry.of, about: entry.about, search: entry.search)
        }
    }
}
