// LOFI-FORK: reads an MP3 file as mono sound for `podcast-teach edges` (see FORK.md). The decoder is
// Apple's, as in the app's silence trimming: AVAssetReader gives mono 16 kHz Float32, so the file is
// never held whole in memory. Empty where there is no AVFoundation (Linux), which says so by having no
// reader; the command then tells the owner to run it on the Mac.
import Foundation
import PodcastAudioMatch

#if canImport(AVFoundation)
  import AVFoundation
#endif

public enum MacEdgeReader {
  /// The sample rate the file is read at, in hertz.
  public static let sampleRate = 16000.0

  /// The reader of a Mac, or nil where there is none.
  public static func make() -> EdgeReader? {
    #if canImport(AVFoundation)
      return EdgeReader(sampleRate: sampleRate) { file, feed in try await read(file, feed) }
    #else
      return nil
    #endif
  }
}

#if canImport(AVFoundation)
  extension MacEdgeReader {
    struct Failure: Error, LocalizedError {
      var errorDescription: String?
    }

    /// Reads `file` to its end and gives its samples to `feed` as they are decoded. Throws when the
    /// file has no audio or cannot be read to its end.
    static func read(_ file: URL, _ feed: ([Float]) -> Void) async throws {
      let asset = AVURLAsset(url: file)
      guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
        throw Failure(errorDescription: "The file has no audio.")
      }
      let reader = try AVAssetReader(asset: asset)
      let output = AVAssetReaderTrackOutput(
        track: track,
        outputSettings: [
          AVFormatIDKey: kAudioFormatLinearPCM,
          AVLinearPCMBitDepthKey: 32,
          AVLinearPCMIsFloatKey: true,
          AVLinearPCMIsBigEndianKey: false,
          AVLinearPCMIsNonInterleaved: false,
          AVNumberOfChannelsKey: 1,
          AVSampleRateKey: sampleRate,
        ])
      guard reader.canAdd(output) else {
        throw Failure(errorDescription: "The audio can't be read.")
      }
      reader.add(output)
      try pump(reader, output, feed)
    }

    /// The decoding loop. It is not async: copying sample buffers is meant for a plain thread.
    private static func pump(
      _ reader: AVAssetReader, _ output: AVAssetReaderTrackOutput, _ feed: ([Float]) -> Void
    ) throws {
      guard reader.startReading() else {
        throw reader.error ?? Failure(errorDescription: "The audio can't be read.")
      }
      while let buffer = output.copyNextSampleBuffer() {
        guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
        let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
        guard count > 0 else { continue }
        var samples = [Float](repeating: 0, count: count)
        let status = samples.withUnsafeMutableBytes { bytes in
          CMBlockBufferCopyDataBytes(
            block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size,
            destination: bytes.baseAddress!)
        }
        guard status == kCMBlockBufferNoErr else {
          throw Failure(errorDescription: "The audio can't be read.")
        }
        feed(samples)
      }
      guard reader.status == .completed else {
        throw reader.error ?? Failure(errorDescription: "The audio stopped before its end.")
      }
    }
  }
#endif
