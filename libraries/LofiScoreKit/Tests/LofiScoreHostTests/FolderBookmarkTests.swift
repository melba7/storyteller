import Foundation
import XCTest
@testable import LofiScoreHost

/// Keeping a link to a picked folder. On an iPhone a folder from the document picker can be
/// bookmarked only while its security scope is open, so the bookmark is made inside it.
final class FolderBookmarkTests: XCTestCase {
    func testTheWorkRunsInsideTheScopeAndTheScopeIsClosedAfter() throws {
        var steps: [String] = []
        let folder = URL(fileURLWithPath: "/tmp/LofiMusic", isDirectory: true)
        let made = try FolderBookmark.insideScope(
            of: folder,
            start: { url in steps.append("start \(url.lastPathComponent)"); return true },
            stop: { url in steps.append("stop \(url.lastPathComponent)") }
        ) { () throws -> Data in
            steps.append("bookmark")
            return Data("link".utf8)
        }
        XCTAssertEqual(made, Data("link".utf8))
        XCTAssertEqual(steps, ["start LofiMusic", "bookmark", "stop LofiMusic"])
    }

    func testAScopeThatDidNotOpenIsNotClosed() throws {
        var steps: [String] = []
        let folder = URL(fileURLWithPath: "/tmp/LofiMusic", isDirectory: true)
        _ = try FolderBookmark.insideScope(
            of: folder,
            start: { _ in steps.append("start"); return false },
            stop: { _ in steps.append("stop") }
        ) { () throws -> Data in
            steps.append("bookmark")
            return Data()
        }
        XCTAssertEqual(steps, ["start", "bookmark"])
    }

    func testTheScopeIsClosedWhenTheWorkFails() {
        struct Refused: Error {}
        var steps: [String] = []
        let folder = URL(fileURLWithPath: "/tmp/LofiMusic", isDirectory: true)
        XCTAssertThrowsError(
            try FolderBookmark.insideScope(
                of: folder,
                start: { _ in steps.append("start"); return true },
                stop: { _ in steps.append("stop") }
            ) { () throws -> Data in throw Refused() }
        )
        XCTAssertEqual(steps, ["start", "stop"])
    }
}
