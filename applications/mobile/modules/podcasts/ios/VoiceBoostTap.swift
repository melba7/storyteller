// LOFI-FORK: the Storyteller Lofi fork's podcasts module (see FORK.md).
//
// Voice boost on the one AVPlayer. An MTAudioProcessingTap on the player item's audio mix hands
// each buffer of decoded audio to PodcastPlayback's `VoiceBoost` (gain, a compressor and a
// limiter) before it plays. The sums are the pure `VoiceBoost`; this file only wires the tap.
//
// The tap's C callbacks cannot capture anything, so they find their `BoostContext` through the
// tap's storage pointer. The context is retained once when the tap is made (clientInfo) and
// released once in `finalize`, which is the only place it is released.

import AVFoundation
import AudioToolbox
import Foundation
import MediaToolbox
import PodcastPlayback

/// What one tap knows. Its callbacks run one at a time on the audio thread (prepare, then
/// process over and over, then unprepare), so nothing here needs a lock.
final class BoostContext {
  let parameters: BoostParameters
  /// One processor per channel, because each one remembers how loud its channel was.
  var processors: [VoiceBoost] = []
  /// Only Float32 audio with a buffer for each channel is changed; anything else passes through.
  var canProcess = false

  init(parameters: BoostParameters) { self.parameters = parameters }

  func prepare(_ format: AudioStreamBasicDescription) {
    let flags = format.mFormatFlags
    canProcess =
      format.mFormatID == kAudioFormatLinearPCM && flags & kAudioFormatFlagIsFloat != 0
      && flags & kAudioFormatFlagIsNonInterleaved != 0 && format.mBitsPerChannel == 32
    processors = canProcess
      ? (0..<Int(format.mChannelsPerFrame)).map { _ in
        VoiceBoost(parameters: parameters, sampleRate: format.mSampleRate)
      } : []
  }

  func unprepare() {
    processors = []
    canProcess = false
  }

  func process(_ buffers: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
    guard canProcess else { return }
    let list = UnsafeMutableAudioBufferListPointer(buffers)
    for (index, buffer) in list.enumerated() where index < processors.count {
      guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
      // A buffer holds one channel, so its length in samples is the frames, at most.
      let count = min(frames, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
      processors[index].process(UnsafeMutableBufferPointer(start: data, count: count))
    }
  }
}

private func context(of tap: MTAudioProcessingTap) -> BoostContext {
  Unmanaged<BoostContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
}

private let tapInit: MTAudioProcessingTapInitCallback = { tap, clientInfo, storageOut in
  // The context was retained when the callbacks were made; the tap now owns that one retain.
  storageOut.pointee = clientInfo
}

private let tapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
  Unmanaged<BoostContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private let tapPrepare: MTAudioProcessingTapPrepareCallback = { tap, _, format in
  context(of: tap).prepare(format.pointee)
}

private let tapUnprepare: MTAudioProcessingTapUnprepareCallback = { tap in
  context(of: tap).unprepare()
}

private let tapProcess: MTAudioProcessingTapProcessCallback = {
  tap, frames, _, buffers, framesOut, flagsOut in
  // Fills `buffers` with the audio as it is; then it is changed in place.
  let status = MTAudioProcessingTapGetSourceAudio(
    tap, frames, buffers, flagsOut, nil, framesOut)
  guard status == noErr else { return }
  context(of: tap).process(buffers, frames: Int(framesOut.pointee))
}

enum VoiceBoostTap {
  /// The audio mix that boosts `asset`'s first audio track, or nil when the strength is off,
  /// the asset has no audio track (a stream that has not loaded, or cannot be tapped) or the
  /// tap could not be made. Nil means the item plays as it is.
  static func audioMix(for asset: AVAsset, strength: BoostStrength) async -> AVAudioMix? {
    guard let parameters = strength.parameters else { return nil }
    guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
      let tap = makeTap(parameters)
    else { return nil }
    let input = AVMutableAudioMixInputParameters(track: track)
    input.audioTapProcessor = tap
    let mix = AVMutableAudioMix()
    mix.inputParameters = [input]
    return mix
  }

  private static func makeTap(_ parameters: BoostParameters) -> MTAudioProcessingTap? {
    let retained = Unmanaged.passRetained(BoostContext(parameters: parameters))
    var callbacks = MTAudioProcessingTapCallbacks(
      version: kMTAudioProcessingTapCallbacksVersion_0, clientInfo: retained.toOpaque(),
      init: tapInit, finalize: tapFinalize, prepare: tapPrepare, unprepare: tapUnprepare,
      process: tapProcess)
    // The SDK hands the tap back as a managed object (`MTAudioProcessingTap?`), not Unmanaged.
    var tap: MTAudioProcessingTap?
    let status = MTAudioProcessingTapCreate(
      kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
    guard status == noErr, let tap else {
      // No tap was made, so nothing will call finalize: give the context back here.
      retained.release()
      return nil
    }
    return tap
  }
}
