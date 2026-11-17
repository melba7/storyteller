import XCTest

@testable import PodcastDownloads

final class Sha256Tests: XCTestCase {
  private let empty = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  private let abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  /// The 56-byte test string from FIPS 180-2: it needs a second block just for the padding.
  private let twoBlocksText = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
  private let twoBlocks = "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
  /// One million "a".
  private let millionA = "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"

  private func pure(_ pieces: [Data]) -> String {
    var hasher = PureSHA256()
    for piece in pieces { hasher.update(data: piece) }
    return Sha256Stream.hex(hasher.finalize())
  }

  private func stream(_ pieces: [Data]) -> String {
    var hasher = Sha256Stream()
    for piece in pieces { hasher.update(piece) }
    return hasher.finish()
  }

  func testEmptyInput() {
    XCTAssertEqual(pure([]), empty)
    XCTAssertEqual(stream([]), empty)
  }

  func testAbc() {
    XCTAssertEqual(pure([Data("abc".utf8)]), abc)
    XCTAssertEqual(stream([Data("abc".utf8)]), abc)
    XCTAssertEqual(Sha256Stream.hash(of: Data("abc".utf8)), abc)
  }

  func testPaddingThatNeedsASecondBlock() {
    XCTAssertEqual(pure([Data(twoBlocksText.utf8)]), twoBlocks)
    XCTAssertEqual(stream([Data(twoBlocksText.utf8)]), twoBlocks)
  }

  func testAMillionAsInOddlySizedPieces() {
    let all = Data(repeating: UInt8(ascii: "a"), count: 1_000_000)
    var pieces: [Data] = []
    var offset = 0
    var size = 1
    while offset < all.count {
      let end = min(all.count, offset + size)
      pieces.append(all[offset..<end])
      offset = end
      size = size % 997 + 37
    }
    XCTAssertEqual(pure(pieces), millionA)
    XCTAssertEqual(stream(pieces), millionA)
    XCTAssertEqual(pure([all]), millionA)
  }

  func testTheSameInputInDifferentPiecesGivesTheSameHash() {
    let text = Data(twoBlocksText.utf8)
    let split = [text.prefix(10), text.dropFirst(10).prefix(60), text.dropFirst(70)].map { Data($0) }
    XCTAssertEqual(pure(split), twoBlocks)
  }

  func testAFileIsHashedInChunks() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("a.bin")
    let all = Data(repeating: UInt8(ascii: "a"), count: 1_000_000)
    try all.write(to: file)
    // Small chunks, so the file takes many reads and ends part-way through a block.
    XCTAssertEqual(try FileHash.sha256(of: file, chunkSize: 7001), millionA)
    XCTAssertEqual(try FileHash.sha256(of: file), millionA)
    try Data().write(to: file)
    XCTAssertEqual(try FileHash.sha256(of: file), empty)
  }

  func testAMissingFileThrows() {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    XCTAssertThrowsError(try FileHash.sha256(of: missing))
  }

  #if canImport(CryptoKit)
    func testThePureVersionAgreesWithCryptoKit() {
      let data = Data((0..<5000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
      XCTAssertEqual(pure([data]), stream([data]))
    }
  #endif
}
