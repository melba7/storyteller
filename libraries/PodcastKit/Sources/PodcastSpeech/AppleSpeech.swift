// LOFI-FORK: Apple's SpeechAnalyzer as a PieceRecogniser (see FORK.md).
//
// Written from Apple's documented iOS 26 / macOS 26 API (WWDC25, "Bring advanced speech-to-text
// to your app with SpeechAnalyzer") and compiled only in Fork CI and on a Mac, never on Linux:
// everything is behind `canImport(Speech)` and Swift 6.2 (Xcode 26), so older toolchains and
// Linux see an empty module, and `AppleSpeech.makeRecogniser()` answers nil there.
import Foundation
import PodcastTranscripts

#if canImport(Speech) && compiler(>=6.2)
  import AVFoundation
  import CoreMedia
  import Speech

  @available(iOS 26.0, macOS 26.0, *)
  public struct AppleRecogniser: PieceRecogniser {
    public let name = "SpeechTranscriber"
    /// Bumped when what this file does with Apple's results changes.
    public let version = "1"
    public var osVersion: String { ProcessInfo.processInfo.operatingSystemVersionString }

    public init() {}

    /// The transcriber for a locale, asking for the time of each word.
    private static func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
      SpeechTranscriber(
        locale: locale, transcriptionOptions: [], reportingOptions: [],
        attributeOptions: [.audioTimeRange])
    }

    public func prepare(locale identifier: String) async throws -> String {
      guard SpeechTranscriber.isAvailable else {
        throw TranscriptError.notSupported("Speech recognition is not available on this device")
      }
      guard
        let supported = await SpeechTranscriber.supportedLocale(
          equivalentTo: Locale(identifier: identifier))
      else { throw TranscriptError.notSupported("Language not supported") }
      let transcriber = Self.makeTranscriber(supported)
      do {
        // The first time for a language, iOS downloads its speech model.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
          try await request.downloadAndInstall()
        }
      } catch {
        throw TranscriptError.failed("The speech model could not be downloaded")
      }
      return supported.identifier(.bcp47)
    }

    public func duration(of file: URL) throws -> Double {
      let audio = try AVAudioFile(forReading: file)
      return Double(audio.length) / audio.processingFormat.sampleRate
    }

    public func recognise(
      file: URL, locale identifier: String, from: Double, to: Double
    ) async throws -> [TranscriptWord] {
      let transcriber = Self.makeTranscriber(Locale(identifier: identifier))
      let analyzer = SpeechAnalyzer(modules: [transcriber])
      guard
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
      else { throw TranscriptError.failed("The speech recogniser has no audio format for this language") }

      // Results arrive timed from the start of what was fed in, so the piece's start is added.
      let collector = Task { () throws -> [TranscriptWord] in
        var words: [TranscriptWord] = []
        for try await result in transcriber.results {
          for run in result.text.runs {
            guard let range = run[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] else {
              continue
            }
            let text = String(result.text[run.range].characters)
              .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            words.append(
              TranscriptWord(
                text: text, start: from + range.start.seconds, end: from + range.end.seconds))
          }
        }
        return words
      }

      let (inputs, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
      do {
        try await analyzer.start(inputSequence: inputs)
        try Self.feed(file, from: from, to: to, as: format, into: continuation)
        continuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await collector.value
      } catch {
        continuation.finish()
        collector.cancel()
        await analyzer.cancelAndFinishNow()
        throw error
      }
    }

    /// Reads `from` to `to` seconds of the file, from its frame position, and yields the audio
    /// in the format the analyzer wants.
    private static func feed(
      _ file: URL, from: Double, to: Double, as target: AVAudioFormat,
      into continuation: AsyncStream<AnalyzerInput>.Continuation
    ) throws {
      let audio = try AVAudioFile(forReading: file)
      let format = audio.processingFormat
      audio.framePosition = AVAudioFramePosition(from * format.sampleRate)
      var remaining = AVAudioFramePosition(to * format.sampleRate) - audio.framePosition
      let converter = format == target ? nil : AVAudioConverter(from: format, to: target)
      if converter == nil && format != target {
        throw TranscriptError.failed("This audio cannot be converted for the speech recogniser")
      }
      let chunk = AVAudioFrameCount(format.sampleRate)
      while remaining > 0 {
        let count = AVAudioFrameCount(min(AVAudioFramePosition(chunk), remaining))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else {
          throw TranscriptError.failed("Not enough memory to read the audio")
        }
        try audio.read(into: buffer, frameCount: count)
        if buffer.frameLength == 0 { break }
        remaining -= AVAudioFramePosition(buffer.frameLength)
        continuation.yield(AnalyzerInput(buffer: try convert(buffer, with: converter, to: target)))
      }
    }

    private static func convert(
      _ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter?, to format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
      guard let converter else { return buffer }
      let ratio = format.sampleRate / buffer.format.sampleRate
      let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
      guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
        throw TranscriptError.failed("Not enough memory to convert the audio")
      }
      var supplied = false
      var failure: NSError?
      let status = converter.convert(to: output, error: &failure) { _, inputStatus in
        if supplied {
          inputStatus.pointee = .noDataNow
          return nil
        }
        supplied = true
        inputStatus.pointee = .haveData
        return buffer
      }
      if status == .error {
        throw TranscriptError.failed("The audio could not be converted: \(failure?.localizedDescription ?? "unknown")")
      }
      return output
    }
  }
#endif

public enum AppleSpeech {
  /// What a row says on an iPhone that is too old for SpeechTranscriber.
  public static let needsNewerSystem = "Needs iOS 26"

  /// The Apple recogniser, or nil when this system or build has no SpeechAnalyzer.
  public static func makeRecogniser() -> PieceRecogniser? {
    #if canImport(Speech) && compiler(>=6.2)
      if #available(iOS 26.0, macOS 26.0, *) { return AppleRecogniser() }
    #endif
    return nil
  }
}
