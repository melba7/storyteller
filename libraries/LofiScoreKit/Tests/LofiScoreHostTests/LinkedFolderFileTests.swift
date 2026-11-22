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

    // MARK: Writing a small file

    func testWriteMakesTheSubfolderAndReplacesTheFile() throws {
        XCTAssertEqual(LinkedFolderFile.write("Podcasts/phone-notes.jsonl", data: Data("a\n".utf8), in: folder), .written)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("Podcasts/phone-notes.jsonl")), Data("a\n".utf8))
        XCTAssertEqual(LinkedFolderFile.write("New/Deeper/x.txt", data: Data("b".utf8), in: folder), .written)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("New/Deeper/x.txt")), Data("b".utf8))
        XCTAssertEqual(LinkedFolderFile.write("Podcasts/phone-notes.jsonl", data: Data("c\n".utf8), in: folder), .written)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("Podcasts/phone-notes.jsonl")), Data("c\n".utf8))
        // Nothing else is left beside it (the atomic write's temporary file is gone).
        let names = try fileManager.contentsOfDirectory(atPath: folder.appendingPathComponent("Podcasts").path)
        XCTAssertEqual(names, ["phone-notes.jsonl"])
    }

    func testWriteRefusesPathsOutOfTheFolder() {
        let refused = LinkedFolderFile.WriteOutcome.unwritable("The file's path is not allowed.")
        for path in ["../lofi-linked-out.txt", "Podcasts/../../lofi-linked-out.txt", "/tmp/lofi-linked-out.txt", "", "Podcasts//x"] {
            XCTAssertEqual(LinkedFolderFile.write(path, data: Data("x".utf8), in: folder), refused, path)
        }
        XCTAssertFalse(fileManager.fileExists(atPath: folder.deletingLastPathComponent().appendingPathComponent("lofi-linked-out.txt").path))
    }

    func testWriteSaysWhenTheFolderIsGoneAndRefusesHugeData() {
        XCTAssertEqual(LinkedFolderFile.write("Podcasts/x", data: Data("x".utf8), in: folder.appendingPathComponent("gone")), .folderGone)
        XCTAssertFalse(fileManager.fileExists(atPath: folder.appendingPathComponent("gone").path))
        XCTAssertEqual(
            LinkedFolderFile.write("Podcasts/big", data: Data(count: LinkedFolderFile.sizeLimit + 1), in: folder),
            .unwritable("The file is too large."))
        XCTAssertEqual(LinkedFolderFile.write("Podcasts/exact", data: Data(count: LinkedFolderFile.sizeLimit), in: folder), .written)
    }

    func testWriteSaysWhyItCouldNotWrite() throws {
        // A file where the subfolder should be.
        try Data("x".utf8).write(to: folder.appendingPathComponent("Blocked"))
        let outcome = LinkedFolderFile.write("Blocked/x.txt", data: Data("x".utf8), in: folder)
        guard case .unwritable(let message) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertFalse(message.isEmpty)
    }
}
