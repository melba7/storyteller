// LOFI-FORK: Apple's SpeechAnalyzer as a PieceRecogniser (see FORK.md).
//
// Written from Apple's documented iOS 26 / macOS 26 API (WWDC25, "Bring advanced speech-to-text
// to your app with SpeechAnalyzer") and compiled only in Fork CI and on a Mac, never on Linux:
// everything is behind `canImport(Speech)` and Swift 6.2 (Xcode 26), so older toolchains and
// Linux see an empty module, and `AppleSpeech.makeRecogniser()` answers nil there.
import Foundation
import PodcastTranscripts


/// Turns the start of an episode into words while the rest is still downloading. One analyzer
/// is made ready ahead of the audio, then fed in steps; every call gives all words so far.
public protocol HeadTranscribing: AnyObject, Sendable {
  /// Loads the model and gets the analyzer ready. Throws when the speech model is not on the
  /// phone yet (it is not downloaded here: the normal path does that) or the language is not
  /// supported.
  func prepare() async throws
  /// Feeds `from` to `to` seconds of `file` (the next piece after the last call: the audio is
  /// taken to be one run) and returns all the words that are final so far, timed from 0.
  func extend(file: URL, from: Double, to: Double) async throws -> [TranscriptWord]
  /// Lets go of the analyzer, so the full transcript can have it.
  func finish() async
}

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
    static func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
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
    static func feed(
      _ file: URL, from: Double, to: Double, as target: AVAudioFormat,
      into continuation: AsyncStream<AnalyzerInput>.Continuation, tolerant: Bool = false
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
        // A copy of a file that is still downloading may end inside what its header promises:
        // for it a read error is the end of the audio.
        do {
          try audio.read(into: buffer, frameCount: count)
        } catch where tolerant {
          break
        }
        if buffer.frameLength == 0 { break }
        remaining -= AVAudioFramePosition(buffer.frameLength)
        continuation.yield(AnalyzerInput(buffer: try convert(buffer, with: converter, to: target)))
      }
    }

    static func convert(
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
  @available(iOS 26.0, macOS 26.0, *)
  final class AppleHeadTranscriber: HeadTranscribing, @unchecked Sendable {
    private let locale: String
    private var analyzer: SpeechAnalyzer?
    private var format: AVAudioFormat?
    private var inputs: AsyncStream<AnalyzerInput>.Continuation?
    private var collector: Task<Void, Never>?
    private let lock = NSLock()
    private var words: [TranscriptWord] = []
    private var finalizedTo = 0.0
    private var failure: Error?

    init(locale: String) { self.locale = locale }

    func prepare() async throws {
      guard SpeechTranscriber.isAvailable,
        let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: locale))
      else { throw TranscriptError.notSupported("Language not supported") }
      let transcriber = AppleRecogniser.makeTranscriber(supported)
      if try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) != nil {
        throw TranscriptError.notSupported("The speech model is not on this phone yet")
      }
      guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
      else { throw TranscriptError.failed("The speech recogniser has no audio format") }
      // The model stays loaded for the process, so the next episode's head starts warm too.
      let analyzer = SpeechAnalyzer(
        modules: [transcriber],
        options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime))
      try await analyzer.prepareToAnalyze(in: format)
      let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
      try await analyzer.start(inputSequence: stream)
      self.analyzer = analyzer
      self.format = format
      inputs = continuation
      collector = Task { [weak self] in
        do {
          for try await result in transcriber.results {
            self?.take(result)
          }
        } catch {
          self?.lock.withLock { self?.failure = error }
        }
      }
    }

    private func take(_ result: SpeechTranscriber.Result) {
      var found: [TranscriptWord] = []
      for run in result.text.runs {
        guard let range = run[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] else { continue }
        let text = String(result.text[run.range].characters)
          .trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
          found.append(TranscriptWord(text: text, start: range.start.seconds, end: range.end.seconds))
        }
      }
      lock.withLock {
        words += found
        finalizedTo = max(finalizedTo, result.resultsFinalizationTime.seconds, result.range.end.seconds)
      }
    }

    func extend(file: URL, from: Double, to: Double) async throws -> [TranscriptWord] {
      guard let analyzer, let format, let inputs else {
        throw TranscriptError.failed("The head transcriber was not prepared")
      }
      try AppleRecogniser.feed(file, from: from, to: to, as: format, into: inputs, tolerant: true)
      try await analyzer.finalize(through: CMTime(seconds: to, preferredTimescale: 600))
      // The results reach the collector a moment after they are final.
      var waited = 0
      while waited < 40, lock.withLock({ finalizedTo < to - 1 && failure == nil }) {
        try await Task.sleep(nanoseconds: 25_000_000)
        waited += 1
      }
      return try lock.withLock {
        if let failure { throw failure }
        return words
      }
    }

    func finish() async {
      inputs?.finish()
      collector?.cancel()
      await analyzer?.cancelAndFinishNow()
      analyzer = nil
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

  /// A transcriber for the first minutes of a stream, or nil when this system has none.
  public static func makeHeadTranscriber(locale identifier: String) -> HeadTranscribing? {
    #if canImport(Speech) && compiler(>=6.2)
      if #available(iOS 26.0, macOS 26.0, *) { return AppleHeadTranscriber(locale: identifier) }
    #endif
    return nil
  }
}
