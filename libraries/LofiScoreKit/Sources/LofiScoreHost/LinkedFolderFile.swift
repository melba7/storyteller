import Foundation

/// Reading one small file from the folder the listener linked, for things the Mac leaves
/// there besides sounds (the Apple Podcasts follow list at `Podcasts/apple-podcasts.json`).
public enum LinkedFolderFile {
    /// Files larger than this are not read; the Mac's files are a few kilobytes.
    public static let sizeLimit = 5_000_000

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
