import Foundation

/// Reading one small file from the folder the listener linked, for things the Mac leaves
/// there besides sounds (the Apple Podcasts follow list at `Podcasts/apple-podcasts.json`).
public enum LinkedFolderFile {
    /// Files larger than this are not read; the Mac's files are a few kilobytes.
    public static let sizeLimit = 5_000_000

    /// What reading one file found, so the app can say why there is nothing.
    public enum Outcome: Equatable, Sendable {
        case found(Data)
        /// No folder is linked.
        case notLinked
        /// The linked folder cannot be opened (it was moved or deleted).
        case folderGone
        /// The folder is there and the file is not.
        case missing
        /// iCloud has the file but has not put it on the phone yet; it has been asked to.
        case notDownloaded
        case unreadable(String)
    }

    /// Like `read`, but says what was found. A file that is on the phone is read through a
    /// file coordinator, so iCloud settles any change first; one that is only a placeholder is
    /// asked for and reported as `notDownloaded` (the caller asks again a little later).
    public static func fetch(_ path: String, in folder: URL, fileManager: FileManager = .default) -> Outcome {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, !path.hasPrefix("/"), !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            return .unreadable("The file's path is not allowed.")
        }
        #if canImport(Darwin)
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        #endif
        var isFolder: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue else {
            return .folderGone
        }
        let file = parts.reduce(folder) { $0.appendingPathComponent($1) }
        guard fileManager.fileExists(atPath: file.path) else {
            let stub = file.deletingLastPathComponent().appendingPathComponent(".\(file.lastPathComponent).icloud")
            guard fileManager.fileExists(atPath: stub.path) else { return .missing }
            #if canImport(Darwin)
            try? fileManager.startDownloadingUbiquitousItem(at: file)
            #endif
            return .notDownloaded
        }
        guard let size = (try? fileManager.attributesOfItem(atPath: file.path))?[.size] as? Int else {
            return .unreadable("The file can't be read.")
        }
        guard size <= sizeLimit else { return .unreadable("The file is too large.") }
        var data: Data?
        #if canImport(Darwin)
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [.withoutChanges], error: &coordinationError) { url in
            data = try? Data(contentsOf: url)
        }
        if data == nil { data = try? Data(contentsOf: file) }
        #else
        data = try? Data(contentsOf: file)
        #endif
        guard let data else { return .unreadable("The file can't be read.") }
        return .found(data)
    }

    /// The file at `path` below `folder`, or nil when it is not there, not downloaded from
    /// iCloud yet, too large, or the path would leave the folder. Starts and stops the
    /// security-scoped access to the folder around the read. Never throws: a missing file is
    /// the normal case when the Mac has not written one.
    public static func read(_ path: String, in folder: URL, fileManager: FileManager = .default) -> Data? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, !path.hasPrefix("/"), !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            return nil
        }
        #if canImport(Darwin)
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        #endif

        let file = parts.reduce(folder) { $0.appendingPathComponent($1) }
        #if canImport(Darwin)
        if !fileManager.fileExists(atPath: file.path) {
            // A file iCloud has not downloaded is a hidden ".name.icloud" stub; ask for it, the next read finds it.
            let stub = file.deletingLastPathComponent().appendingPathComponent(".\(file.lastPathComponent).icloud")
            if fileManager.fileExists(atPath: stub.path) { try? fileManager.startDownloadingUbiquitousItem(at: file) }
        }
        #endif
        guard let size = (try? fileManager.attributesOfItem(atPath: file.path))?[.size] as? Int, size <= sizeLimit else {
            return nil
        }
        return try? Data(contentsOf: file)
    }
}
