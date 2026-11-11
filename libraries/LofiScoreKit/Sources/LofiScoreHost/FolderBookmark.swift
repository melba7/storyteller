import Foundation

/// Remembering a folder the listener picked, across launches.
///
/// On Apple platforms a folder from the document picker can only be read again through a
/// security-scoped bookmark. Elsewhere (the Linux tests) the folder's path is kept.
public enum FolderBookmark {
    public enum LinkError: Error, CustomStringConvertible {
        case notAFolder(String)
        public var description: String {
            switch self {
            case let .notAFolder(path): return "\(path) is not a folder the app can read"
            }
        }
    }

    public static func make(_ folder: URL) throws -> Data {
        #if canImport(Darwin)
        #if os(macOS)
        return try folder.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        return try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
        #else
        return Data(folder.path.utf8)
        #endif
    }

    public static func resolve(_ bookmark: Data) throws -> URL {
        #if canImport(Darwin)
        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
        #else
        let options: URL.BookmarkResolutionOptions = [.withoutUI]
        #endif
        let url = try URL(resolvingBookmarkData: bookmark, options: options, relativeTo: nil, bookmarkDataIsStale: &stale)
        return url
        #else
        guard let path = String(data: bookmark, encoding: .utf8) else { throw LinkError.notAFolder("?") }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LinkError.notAFolder(path)
        }
        return url
        #endif
    }
}
