import Foundation

/// Stereo audio as two arrays of samples.
public struct StereoBuffer: Sendable, Hashable {
    public var left: [Float]
    public var right: [Float]
    public var sampleRate: Double

    public init(left: [Float], right: [Float], sampleRate: Double) {
        precondition(left.count == right.count, "channels must be the same length")
        self.left = left
        self.right = right
        self.sampleRate = sampleRate
    }

    public init(frames: Int, sampleRate: Double) {
        left = [Float](repeating: 0, count: frames)
        right = [Float](repeating: 0, count: frames)
        self.sampleRate = sampleRate
    }

    public var frames: Int { left.count }
    public var duration: TimeInterval { Double(frames) / sampleRate }

    public mutating func scale(by gain: Float) {
        for index in left.indices {
            left[index] *= gain
            right[index] *= gain
        }
    }

    /// The largest absolute sample value.
    public var samplePeak: Float {
        var peak: Float = 0
        for index in left.indices {
            peak = max(peak, abs(left[index]), abs(right[index]))
        }
        return peak
    }
}
