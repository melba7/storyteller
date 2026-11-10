#if canImport(AVFoundation)
import AVFoundation
import Foundation
import LofiAudio
import LofiPlaceholders

/// Reading and writing audio files for the offline tools (`lofi-render`, `lofi-import`).
public enum AudioFileIO {
    public enum IOError: Error, CustomStringConvertible {
        case noBuffer
        case noConverter(String)
        case conversionFailed(String)

        public var description: String {
            switch self {
            case .noBuffer: return "Could not allocate an audio buffer"
            case let .noConverter(detail): return "No converter for \(detail)"
            case let .conversionFailed(detail): return "Conversion failed: \(detail)"
            }
        }
    }

    /// Decodes a whole file (any format AVFoundation reads, MP3 included) to float
    /// channels at the file's own sample rate.
    public static func read(_ url: URL) throws -> (channels: [[Float]], sampleRate: Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let chunk: AVAudioFrameCount = 65_536
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { throw IOError.noBuffer }
        var channels = [[Float]](repeating: [], count: Int(format.channelCount))
        for index in channels.indices {
            channels[index].reserveCapacity(Int(max(0, file.length)))
        }
        while file.framePosition < file.length {
            let remaining = AVAudioFrameCount(clamping: file.length - file.framePosition)
            try file.read(into: buffer, frameCount: min(chunk, remaining))
            let frames = Int(buffer.frameLength)
            guard frames > 0, let data = buffer.floatChannelData else { break }
            for index in channels.indices {
                channels[index].append(contentsOf: UnsafeBufferPointer(start: data[index], count: frames))
            }
        }
        return (channels, format.sampleRate)
    }

    /// Decodes a file to stereo (mono is copied to both sides; extra channels are dropped).
    public static func readStereo(_ url: URL) throws -> StereoBuffer {
        let (channels, sampleRate) = try read(url)
        guard let left = channels.first else { return StereoBuffer(frames: 0, sampleRate: sampleRate) }
        let right = channels.count > 1 ? channels[1] : left
        return StereoBuffer(left: left, right: right, sampleRate: sampleRate)
    }

    /// Decodes a file to mono at `sampleRate`.
    public static func readMono(_ url: URL, sampleRate: Double) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let input = file.processingFormat
        let frames = AVAudioFrameCount(clamping: max(0, file.length))
        guard frames > 0 else { return [] }
        guard let source = AVAudioPCMBuffer(pcmFormat: input, frameCapacity: frames) else { throw IOError.noBuffer }
        try file.read(into: source)

        if input.sampleRate == sampleRate, input.channelCount == 1, let data = source.floatChannelData {
            return Array(UnsafeBufferPointer(start: data[0], count: Int(source.frameLength)))
        }
        guard let output = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { throw IOError.noBuffer }
        guard let converter = AVAudioConverter(from: input, to: output) else {
            throw IOError.noConverter("\(input) to \(output)")
        }
        let capacity = AVAudioFrameCount(Double(source.frameLength) * sampleRate / input.sampleRate) + 8192
        guard let target = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { throw IOError.noBuffer }
        let feed = OneShotInput(source)
        var conversionError: NSError?
        let status = converter.convert(to: target, error: &conversionError) { _, inputStatus in
            feed.next(inputStatus)
        }
        if status == .error {
            throw IOError.conversionFailed(conversionError?.localizedDescription ?? "unknown error")
        }
        guard let data = target.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(target.frameLength)))
    }

    /// Writes `audio` as AAC in an `.m4a` file, replacing any file already there.
    public static func writeAAC(_ audio: StereoBuffer, to url: URL, bitRate: Int = 192_000) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: audio.sampleRate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: bitRate,
        ]
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        // The file is finished when it goes out of scope at the end of this function.
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let chunk = 32_768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(chunk)),
              let data = buffer.floatChannelData
        else { throw IOError.noBuffer }
        var start = 0
        while start < audio.frames {
            let count = min(chunk, audio.frames - start)
            buffer.frameLength = AVAudioFrameCount(count)
            audio.left.withUnsafeBufferPointer { data[0].update(from: $0.baseAddress! + start, count: count) }
            audio.right.withUnsafeBufferPointer { data[1].update(from: $0.baseAddress! + start, count: count) }
            try file.write(from: buffer)
            start += count
        }
    }

    /// `samples` without the near-silence at either end, keeping `margin` seconds.
    public static func trimSilence(_ samples: [Float], sampleRate: Double, threshold: Float = 0.003, margin: Double = 0.03) -> [Float] {
        guard let first = samples.firstIndex(where: { abs($0) > threshold }),
              let last = samples.lastIndex(where: { abs($0) > threshold })
        else { return [] }
        let pad = Int(margin * sampleRate)
        let start = max(0, first - pad)
        let end = min(samples.count, last + pad + 1)
        return Array(samples[start..<end])
    }
}

/// Hands a converter one buffer, then the end of the stream. The converter calls back on
/// the calling thread, so the unchecked `Sendable` is safe.
private final class OneShotInput: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private var delivered = false

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        if delivered {
            status.pointee = .endOfStream
            return nil
        }
        delivered = true
        status.pointee = .haveData
        return buffer
    }
}

/// Collects the music an offline ``AVAudioEngineBackend`` renders, step by step, while an
/// ``OfflineStoryRun`` drives the player.
public final class OfflineMusicRecorder {
    public let backend: AVAudioEngineBackend
    public let sampleRate: Double
    public private(set) var audio: StereoBuffer

    private let buffer: AVAudioPCMBuffer
    private let chunk: AVAudioFrameCount = 4096

    public init(sampleRate: Double = 44_100) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw AudioFileIO.IOError.noBuffer
        }
        backend = try AVAudioEngineBackend(offlineFormat: format, maximumFrameCount: chunk)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: backend.offlineFormat ?? format, frameCapacity: chunk) else {
            throw AudioFileIO.IOError.noBuffer
        }
        self.buffer = buffer
        self.sampleRate = sampleRate
        audio = StereoBuffer(frames: 0, sampleRate: sampleRate)
    }

    /// Renders until `time` seconds of music exist.
    public func render(until time: TimeInterval) throws {
        let target = Int((time * sampleRate).rounded())
        while audio.frames < target {
            let wanted = AVAudioFrameCount(min(Int(chunk), target - audio.frames))
            try backend.renderOffline(wanted, into: buffer)
            let frames = Int(buffer.frameLength)
            if frames > 0, let data = buffer.floatChannelData {
                let right = buffer.format.channelCount > 1 ? 1 : 0
                audio.left.append(contentsOf: UnsafeBufferPointer(start: data[0], count: frames))
                audio.right.append(contentsOf: UnsafeBufferPointer(start: data[right], count: frames))
            } else {
                audio.left.append(contentsOf: repeatElement(0, count: Int(wanted)))
                audio.right.append(contentsOf: repeatElement(0, count: Int(wanted)))
            }
        }
    }
}

#if os(macOS)
/// The Mac's text-to-speech voice, through `/usr/bin/say`.
public enum SystemVoice {
    public enum VoiceError: Error, CustomStringConvertible {
        case failed(status: Int32, message: String)

        public var description: String {
            switch self {
            case let .failed(status, message): return "say exited with \(status): \(message)"
            }
        }
    }

    /// Speaks `text` into an AIFF file at `url`.
    public static func render(_ text: String, to url: URL, voice: String? = nil, wordsPerMinute: Int? = nil) throws {
        let textFile = url.deletingPathExtension().appendingPathExtension("txt")
        try text.write(to: textFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: textFile) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        var arguments = ["-o", url.path, "-f", textFile.path]
        if let voice {
            arguments += ["-v", voice]
        }
        if let wordsPerMinute {
            arguments += ["-r", String(wordsPerMinute)]
        }
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw VoiceError.failed(status: process.terminationStatus, message: message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
#endif
#endif
