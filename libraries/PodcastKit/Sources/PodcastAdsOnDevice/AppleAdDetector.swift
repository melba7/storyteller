// LOFI-FORK: Apple's on-device model as an AdDetector (see FORK.md).
//
// Written from Apple's documented iOS 26 / macOS 26 API (WWDC25, "Meet the Foundation Models
// framework" and "Deep dive into the Foundation Models framework") and compiled only in Fork
// CI and on a Mac, never on Linux: everything is behind `canImport(FoundationModels)` and
// Swift 6.2 (Xcode 26), so older toolchains and Linux see an empty module, and
// `AppleAds.makeDetector()` answers nil there.
//
// The wording of the instructions is adapted from two MIT-licensed projects that find ads in
// podcast transcripts with a language model: MinusPod (github.com/ttlequals0/MinusPod, "What
// is not an ad", the platform-inserted ads, where an ad starts and ends) and Podly
// (github.com/jdrbc/podly_pure_podcasts, the guard against calling self-promotion an ad and
// the rule to prefer content when in doubt). Both are listed in FORK.md.
import Foundation
import PodcastAds

/// A detector that can load the model ahead of its one request, so the answer comes sooner.
public protocol PrewarmableAdDetector: AdDetector {
  /// Starts loading the model and the instructions now. The system may ignore it (in the
  /// background, or under load); the request still works.
  func prewarm()
}

/// What the model needs from this system, and what the app asks of it.
public enum AppleAds {
  /// A detector for one request, with its session made and asked to prewarm by `prewarm()`.
  /// Use it once: a session keeps what it has been asked. Nil when this system has no model.
  public static func makeWarmDetector() -> PrewarmableAdDetector? {
    #if canImport(FoundationModels) && compiler(>=6.2)
      if #available(iOS 26.0, macOS 26.0, *) { return AppleAdDetector(warm: true) }
    #endif
    return nil
  }

  /// The Apple detector, or nil when this system or build has no Foundation Models.
  public static func makeDetector() -> AdDetector? {
    #if canImport(FoundationModels) && compiler(>=6.2)
      if #available(iOS 26.0, macOS 26.0, *) { return AppleAdDetector() }
    #endif
    return nil
  }

  /// Why ads cannot be found now, or nil when they can.
  public static func unavailable() -> AdUnavailable? {
    #if canImport(FoundationModels) && compiler(>=6.2)
      if #available(iOS 26.0, macOS 26.0, *) { return AppleAdDetector.availability() }
    #endif
    return .systemTooOld
  }
}

#if canImport(FoundationModels) && compiler(>=6.2)
  import FoundationModels

  @available(iOS 26.0, macOS 26.0, *)
  public struct AppleAdDetector: PrewarmableAdDetector {
    public let name = "apple-on-device"
    /// Bumped when the instructions or what this file does with answers changes.
    public let version = "1"
    /// The window is 4,096 tokens for the instructions, the lines and the answer together;
    /// about 2,500 are kept for the lines (about ten minutes of speech).
    public let tokenBudget = 2500

    /// What is kept free for the answer, in tokens.
    static let answerRoom = 600
    static let window = 4096

    /// The session made ahead for one request, when this detector was made to be warmed.
    private let warmSession: LanguageModelSession?

    public init() { warmSession = nil }

    fileprivate init(warm: Bool) {
      warmSession = warm ? LanguageModelSession(instructions: Self.instructions) : nil
    }

    public func prewarm() { warmSession?.prewarm() }

    /// Why the model cannot be used now, or nil when it can.
    public static func availability() -> AdUnavailable? {
      switch SystemLanguageModel.default.availability {
      case .available:
        return nil
      case .unavailable(let reason):
        switch reason {
        case .appleIntelligenceNotEnabled: return .appleIntelligenceOff
        case .modelNotReady: return .modelDownloading
        case .deviceNotEligible: return .deviceNotEligible
        @unknown default: return .other("Apple Intelligence is not available")
        }
      @unknown default:
        return .other("Apple Intelligence is not available")
      }
    }

    public func findAds(in piece: TranscriptPiece) async throws -> [AdRange] {
      if let reason = Self.availability() { throw AdDetectorError.unavailable(reason) }
      let prompt = "The lines of a podcast episode, each with its number in brackets:\n\n" + piece.prompt
      guard fits(prompt: prompt) else { throw AdDetectorError.tooLong }

      let session = warmSession ?? LanguageModelSession(instructions: Self.instructions)
      do {
        let response = try await session.respond(
          to: prompt, generating: AdAnswer.self, options: GenerationOptions(sampling: .greedy))
        return response.content.segments.compactMap { $0.range(inside: piece) }
      } catch let error as LanguageModelSession.GenerationError {
        switch error {
        case .exceededContextWindowSize: throw AdDetectorError.tooLong
        // The model refused these lines, or could not put its answer in the asked shape. The
        // answer is the same every time (the sampling is greedy), so asking again is no use:
        // the runner counts the piece as having no ad and reports it, so the app can show
        // that part was not read, and the rest of the episode still gets its ads.
        case .guardrailViolation, .refusal, .decodingFailure: throw AdDetectorError.refused
        case .unsupportedLanguageOrLocale:
          throw AdDetectorError.failed("The on-device model does not support this language")
        // The rest (busy, rate limited, no assets) pass, so the piece is asked again later. The
        // failure keeps the error's type name and case name for the ad finder's diary.
        default: throw AdModelFailure.classify(error)
        }
      } catch let error as CancellationError {
        throw error
      } catch {
        // Any other error of the model (iOS 27 brings new types) is read by its names, so a
        // refusal is no longer the end of the pass: the runner counts the piece as refused.
        throw AdModelFailure.classify(error)
      }
    }

    /// Whether the instructions, the lines and room for the answer fit the window, at about
    /// four characters a token. A piece that is still too long makes the model throw
    /// `exceededContextWindowSize`, and the runner halves it.
    private func fits(prompt: String) -> Bool {
      (Self.instructions.count + prompt.count) / 4 + Self.answerRoom <= Self.window
    }

    static let instructions = """
      You find advertising in a podcast episode's transcript. The transcript is given as numbered \
      lines. Answer with the runs of lines that are an ad or the hosts' own plug, and nothing else.

      An AD is a sponsor read by the hosts, a produced commercial, a spot the hosting platform or \
      network inserted ("Hosted on ...", "Acast powers ..."), or a promo for a different show. It \
      has promotional words you can point to: a sponsor's name, a web address, a promo code, a \
      product pitch or a call to action. Include the lead-in ("let's take a break", "this episode \
      is brought to you by") and keep going to the last web address, because sponsors repeat it. \
      The ad ends when the show comes back, not when the pitch ends.

      An OWN PLUG is the hosts promoting their own things: Patreon, merch, a newsletter, their \
      other shows, asking listeners to subscribe or leave a review.

      NOT an ad: a guest talking about their own work in an interview, brand names mentioned in \
      passing in real discussion, topic changes, jokes about sponsors without a pitch.

      Say how sure you are. SURE: you can point to specific promotional words. UNSURE: it looks \
      like an ad but the words are thin. GUESS: little more than a feeling. When in doubt, \
      prefer saying nothing, because a wrong ad costs the listener part of the show.

      The lines may start or end inside an ad: give the lines you can see. Use only the numbers \
      in brackets. Give no segment when there is no ad.
      """
  }
#endif
