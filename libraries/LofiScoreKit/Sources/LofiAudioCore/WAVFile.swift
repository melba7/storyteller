import Foundation

/// Reads and writes 16-bit PCM stereo WAV files. AVAudioFile opens these on every Apple
/// platform, and they need nothing but Foundation to make.
public enum WAVFile {
    public enum ReadError: Error, Equatable {
        case notWAV
        case unsupportedFormat(String)
        case truncated
    }

    /// Encodes `buffer` as 16-bit little-endian PCM with triangular dither.
    public static func data(for buffer: StereoBuffer, ditherSeed: UInt64 = 1) -> Data {
        let frames = buffer.frames
        let sampleRate = UInt32(buffer.sampleRate.rounded())
        let channels: UInt16 = 2
        let bitsPerSample: UInt16 = 16
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(frames) * UInt32(blockAlign)

        var data = Data(capacity: 44 + Int(dataSize))
        data.append(contentsOf: Array("RIFF".utf8))
        data.appendLittleEndian(UInt32(36) + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))  // PCM
        data.appendLittleEndian(channels)
        data.appendLittleEndian(sampleRate)
        data.appendLittleEndian(sampleRate * UInt32(blockAlign))
        data.appendLittleEndian(blockAlign)
        data.appendLittleEndian(bitsPerSample)
        data.append(contentsOf: Array("data".utf8))
        data.appendLittleEndian(dataSize)

        var samples = [Int16](repeating: 0, count: frames * 2)
        var state = ditherSeed
        func ditherNoise() -> Float {
            // Two uniform values make triangular noise of ±1 LSB.
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let a = Float(state >> 40) / Float(1 << 24)
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let b = Float(state >> 40) / Float(1 << 24)
            return a - b
        }
        for frame in 0..<frames {
            samples[2 * frame] = quantize(buffer.left[frame], dither: ditherNoise()).littleEndian
            samples[2 * frame + 1] = quantize(buffer.right[frame], dither: ditherNoise()).littleEndian
        }
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }

    public static func write(_ buffer: StereoBuffer, to url: URL) throws {
        try data(for: buffer).write(to: url, options: .atomic)
    }

    /// Reads a 16-bit PCM WAV file with one or two channels.
    public static func read(_ data: Data) throws -> StereoBuffer {
        let bytes = [UInt8](data)
        guard bytes.count >= 12, String(decoding: bytes[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: bytes[8..<12], as: UTF8.self) == "WAVE"
        else { throw ReadError.notWAV }

        var offset = 12
        var channels = 0
        var sampleRate = 0.0
        var bits = 0
        while offset + 8 <= bytes.count {
            let id = String(decoding: bytes[offset..<offset + 4], as: UTF8.self)
            let size = Int(bytes.littleEndianUInt32(at: offset + 4))
            let body = offset + 8
            guard body + size <= bytes.count else { throw ReadError.truncated }
            if id == "fmt " {
                let format = bytes.littleEndianUInt16(at: body)
                channels = Int(bytes.littleEndianUInt16(at: body + 2))
                sampleRate = Double(bytes.littleEndianUInt32(at: body + 4))
                bits = Int(bytes.littleEndianUInt16(at: body + 14))
                guard format == 1, bits == 16, channels == 1 || channels == 2 else {
                    throw ReadError.unsupportedFormat("format \(format), \(bits) bits, \(channels) channels")
                }
            } else if id == "data" {
                guard channels > 0 else { throw ReadError.unsupportedFormat("data before fmt") }
                let frames = size / (2 * channels)
                var buffer = StereoBuffer(frames: frames, sampleRate: sampleRate)
                for frame in 0..<frames {
                    let base = body + frame * 2 * channels
                    let left = Float(Int16(bitPattern: bytes.littleEndianUInt16(at: base))) / 32768
                    let right = channels == 2
                        ? Float(Int16(bitPattern: bytes.littleEndianUInt16(at: base + 2))) / 32768
                        : left
                    buffer.left[frame] = left
                    buffer.right[frame] = right
                }
                return buffer
            }
            offset = body + size + (size % 2)
        }
        throw ReadError.truncated
    }

    private static func quantize(_ value: Float, dither: Float) -> Int16 {
        let scaled = value * 32767 + dither
        return Int16(max(-32768, min(32767, scaled.rounded())))
    }
}

extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}

extension Array where Element == UInt8 {
    func littleEndianUInt16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func littleEndianUInt32(at offset: Int) -> UInt32 {
        UInt32(self[offset]) | UInt32(self[offset + 1]) << 8 | UInt32(self[offset + 2]) << 16 | UInt32(self[offset + 3]) << 24
    }
}
