// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Reads a downloaded episode once and finds its silent gaps. The file is decoded to mono 16 kHz
// Float32 with AVAssetReader on a background queue, loudness is measured in 50 ms frames
// (PodcastPlayback's LoudnessMeter), and the gaps come from SilenceFinder. The result is saved
// as `<sha256>.silence.json` next to the audio (SilenceStore).

import AVFoundation
import Foundation
import PodcastPlayback

enum SilenceAnalyzer {
  static let sampleRate = 16000.0

  struct Failure: Error, LocalizedError {
    var errorDescription: String?
  }

  /// Reads `file` and saves its silence file. Throws when the file cannot be read to its end.
  static func analyze(file: URL, store: SilenceStore) async throws -> SilenceFile {
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
    guard reader.canAdd(output) else { throw Failure(errorDescription: "The audio can't be read.") }
    reader.add(output)
    let frames: [Float] = try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .utility).async {
        do { continuation.resume(returning: try measure(reader, output)) } catch {
          continuation.resume(throwing: error)
        }
      }
    }
    let result = SilenceFile(
      sha256: store.sha256, duration: Double(frames.count) * SilenceFinder.frameSeconds,
      gaps: SilenceFinder.gaps(loudness: frames))
    try store.save(result)
    return result
  }

  /// The loudness of each frame of the whole file. Runs on a background queue.
  private static func measure(_ reader: AVAssetReader, _ output: AVAssetReaderTrackOutput) throws
    -> [Float]
  {
    guard reader.startReading() else {
      throw reader.error ?? Failure(errorDescription: "The audio can't be read.")
    }
    var meter = LoudnessMeter(sampleRate: sampleRate)
    var scratch = [Float](repeating: 0, count: 16384)
    while let buffer = output.copyNextSampleBuffer() {
      guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
      let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
      if scratch.count < count { scratch = [Float](repeating: 0, count: count) }
      let status = scratch.withUnsafeMutableBytes { bytes in
        CMBlockBufferCopyDataBytes(
          block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size,
          destination: bytes.baseAddress!)
      }
      guard status == kCMBlockBufferNoErr else {
        throw Failure(errorDescription: "The audio can't be read.")
      }
      scratch.withUnsafeBufferPointer { meter.add(UnsafeBufferPointer(rebasing: $0[0..<count])) }
    }
    guard reader.status == .completed else {
      throw reader.error ?? Failure(errorDescription: "The audio stopped before its end.")
    }
    return meter.frames
  }
}
