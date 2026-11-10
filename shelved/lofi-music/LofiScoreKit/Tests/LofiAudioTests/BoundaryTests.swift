import XCTest

/// Keeps the music code inside its lane: the narrator owns the audio session, Now Playing
/// and the remote commands, and the music never changes speed. These checks scan the
/// source, so they also guard the Apple-only files that do not compile on Linux.
final class BoundaryTests: XCTestCase {
    private static let forbidden: [(token: String, reason: String)] = [
        ("setCategory", "the narrator owns the audio session category"),
        ("setMode", "the narrator owns the audio session mode"),
        ("setActive", "the narrator activates and deactivates the session"),
        ("setPreferred", "session preferences belong to the narrator"),
        ("overrideOutputAudioPort", "the narrator owns routing"),
        ("MPNowPlayingInfoCenter", "Now Playing belongs to the narrator"),
        ("MPRemoteCommandCenter", "remote commands belong to the narrator"),
        ("nowPlayingInfo", "Now Playing belongs to the narrator"),
        ("import MediaPlayer", "nothing in the music code needs MediaPlayer"),
        ("inputNode", "touching the input node asks for the microphone"),
        ("AVAudioUnitTimePitch", "the music never changes speed"),
        ("AVAudioUnitVarispeed", "the music never changes speed"),
    ]

    func testMusicCodeNeverTouchesTheNarratorsControls() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        var scanned = 0
        for target in ["LofiAudio", "LofiDirector", "LofiPlaceholders"] {
            let folder = root.appendingPathComponent("Sources").appendingPathComponent(target)
            guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else {
                return XCTFail("missing \(folder.path)")
            }
            for case let file as URL in files where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                scanned += 1
                for (token, reason) in Self.forbidden where text.contains(token) {
                    XCTFail("\(target)/\(file.lastPathComponent) uses \(token): \(reason)")
                }
            }
        }
        XCTAssertGreaterThan(scanned, 10)
    }
}
