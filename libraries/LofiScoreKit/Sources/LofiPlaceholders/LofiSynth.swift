import Foundation
import LofiDirector

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

/// A small, deterministic lofi synthesiser: electric piano chords, sine bass, drums made
/// from noise and sweeps, an occasional melody, tape wobble, vinyl crackle and a warm
/// low-pass. Pure Swift, so it runs anywhere the tests run.
public enum LofiSynth {
    /// Renders `recipe` at its natural level (not loudness-normalised).
    public static func render(_ recipe: PlaceholderRecipe, sampleRate: Double = 44_100) -> StereoBuffer {
        var renderer = Renderer(recipe: recipe, sampleRate: sampleRate)
        renderer.renderAll()
        return renderer.output
    }
}

private struct Renderer {
    let recipe: PlaceholderRecipe
    let sampleRate: Double
    let beat: Double
    let frames: Int
    var output: StereoBuffer
    var random: SplitMix64
    /// Pitch factor per frame, for tape wobble.
    let wobble: [Float]

    init(recipe: PlaceholderRecipe, sampleRate: Double) {
        self.recipe = recipe
        self.sampleRate = sampleRate
        beat = 60 / recipe.bpm
        frames = Int((recipe.duration * sampleRate).rounded())
        output = StereoBuffer(frames: frames, sampleRate: sampleRate)
        random = SplitMix64(seed: recipe.seed)
        let depth = recipe.wobble / 1200
        var table = [Float](repeating: 1, count: frames)
        for frame in 0..<frames {
            let t = Double(frame) / sampleRate
            let cents = depth * (sin(2 * .pi * 0.37 * t) + 0.35 * sin(2 * .pi * 1.13 * t + 1))
            table[frame] = Float(pow(2, cents))
        }
        wobble = table
    }

    mutating func renderAll() {
        renderChords()
        renderBass()
        renderDrums()
        renderMelody()
        renderTexture()
        finish()
    }

    // MARK: - Time

    /// Seconds at `position` beats from the start, with swing on off-beat eighths.
    func time(atBeat position: Double) -> Double {
        let whole = position.rounded(.down)
        let fraction = position - whole
        var shifted = fraction
        if abs(fraction - 0.5) < 1e-9 {
            shifted = 0.5 + recipe.swing * 0.5
        } else if abs(fraction - 0.25) < 1e-9 || abs(fraction - 0.75) < 1e-9 {
            // Sixteenths swing a little less.
            shifted = fraction + recipe.swing * 0.12
        }
        return (whole + shifted) * beat
    }

    func midiFrequency(_ note: Int) -> Double {
        440 * pow(2, Double(note - 69) / 12)
    }

    // MARK: - Voices

    struct Partial {
        var ratio: Double
        var gain: Double
        var decay: Double
    }

    /// A pitched note with its own partials, an attack, an exponential decay and a release.
    mutating func addTone(
        start: Double, length: Double, frequency: Double, amplitude: Double, pan: Double,
        partials: [Partial], attack: Double, decay: Double, release: Double,
        tremolo: Double = 0, vibrato: Double = 0
    ) {
        let first = max(0, Int(start * sampleRate))
        let last = min(frames, Int((start + length + release) * sampleRate))
        guard first < last else { return }
        let gains = panGains(pan)
        var phase = 0.0
        let step = 2 * Double.pi * frequency / sampleRate
        for frame in first..<last {
            let t = Double(frame - first) / sampleRate
            var envelope = min(1, t / attack) * exp(-t / decay)
            if t > length {
                envelope *= max(0, 1 - (t - length) / release)
            }
            if tremolo > 0 {
                envelope *= 1 - tremolo * 0.5 * (1 + sin(2 * .pi * 4.7 * t))
            }
            var pitch = Double(wobble[frame])
            if vibrato > 0 {
                pitch *= 1 + vibrato * sin(2 * .pi * 5.2 * t) * min(1, t / 0.3)
            }
            phase += step * pitch
            var sample = 0.0
            for partial in partials {
                sample += partial.gain * sin(phase * partial.ratio) * exp(-t / partial.decay)
            }
            let value = sample * envelope * amplitude
            output.left[frame] += Float(value * gains.left)
            output.right[frame] += Float(value * gains.right)
        }
    }

    /// Equal-power pan; centre is unity in both channels.
    func panGains(_ pan: Double) -> (left: Double, right: Double) {
        let angle = (min(1, max(-1, pan)) + 1) / 2 * .pi / 2
        return (cos(angle) * 2.0.squareRoot(), sin(angle) * 2.0.squareRoot())
    }

    // MARK: - Parts

    /// Electric-piano chords, one per bar, voiced around middle C.
    mutating func renderChords() {
        let piano = [
            Partial(ratio: 1, gain: 1, decay: 3.5),
            Partial(ratio: 2, gain: 0.32, decay: 1.2),
            Partial(ratio: 3, gain: 0.1, decay: 0.6),
            Partial(ratio: 7.1, gain: 0.05, decay: 0.08),
        ]
        let barBeats = 4.0
        for bar in 0..<recipe.bars {
            let chord = recipe.progression[bar % recipe.progression.count]
            let notes = voicing(of: chord)
            var hits: [(beat: Double, length: Double, level: Double)] = [(0, 3.9, 1)]
            if recipe.chordStabs {
                hits = [(0, 1.4, 1), (1.5, 2.4, 0.7)]
            }
            for hit in hits {
                let start = time(atBeat: Double(bar) * barBeats + hit.beat)
                for (index, note) in notes.enumerated() {
                    let strum = Double(index) * 0.018 + random.nextUnit() * 0.006
                    let pan = (Double(index) / Double(max(1, notes.count - 1)) - 0.5) * 0.5
                    addTone(
                        start: start + strum,
                        length: hit.length * beat,
                        frequency: midiFrequency(note) * (1 + (random.nextUnit() - 0.5) * 0.002),
                        amplitude: 0.16 * hit.level * (0.85 + random.nextUnit() * 0.3),
                        pan: pan,
                        partials: piano,
                        attack: 0.012,
                        decay: 2.6,
                        release: 0.25,
                        tremolo: 0.12
                    )
                }
            }
        }
    }

    /// The chord's notes, with its root in the octave from F3 to E4.
    func voicing(of chord: Chord) -> [Int] {
        var root = recipe.tonic + chord.degree
        while root < 53 { root += 12 }
        while root > 64 { root -= 12 }
        return chord.intervals.map { root + $0 }
    }

    mutating func renderBass() {
        guard recipe.bass != .none else { return }
        let partials = [Partial(ratio: 1, gain: 1, decay: 4), Partial(ratio: 2, gain: 0.18, decay: 0.5)]
        for bar in 0..<recipe.bars {
            let chord = recipe.progression[bar % recipe.progression.count]
            var root = recipe.tonic + chord.degree
            while root < 33 { root += 12 }
            while root > 44 { root -= 12 }
            let fifth = root + 7
            let pattern: [(beat: Double, length: Double, note: Int)]
            switch recipe.bass {
            case .none: pattern = []
            case .whole: pattern = [(0, 3.6, root)]
            case .halves: pattern = [(0, 1.8, root), (2, 1.8, root)]
            case .syncopated: pattern = [(0, 1.2, root), (1.5, 0.9, root), (3, 0.5, fifth), (3.5, 0.45, root + 12)]
            case .eighths: pattern = (0..<8).map { (Double($0) * 0.5, 0.4, root) }
            }
            for hit in pattern {
                addTone(
                    start: time(atBeat: Double(bar) * 4 + hit.beat),
                    length: hit.length * beat,
                    frequency: midiFrequency(hit.note),
                    amplitude: recipe.bass == .eighths ? 0.14 : 0.19,
                    pan: 0,
                    partials: partials,
                    attack: 0.015,
                    decay: 3,
                    release: 0.08
                )
            }
        }
    }

    mutating func renderDrums() {
        guard recipe.drums != .none else { return }
        for bar in 0..<recipe.bars {
            let base = Double(bar) * 4
            let kicks: [Double]
            let snares: [Double]
            switch recipe.drums {
            case .none: kicks = []; snares = []
            case .soft: kicks = [0, 2.5]; snares = [1, 3]
            case .boomBap: kicks = bar % 2 == 0 ? [0, 1.5, 2.5] : [0, 1.75, 2.5]; snares = [1, 3]
            case .driving: kicks = [0, 0.75, 1.5, 2, 2.75]; snares = [1, 3]
            case .halfTime: kicks = bar % 2 == 0 ? [0, 0.75] : [0, 2.5]; snares = [2]
            }
            let soft = recipe.drums == .soft
            for position in kicks {
                addKick(at: time(atBeat: base + position), level: soft ? 0.3 : 0.48)
            }
            for position in snares {
                if soft {
                    addRim(at: time(atBeat: base + position), level: 0.18)
                } else {
                    addSnare(at: time(atBeat: base + position), level: recipe.drums == .halfTime ? 0.32 : 0.28)
                }
            }
            if recipe.hats > 0 {
                let step = recipe.drums == .driving ? 0.25 : 0.5
                var position = 0.0
                while position < 4 - 1e-9 {
                    if random.nextUnit() < recipe.hats {
                        let accent = position.truncatingRemainder(dividingBy: 1) == 0 ? 1.0 : 0.65
                        let open = recipe.drums != .driving && random.nextUnit() < 0.06
                        addHat(at: time(atBeat: base + position), level: 0.11 * accent, open: open)
                    }
                    position += step
                }
            }
        }
    }

    mutating func addKick(at start: Double, level: Double) {
        let first = Int(start * sampleRate)
        let last = min(frames, first + Int(0.5 * sampleRate))
        guard first < last else { return }
        var phase = 0.0
        for frame in first..<last {
            let t = Double(frame - first) / sampleRate
            let frequency = 46 + 74 * exp(-t / 0.035)
            phase += 2 * .pi * frequency / sampleRate
            var value = sin(phase) * exp(-t / 0.2)
            if t < 0.003 {
                value += (random.nextUnit() - 0.5) * 0.4 * (1 - t / 0.003)
            }
            let sample = Float(tanh(1.4 * value) * level)
            output.left[frame] += sample
            output.right[frame] += sample
        }
    }

    mutating func addSnare(at start: Double, level: Double) {
        let first = Int(start * sampleRate)
        let last = min(frames, first + Int(0.35 * sampleRate))
        guard first < last else { return }
        var low = 0.0
        var previous = 0.0
        var high = 0.0
        let lowCoefficient = 1 - exp(-2 * .pi * 5000 / sampleRate)
        let highCoefficient = exp(-2 * .pi * 900 / sampleRate)
        for frame in first..<last {
            let t = Double(frame - first) / sampleRate
            let noise = random.nextUnit() * 2 - 1
            low += lowCoefficient * (noise - low)
            high = highCoefficient * (high + low - previous)
            previous = low
            let body = sin(2 * .pi * 185 * t) * exp(-t / 0.035) * 0.6
            let value = (high * exp(-t / 0.1) + body) * level
            output.left[frame] += Float(value * 0.95)
            output.right[frame] += Float(value * 1.05)
        }
    }

    mutating func addRim(at start: Double, level: Double) {
        let first = Int(start * sampleRate)
        let last = min(frames, first + Int(0.08 * sampleRate))
        guard first < last else { return }
        for frame in first..<last {
            let t = Double(frame - first) / sampleRate
            let value = (sin(2 * .pi * 1650 * t) * 0.7 + (random.nextUnit() - 0.5) * 0.6) * exp(-t / 0.012) * level
            output.left[frame] += Float(value * 0.9)
            output.right[frame] += Float(value * 1.1)
        }
    }

    mutating func addHat(at start: Double, level: Double, open: Bool) {
        let first = Int(start * sampleRate)
        let length = open ? 0.35 : 0.08
        let last = min(frames, first + Int(length * sampleRate))
        guard first < last else { return }
        let gains = panGains(0.3)
        let coefficient = exp(-2 * .pi * 7000 / sampleRate)
        var high = 0.0
        var previous = 0.0
        for frame in first..<last {
            let t = Double(frame - first) / sampleRate
            let noise = random.nextUnit() * 2 - 1
            high = coefficient * (high + noise - previous)
            previous = noise
            let value = high * exp(-t / (open ? 0.12 : 0.022)) * level
            output.left[frame] += Float(value * gains.left)
            output.right[frame] += Float(value * gains.right)
        }
    }

    /// A sparse pentatonic melody above the chords.
    mutating func renderMelody() {
        guard recipe.melody > 0 else { return }
        let scale = recipe.minor ? [0, 3, 5, 7, 10] : [0, 2, 4, 7, 9]
        var tonic = recipe.tonic
        while tonic < 67 { tonic += 12 }
        while tonic > 78 { tonic -= 12 }
        let partials = [Partial(ratio: 1, gain: 1, decay: 2), Partial(ratio: 3, gain: 0.12, decay: 0.3)]
        var degree = 0
        // The first bars stay empty, like an intro.
        for bar in 2..<max(2, recipe.bars) {
            var position = 0.0
            while position < 4 - 1e-9 {
                if random.nextUnit() < recipe.melody * 0.35 {
                    degree = max(-2, min(7, degree + Int((random.nextUnit() * 5).rounded(.down)) - 2))
                    let octave = degree >= 0 ? degree / scale.count : -1
                    let index = ((degree % scale.count) + scale.count) % scale.count
                    let note = tonic + 12 * octave + scale[index]
                    let length = [0.5, 1, 1.5][Int(random.nextUnit() * 3)]
                    addTone(
                        start: time(atBeat: Double(bar) * 4 + position),
                        length: length * beat,
                        frequency: midiFrequency(note),
                        amplitude: 0.12,
                        pan: 0.15,
                        partials: partials,
                        attack: 0.02,
                        decay: 1.2,
                        release: 0.2,
                        vibrato: 0.003
                    )
                    position += length
                } else {
                    position += 0.5
                }
            }
        }
    }

    /// Vinyl crackle and hiss.
    mutating func renderTexture() {
        guard recipe.crackle > 0 else { return }
        let clicksPerSecond = 4 + 14 * recipe.crackle
        let probability = clicksPerSecond / sampleRate
        let hiss = 0.004 * recipe.crackle
        var hissLeft = 0.0
        var hissRight = 0.0
        let hissCoefficient = 1 - exp(-2 * .pi * 3500 / sampleRate)
        var frame = 0
        while frame < frames {
            hissLeft += hissCoefficient * ((random.nextUnit() * 2 - 1) - hissLeft)
            hissRight += hissCoefficient * ((random.nextUnit() * 2 - 1) - hissRight)
            output.left[frame] += Float(hissLeft * hiss)
            output.right[frame] += Float(hissRight * hiss)
            if random.nextUnit() < probability {
                let size = pow(random.nextUnit(), 3) * 0.22 * recipe.crackle
                let right = random.nextUnit() < 0.5
                let width = 1 + Int(random.nextUnit() * 4)
                for offset in 0..<width where frame + offset < frames {
                    let value = Float(size * exp(-Double(offset) / 1.5) * (offset % 2 == 0 ? 1 : -0.6))
                    if right {
                        output.right[frame + offset] += value
                        output.left[frame + offset] += value * 0.3
                    } else {
                        output.left[frame + offset] += value
                        output.right[frame + offset] += value * 0.3
                    }
                }
            }
            frame += 1
        }
    }

    /// Warm low-pass, gentle saturation, and short fades so the file starts and ends cleanly.
    mutating func finish() {
        // Two gentle one-pole stages: the first at the recipe's brightness, the second higher,
        // so the top end rolls off warmly without disappearing.
        let coefficient = 1 - exp(-2 * .pi * recipe.brightness / sampleRate)
        let upper = 1 - exp(-2 * .pi * min(recipe.brightness * 2.5, sampleRate * 0.45) / sampleRate)
        var stages = [0.0, 0.0, 0.0, 0.0]
        let fadeIn = Int(0.01 * sampleRate)
        let fadeOut = Int(0.6 * sampleRate)
        for frame in 0..<frames {
            stages[0] += coefficient * (Double(output.left[frame]) - stages[0])
            stages[1] += upper * (stages[0] - stages[1])
            stages[2] += coefficient * (Double(output.right[frame]) - stages[2])
            stages[3] += upper * (stages[2] - stages[3])
            var gain = 1.0
            if frame < fadeIn { gain = Double(frame) / Double(fadeIn) }
            if frame >= frames - fadeOut { gain = min(gain, Double(frames - frame) / Double(fadeOut)) }
            output.left[frame] = Float(tanh(stages[1] * 1.2) / 1.2 * gain)
            output.right[frame] = Float(tanh(stages[3] * 1.2) / 1.2 * gain)
        }
    }
}
