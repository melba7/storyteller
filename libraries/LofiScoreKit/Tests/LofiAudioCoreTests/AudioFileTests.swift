import Foundation
import XCTest
@testable import LofiAudioCore

final class LoudnessTests: XCTestCase {
    private func sine(frequency: Double, amplitude: Float, seconds: Double, sampleRate: Double) -> [Float] {
        (0..<Int(seconds * sampleRate)).map { Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) * amplitude }
    }

    func testFullScaleSineInBothChannelsIsZeroLUFS() {
        // BS.1770: a 0 dBFS 1 kHz sine in left and right measures 0 LKFS.
        for rate in [44_100.0, 48_000.0] {
            let tone = sine(frequency: 997, amplitude: 1, seconds: 3, sampleRate: rate)
            let measured = Loudness.integrated(channels: [tone, tone], sampleRate: rate)
            XCTAssertEqual(measured, 0, accuracy: 0.05, "at \(rate) Hz")
        }
    }

    func testOneChannelIsThreeDecibelsQuieter() {
        let rate = 48_000.0
        let tone = sine(frequency: 997, amplitude: 1, seconds: 3, sampleRate: rate)
        let silence = [Float](repeating: 0, count: tone.count)
        XCTAssertEqual(Loudness.integrated(channels: [tone, silence], sampleRate: rate), -3.01, accuracy: 0.05)
    }

    func testLevelScalesInDecibels() {
        let rate = 48_000.0
        let tone = sine(frequency: 997, amplitude: Float(Gain.linear(fromDB: -20)), seconds: 3, sampleRate: rate)
        XCTAssertEqual(Loudness.integrated(channels: [tone, tone], sampleRate: rate), -20, accuracy: 0.05)
    }

    func testGatingIgnoresSilence() {
        let rate = 48_000.0
        let tone = sine(frequency: 997, amplitude: Float(Gain.linear(fromDB: -23)), seconds: 4, sampleRate: rate)
        let padded = tone + [Float](repeating: 0, count: Int(8 * rate))
        // The 37 blocks inside the tone count fully; the three blocks straddling its end hold
        // 75%, 50% and 25% of it and pass the gates too. The 77 silent blocks are gated out.
        let expected = -23 + 10 * log10((37 + 0.75 + 0.5 + 0.25) / 40)
        XCTAssertEqual(Loudness.integrated(channels: [padded, padded], sampleRate: rate), expected, accuracy: 0.02)
        let silence = [Float](repeating: 0, count: 48_000)
        XCTAssertEqual(Loudness.integrated(channels: [silence, silence], sampleRate: rate), -.infinity)
    }

    func testTruePeakCatchesPeaksBetweenSamples() {
        // A sine at a quarter of the sample rate, phase-shifted so no sample lands on a crest.
        let rate = 48_000.0
        let samples = (0..<4800).map { (i: Int) -> Float in
            let phase: Double = 2 * Double.pi * 12_000 * Double(i) / rate + Double.pi / 4
            return Float(sin(phase))
        }
        let buffer = StereoBuffer(left: samples, right: samples, sampleRate: rate)
        XCTAssertEqual(Double(buffer.samplePeak), sqrt(0.5), accuracy: 1e-3)
        XCTAssertGreaterThan(Loudness.truePeak(buffer), Gain.decibels(fromLinear: Double(buffer.samplePeak)) + 1)
    }
}

final class WAVFileTests: XCTestCase {
    func testRoundTrip() throws {
        let rate = 22_050.0
        let left = (0..<2000).map { Float(sin(Double($0) / 10)) * 0.5 }
        let right = (0..<2000).map { Float(cos(Double($0) / 7)) * 0.25 }
        let buffer = StereoBuffer(left: left, right: right, sampleRate: rate)
        let data = WAVFile.data(for: buffer)
        XCTAssertEqual(data.count, 44 + 2000 * 4)
        let decoded = try WAVFile.read(data)
        XCTAssertEqual(decoded.sampleRate, rate)
        XCTAssertEqual(decoded.frames, 2000)
        for index in stride(from: 0, to: 2000, by: 97) {
            XCTAssertEqual(decoded.left[index], left[index], accuracy: 1e-4)
            XCTAssertEqual(decoded.right[index], right[index], accuracy: 1e-4)
        }
    }

    func testClipsInsteadOfWrapping() throws {
        let buffer = StereoBuffer(left: [2, -2], right: [1, -1], sampleRate: 8000)
        let decoded = try WAVFile.read(WAVFile.data(for: buffer))
        XCTAssertGreaterThan(decoded.left[0], 0.99)
        XCTAssertLessThan(decoded.left[1], -0.99)
    }

    func testRejectsOtherFiles() {
        XCTAssertThrowsError(try WAVFile.read(Data("hello world, not a wav".utf8)))
    }
}
