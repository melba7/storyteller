import Foundation
import XCTest
@testable import LofiScoreHost

/// Reading one small file from the linked folder.
final class LinkedFolderFileTests: XCTestCase {
    private var folder: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        folder = fileManager.temporaryDirectory.appendingPathComponent("lofi-linked-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: folder.appendingPathComponent("Podcasts"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: folder)
    }

    func testReadsAFileBelowTheFolder() throws {
        try Data("{}".utf8).write(to: folder.appendingPathComponent("Podcasts/apple-podcasts.json"))
        XCTAssertEqual(LinkedFolderFile.read("Podcasts/apple-podcasts.json", in: folder), Data("{}".utf8))
    }

    func testAMissingFileOrFolderIsNil() {
        XCTAssertNil(LinkedFolderFile.read("Podcasts/none.json", in: folder))
        XCTAssertNil(LinkedFolderFile.read("Podcasts/apple-podcasts.json", in: folder.appendingPathComponent("gone")))
    }

    func testPathsOutOfTheFolderAreRefused() throws {
        try Data("secret".utf8).write(to: folder.deletingLastPathComponent().appendingPathComponent("lofi-linked-outside.txt"))
        defer { try? fileManager.removeItem(at: folder.deletingLastPathComponent().appendingPathComponent("lofi-linked-outside.txt")) }
        XCTAssertNil(LinkedFolderFile.read("../lofi-linked-outside.txt", in: folder))
        XCTAssertNil(LinkedFolderFile.read("Podcasts/../../lofi-linked-outside.txt", in: folder))
        XCTAssertNil(LinkedFolderFile.read("/etc/hostname", in: folder))
        XCTAssertNil(LinkedFolderFile.read("", in: folder))
        XCTAssertNil(LinkedFolderFile.read("Podcasts//x", in: folder))
    }

    func testAFileOverTheLimitIsNotRead() throws {
        try Data(count: LinkedFolderFile.sizeLimit + 1).write(to: folder.appendingPathComponent("Podcasts/big.json"))
        XCTAssertNil(LinkedFolderFile.read("Podcasts/big.json", in: folder))
    }

    // MARK: What the read found

    func testFetchSaysFoundMissingOrNotDownloaded() throws {
        try Data("{}".utf8).write(to: folder.appendingPathComponent("Podcasts/apple-podcasts.json"))
        XCTAssertEqual(LinkedFolderFile.fetch("Podcasts/apple-podcasts.json", in: folder), .found(Data("{}".utf8)))
        XCTAssertEqual(LinkedFolderFile.fetch("Podcasts/none.json", in: folder), .missing)
        XCTAssertEqual(LinkedFolderFile.fetch("Podcasts/x.json", in: folder.appendingPathComponent("gone")), .folderGone)
        // iCloud's placeholder for a file that is not on the phone yet.
        try Data().write(to: folder.appendingPathComponent("Podcasts/.later.json.icloud"))
        XCTAssertEqual(LinkedFolderFile.fetch("Podcasts/later.json", in: folder), .notDownloaded)
    }

    func testFetchRefusesPathsOutOfTheFolderAndHugeFiles() throws {
        XCTAssertEqual(LinkedFolderFile.fetch("../x", in: folder), .unreadable("The file's path is not allowed."))
        let big = Data(count: LinkedFolderFile.sizeLimit + 1)
        try big.write(to: folder.appendingPathComponent("Podcasts/big.json"))
        XCTAssertEqual(LinkedFolderFile.fetch("Podcasts/big.json", in: folder), .unreadable("The file is too large."))
    }
}
