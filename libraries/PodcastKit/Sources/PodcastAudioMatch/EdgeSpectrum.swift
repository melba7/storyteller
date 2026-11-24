// LOFI-FORK: the 24-band spectrum of half a second of sound, for `EdgeSound` (see FORK.md).
// Foundation only, no Accelerate, so it runs on Linux and in the phone alike.
import Foundation

/// Turns half a second of mono samples into the level of 24 bands, in decibels. The bands are
/// spaced evenly on a log scale from 100 Hz up to 7.5 kHz (or the top of what the sample rate
/// holds). The spectrum is the average of up to 7 Hann-windowed frames spread over the half second,
/// so one loud click does not decide it.
struct EdgeSpectrum {
  /// The lowest and highest band edge, in hertz.
  static let lowest = 100.0
  static let highest = 7500.0
  static let frames = 7
  /// The quietest level a band reports, in decibels.
  static let floor: Float = -120

  let size: Int
  /// The bins each band covers.
  let ranges: [Range<Int>]
  private let window: [Float]
  private let cosines: [Float]
  private let sines: [Float]
  private let reversed: [Int]
  private let scale: Float
  private var real: [Float]
  private var imaginary: [Float]
  private var power: [Float]

  /// The edges of the bands in hertz: 25 numbers for 24 bands.
  static func edges(sampleRate: Double) -> [Double] {
    let top = min(highest, sampleRate / 2 * 0.95)
    let bottom = min(lowest, top / 4)
    return (0...EdgeSound.bandCount).map {
      bottom * pow(top / bottom, Double($0) / Double(EdgeSound.bandCount))
    }
  }

  /// The frame is 1024 samples, or the biggest power of two a half second holds when it holds
  /// fewer.
  init(sampleRate: Double, blockSamples: Int) {
    var size = 1024
    while size > blockSamples, size > 16 { size /= 2 }
    self.size = size
    let binHertz = sampleRate / Double(size)
    ranges = Self.edges(sampleRate: sampleRate).adjacentPairs().map { low, high in
      let first = min(Int((low / binHertz).rounded(.up)), size / 2 - 1)
      return first..<min(max(Int((high / binHertz).rounded(.up)), first + 1), size / 2)
    }
    window = (0..<size).map { 0.5 - 0.5 * Float(cos(2 * Double.pi * Double($0) / Double(size))) }
    cosines = (0..<size / 2).map { Float(cos(2 * Double.pi * Double($0) / Double(size))) }
    sines = (0..<size / 2).map { Float(sin(2 * Double.pi * Double($0) / Double(size))) }
    let bits = size.trailingZeroBitCount
    reversed = (0..<size).map { index in
      (0..<bits).reduce(0) { $0 | ((index >> $1) & 1) << (bits - 1 - $1) }
    }
    // A sine of amplitude 1 gives about 0.25 in its bin, whatever the frame.
    let sum = window.reduce(0, +)
    scale = 1 / (sum * sum)
    real = [Float](repeating: 0, count: size)
    imaginary = [Float](repeating: 0, count: size)
    power = [Float](repeating: 0, count: size / 2)
  }

  /// The level of each band in decibels, for the samples of one half second.
  mutating func bands(of samples: [Float]) -> [Float] {
    for index in power.indices { power[index] = 0 }
    let hop = max(1, (samples.count - size) / (Self.frames - 1))
    var used: Float = 0
    var start = 0
    while used < Float(Self.frames), start + size <= samples.count {
      transform(samples, from: start)
      for bin in 0..<size / 2 {
        power[bin] += real[bin] * real[bin] + imaginary[bin] * imaginary[bin]
      }
      used += 1
      start += hop
    }
    guard used > 0 else { return [Float](repeating: Self.floor, count: ranges.count) }
    return ranges.map { range in
      var total: Float = 0
      for bin in range { total += power[bin] }
      let mean = total / Float(range.count) / used * scale
      return mean > 1e-12 ? 10 * log10(mean) : Self.floor
    }
  }

  /// The windowed frame at `start`, in place, as real and imaginary parts (radix 2).
  private mutating func transform(_ samples: [Float], from start: Int) {
    for index in 0..<size {
      real[reversed[index]] = samples[start + index] * window[index]
      imaginary[index] = 0
    }
    var length = 2
    while length <= size {
      let half = length / 2
      let step = size / length
      var block = 0
      while block < size {
        var twiddle = 0
        for index in block..<block + half {
          let (c, s) = (cosines[twiddle], sines[twiddle])
          let other = index + half
          let (re, im) = (
            real[other] * c + imaginary[other] * s, imaginary[other] * c - real[other] * s
          )
          real[other] = real[index] - re
          imaginary[other] = imaginary[index] - im
          real[index] += re
          imaginary[index] += im
          twiddle += step
        }
        block += length
      }
      length *= 2
    }
  }
}

extension Array {
  /// Each element with the one after it.
  fileprivate func adjacentPairs() -> [(Element, Element)] {
    zip(self, dropFirst()).map { ($0, $1) }
  }
}
