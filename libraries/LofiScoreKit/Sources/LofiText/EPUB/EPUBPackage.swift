import Foundation

/// Errors from reading a readaloud book.
public enum ReadaloudBookError: Error, Equatable, CustomStringConvertible {
    case missingContainer
    case missingPackageDocument(String)
    case unreadableFile(String)
    case noNarratedChapters

    public var description: String {
        switch self {
        case .missingContainer: "META-INF/container.xml is missing or names no package document"
        case .missingPackageDocument(let path): "package document not found: \(path)"
        case .unreadableFile(let path): "could not read \(path)"
        case .noNarratedChapters: "the book has no spine items with media overlays"
        }
    }
}

/// A manifest entry from the OPF.
struct ManifestItem: Equatable {
    let id: String
    /// Container-relative path.
    let path: String
    let mediaType: String
    let properties: Set<String>
    /// The manifest id of this item's SMIL file, if it has one.
    let mediaOverlayID: String?
}

/// A spine entry from the OPF.
struct SpineItem: Equatable {
    let idref: String
    let linear: Bool
}

/// The parts of the OPF package document that the text side needs.
///
/// Book-level metadata such as the title is deliberately not kept: nothing on
/// the text side should hand a model the name of the book it might know.
struct EPUBPackage {
    let packagePath: String
    let manifest: [String: ManifestItem]
    let spine: [SpineItem]

    /// Finds the package document through META-INF/container.xml.
    static func locatePackage(in files: any BookFileAccess) throws -> String {
        guard let data = try? files.read("META-INF/container.xml") else {
            throw ReadaloudBookError.missingContainer
        }
        var first: String? = nil
        var preferred: String? = nil
        MarkupScanner(data: data).scan { event in
            guard case let .start(name, attributes, _) = event, localName(name) == "rootfile",
                let fullPath = attributes["full-path"]
            else { return }
            let path = EPUBPath.normalize(fullPath.removingPercentEncoding ?? fullPath)
            if first == nil { first = path }
            if preferred == nil, attributes["media-type"] == "application/oebps-package+xml" {
                preferred = path
            }
        }
        guard let path = preferred ?? first else { throw ReadaloudBookError.missingContainer }
        return path
    }

    static func parse(_ data: Data, packagePath: String) -> EPUBPackage {
        var manifest: [String: ManifestItem] = [:]
        var spine: [SpineItem] = []
        var inManifest = false
        var inSpine = false

        MarkupScanner(data: data).scan { event in
            switch event {
            case let .start(name, attributes, selfClosing):
                switch localName(name) {
                case "manifest": inManifest = !selfClosing
                case "spine": inSpine = !selfClosing
                case "item" where inManifest:
                    guard let id = attributes["id"], let href = attributes["href"] else { return }
                    let resolved = EPUBPath.resolve(href, relativeTo: packagePath).path
                    let properties = Set((attributes["properties"] ?? "").split(separator: " ").map(String.init))
                    manifest[id] = ManifestItem(
                        id: id,
                        path: resolved,
                        mediaType: attributes["media-type"] ?? "",
                        properties: properties,
                        mediaOverlayID: attributes["media-overlay"]
                    )
                case "itemref" where inSpine:
                    guard let idref = attributes["idref"] else { return }
                    let linear = (attributes["linear"] ?? "yes").lowercased() != "no"
                    spine.append(SpineItem(idref: idref, linear: linear))
                default: break
                }
            case let .end(name):
                switch localName(name) {
                case "manifest": inManifest = false
                case "spine": inSpine = false
                default: break
                }
            case .text: break
            }
        }
        return EPUBPackage(packagePath: packagePath, manifest: manifest, spine: spine)
    }
}

/// "opf:item" -> "item".
func localName(_ qualified: String) -> String {
    guard let colon = qualified.lastIndex(of: ":") else { return qualified }
    return String(qualified[qualified.index(after: colon)...])
}

/// Read access to the files of an unzipped EPUB. Only `LofiText` uses it.
protocol BookFileAccess: Sendable {
    func read(_ containerPath: String) throws -> Data
}

/// Files on disk under the unzipped book's root directory, such as
/// `Documents/books/extracted/<uuid>/readaloud/` in the Storyteller app.
struct DirectoryFileAccess: BookFileAccess {
    let root: URL

    func read(_ containerPath: String) throws -> Data {
        let url = root.appendingPathComponent(containerPath, isDirectory: false)
        do {
            return try Data(contentsOf: url)
        } catch {
            throw ReadaloudBookError.unreadableFile(containerPath)
        }
    }
}
