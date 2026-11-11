import Foundation

/// Loudness measurement after ITU-R BS.1770-4 / EBU R 128: K-weighting, 400 ms blocks with
/// 75% overlap, an absolute gate at −70 LUFS and a relative gate 10 LU below.
///
/// The filter coefficients are derived for any sample rate the same way libebur128 does,
/// so 44.1 kHz files measure the same as they would in other R 128 tools.
public enum Loudness {
    /// Integrated loudness in LUFS. Silence returns −infinity.
    public static func integrated(_ buffer: StereoBuffer) -> Double {
        integrated(channels: [buffer.left, buffer.right], sampleRate: buffer.sampleRate)
    }

    /// Integrated loudness of one or more channels (each weighted 1, as for left and right).
    public static func integrated(channels: [[Float]], sampleRate: Double) -> Double {
        guard let frames = channels.first?.count, frames > 0, sampleRate > 0 else { return -.infinity }
        // Running sums of the K-weighted signal's energy, one per channel.
        let sums = channels.map { channel -> [Double] in
            var filter = KWeighting(sampleRate: sampleRate)
            var running = [Double](repeating: 0, count: frames + 1)
            for index in 0..<frames {
                let y = filter.process(Double(channel[index]))
                running[index + 1] = running[index] + y * y
            }
            return running
        }

        let blockLength = Int((0.4 * sampleRate).rounded())
        let hop = Int((0.1 * sampleRate).rounded())
        var blockPowers: [Double] = []
        if frames < blockLength {
            blockPowers.append(sums.reduce(0) { $0 + $1[frames] / Double(frames) })
        } else {
            var start = 0
            while start + blockLength <= frames {
                let end = start + blockLength
                blockPowers.append(sums.reduce(0) { $0 + ($1[end] - $1[start]) / Double(blockLength) })
                start += hop
            }
        }

        func lufs(_ power: Double) -> Double {
            power > 0 ? -0.691 + 10 * log10(power) : -.infinity
        }

        let absolute = blockPowers.filter { lufs($0) > -70 }
        guard !absolute.isEmpty else { return -.infinity }
        let relativeGate = lufs(absolute.reduce(0, +) / Double(absolute.count)) - 10
        let gated = absolute.filter { lufs($0) > relativeGate }
        guard !gated.isEmpty else { return -.infinity }
        return lufs(gated.reduce(0, +) / Double(gated.count))
    }

    /// Peak level in dBFS, estimated between samples with 4x Catmull-Rom interpolation.
    /// Close to (and never below) the sample peak; within a fraction of a dB of a true-peak meter.
    public static func truePeak(_ buffer: StereoBuffer) -> Double {
        var peak: Float = 0
        for channel in [buffer.left, buffer.right] where channel.count >= 4 {
            for index in 1..<(channel.count - 2) {
                let p0 = channel[index - 1], p1 = channel[index], p2 = channel[index + 1], p3 = channel[index + 2]
                peak = max(peak, abs(p1))
                for step in 1...3 {
                    let t = Float(step) / 4
                    let value = 0.5 * (2 * p1 + (-p0 + p2) * t
                        + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                        + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t)
                    peak = max(peak, abs(value))
                }
            }
        }
        peak = max(peak, buffer.samplePeak)
        return peak > 0 ? 20 * log10(Double(peak)) : -.infinity
    }
}

/// The BS.1770 K-weighting filter: a high-shelf "head" filter followed by the RLB high-pass.
struct KWeighting {
    private var shelf: Biquad
    private var highPass: Biquad

    init(sampleRate: Double) {
        // Stage 1: high shelf, +4 dB above about 1.7 kHz.
        var f0 = 1681.974450955533
        let gain = 3.999843853973347
        var q = 0.7071752369554196
        var k = tan(.pi * f0 / sampleRate)
        let vh = pow(10, gain / 20)
        let vb = pow(vh, 0.4996667741545416)
        var a0 = 1 + k / q + k * k
        shelf = Biquad(
            b0: (vh + vb * k / q + k * k) / a0,
            b1: 2 * (k * k - vh) / a0,
            b2: (vh - vb * k / q + k * k) / a0,
            a1: 2 * (k * k - 1) / a0,
            a2: (1 - k / q + k * k) / a0
        )
        // Stage 2: the revised low-frequency B-curve high-pass, around 38 Hz.
        f0 = 38.13547087602444
        q = 0.5003270373238773
        k = tan(.pi * f0 / sampleRate)
        a0 = 1 + k / q + k * k
        highPass = Biquad(
            b0: 1,
            b1: -2,
            b2: 1,
            a1: 2 * (k * k - 1) / a0,
            a2: (1 - k / q + k * k) / a0
        )
    }

    mutating func process(_ x: Double) -> Double {
        highPass.process(shelf.process(x))
    }
}

/// A transposed direct form II biquad.
struct Biquad {
    let b0, b1, b2, a1, a2: Double
    private var z1 = 0.0
    private var z2 = 0.0

    init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}
