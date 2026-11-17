// LOFI-FORK: the podcast downloads' file identity (see FORK.md).
//
// A downloaded episode is known by the SHA-256 of its bytes. Apple's CryptoKit does the
// work where it exists; a small pure-Swift version does it elsewhere (Linux, where the
// tests run) and is checked against the same test vectors. Files are read in chunks, so
// an hour of audio is never held in memory.
import Foundation

#if canImport(CryptoKit)
  import CryptoKit
#endif

/// SHA-256 written out in Swift, fed bit by bit. It is the fallback where CryptoKit is
/// missing, and it is always built so a Mac's tests can compare it with CryptoKit.
public struct PureSHA256: Sendable {
  private static let k: [UInt32] = [
    0x428a_2f98, 0x7137_4491, 0xb5c0_fbcf, 0xe9b5_dba5, 0x3956_c25b, 0x59f1_11f1, 0x923f_82a4,
    0xab1c_5ed5, 0xd807_aa98, 0x1283_5b01, 0x2431_85be, 0x550c_7dc3, 0x72be_5d74, 0x80de_b1fe,
    0x9bdc_06a7, 0xc19b_f174, 0xe49b_69c1, 0xefbe_4786, 0x0fc1_9dc6, 0x240c_a1cc, 0x2de9_2c6f,
    0x4a74_84aa, 0x5cb0_a9dc, 0x76f9_88da, 0x983e_5152, 0xa831_c66d, 0xb003_27c8, 0xbf59_7fc7,
    0xc6e0_0bf3, 0xd5a7_9147, 0x06ca_6351, 0x1429_2967, 0x27b7_0a85, 0x2e1b_2138, 0x4d2c_6dfc,
    0x5338_0d13, 0x650a_7354, 0x766a_0abb, 0x81c2_c92e, 0x9272_2c85, 0xa2bf_e8a1, 0xa81a_664b,
    0xc24b_8b70, 0xc76c_51a3, 0xd192_e819, 0xd699_0624, 0xf40e_3585, 0x106a_a070, 0x19a4_c116,
    0x1e37_6c08, 0x2748_774c, 0x34b0_bcb5, 0x391c_0cb3, 0x4ed8_aa4a, 0x5b9c_ca4f, 0x682e_6ff3,
    0x748f_82ee, 0x78a5_636f, 0x84c8_7814, 0x8cc7_0208, 0x90be_fffa, 0xa450_6ceb, 0xbef9_a3f7,
    0xc671_78f2,
  ]

  private var state: [UInt32] = [
    0x6a09_e667, 0xbb67_ae85, 0x3c6e_f372, 0xa54f_f53a, 0x510e_527f, 0x9b05_688c, 0x1f83_d9ab,
    0x5be0_cd19,
  ]
  /// Bytes not yet making a whole 64-byte block.
  private var pending: [UInt8] = []
  private var length: UInt64 = 0

  public init() {}

  public mutating func update(data: Data) {
    length &+= UInt64(data.count)
    var offset = 0
    if !pending.isEmpty {
      let need = 64 - pending.count
      let take = min(need, data.count)
      pending.append(contentsOf: data.prefix(take))
      offset = take
      if pending.count == 64 {
        process(pending)
        pending.removeAll(keepingCapacity: true)
      }
    }
    while data.count - offset >= 64 {
      let start = data.startIndex + offset
      process(Array(data[start..<start + 64]))
      offset += 64
    }
    if offset < data.count {
      pending.append(contentsOf: data[(data.startIndex + offset)...])
    }
  }

  public mutating func finalize() -> [UInt8] {
    let bitLength = length &* 8
    var tail = pending
    tail.append(0x80)
    while tail.count % 64 != 56 { tail.append(0) }
    for shift in stride(from: 56, through: 0, by: -8) {
      tail.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
    }
    for start in stride(from: 0, to: tail.count, by: 64) {
      process(Array(tail[start..<start + 64]))
    }
    pending.removeAll()
    return state.flatMap { word in
      [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: word >> UInt32($0)) }
    }
  }

  private static func rotate(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }

  private mutating func process(_ block: [UInt8]) {
    var w = [UInt32](repeating: 0, count: 64)
    for i in 0..<16 {
      w[i] =
        UInt32(block[i * 4]) << 24 | UInt32(block[i * 4 + 1]) << 16
        | UInt32(block[i * 4 + 2]) << 8 | UInt32(block[i * 4 + 3])
    }
    for i in 16..<64 {
      let s0 = Self.rotate(w[i - 15], 7) ^ Self.rotate(w[i - 15], 18) ^ (w[i - 15] >> 3)
      let s1 = Self.rotate(w[i - 2], 17) ^ Self.rotate(w[i - 2], 19) ^ (w[i - 2] >> 10)
      w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
    }
    var (a, b, c, d, e, f, g, h) = (
      state[0], state[1], state[2], state[3], state[4], state[5], state[6], state[7]
    )
    for i in 0..<64 {
      let s1 = Self.rotate(e, 6) ^ Self.rotate(e, 11) ^ Self.rotate(e, 25)
      let choice = (e & f) ^ (~e & g)
      let t1 = h &+ s1 &+ choice &+ Self.k[i] &+ w[i]
      let s0 = Self.rotate(a, 2) ^ Self.rotate(a, 13) ^ Self.rotate(a, 22)
      let majority = (a & b) ^ (a & c) ^ (b & c)
      let t2 = s0 &+ majority
      h = g
      g = f
      f = e
      e = d &+ t1
      d = c
      c = b
      b = a
      a = t1 &+ t2
    }
    state[0] &+= a
    state[1] &+= b
    state[2] &+= c
    state[3] &+= d
    state[4] &+= e
    state[5] &+= f
    state[6] &+= g
    state[7] &+= h
  }
}

/// SHA-256 fed in pieces: CryptoKit's where it exists, otherwise `PureSHA256`.
public struct Sha256Stream: Sendable {
  #if canImport(CryptoKit)
    private var inner = SHA256()
  #else
    private var inner = PureSHA256()
  #endif

  public init() {}

  public mutating func update(_ data: Data) { inner.update(data: data) }

  /// The hash as 64 lowercase hex digits.
  public mutating func finish() -> String { Sha256Stream.hex(inner.finalize()) }

  public static func hex(_ bytes: some Sequence<UInt8>) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
  }

  public static func hash(of data: Data) -> String {
    var stream = Sha256Stream()
    stream.update(data)
    return stream.finish()
  }
}

public enum FileHash {
  /// Reads a megabyte at a time.
  public static let defaultChunkSize = 1 << 20

  /// The SHA-256 of a file's bytes, read in chunks.
  public static func sha256(of url: URL, chunkSize: Int = defaultChunkSize) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var stream = Sha256Stream()
    while true {
      let done: Bool = try pooled {
        guard let chunk = try handle.read(upToCount: max(1, chunkSize)), !chunk.isEmpty else {
          return true
        }
        stream.update(chunk)
        return false
      }
      if done { break }
    }
    return stream.finish()
  }

  /// Frees the chunk read on each pass at once on Apple's systems.
  private static func pooled<T>(_ body: () throws -> T) rethrows -> T {
    #if canImport(ObjectiveC)
      return try autoreleasepool(invoking: body)
    #else
      return try body()
    #endif
  }
}
