import XCTest

@testable import PodcastAds

final class AdModelFailureTests: XCTestCase {
  private let modelType = "FoundationModels.LanguageModelError"

  func testARefusalByAnyNameIsRefused() {
    XCTAssertEqual(
      AdModelFailure.classify(
        typeName: modelType, caseName: "refusal", text: "The model refused to answer"),
      .refused)
    // Named by an older type, or with its text only, it is still a refusal.
    XCTAssertEqual(
      AdModelFailure.classify(
        typeName: "FoundationModels.LanguageModelSession.GenerationError", caseName: "refusal",
        text: "x"),
      .refused)
    XCTAssertEqual(
      AdModelFailure.classify(
        typeName: modelType, caseName: "somethingNew", text: "The model refused to answer"),
      .refused)
  }

  func testAGuardrailViolationIsRefused() {
    XCTAssertEqual(
      AdModelFailure.classify(typeName: modelType, caseName: "guardrailViolation", text: "x"),
      .refused)
    XCTAssertEqual(
      AdModelFailure.classify(
        typeName: modelType, caseName: "somethingNew",
        text: "The prompt may contain sensitive content"),
      .refused)
    XCTAssertEqual(
      AdModelFailure.classify(
        typeName: modelType, caseName: "somethingNew", text: "A guardrail was triggered"),
      .refused)
  }

  func testAnAnswerThatCannotBeReadIsRefusedLikeTheOlderErrorTypeDoes() {
    XCTAssertEqual(
      AdModelFailure.classify(typeName: modelType, caseName: "decodingFailure", text: "x"),
      .refused)
  }

  func testAPieceThatDoesNotFitIsTooLong() {
    XCTAssertEqual(
      AdModelFailure.classify(typeName: modelType, caseName: "contextSizeExceeded", text: "x"),
      .tooLong)
    XCTAssertEqual(
      AdModelFailure.classify(
        typeName: modelType, caseName: "exceededContextWindowSize", text: "x"),
      .tooLong)
  }

  func testRateLimitedAndTimeoutAreFailuresThatAreTriedAgain() {
    XCTAssertEqual(
      AdModelFailure.classify(
        typeName: modelType, caseName: "rateLimited", text: "Too many requests"),
      .failed("Too many requests"))
    XCTAssertEqual(
      AdModelFailure.classify(typeName: modelType, caseName: "timeout", text: "Timed out"),
      .failed("Timed out"))
    // A retry case is never turned into a refusal by a word in its text.
    XCTAssertEqual(
      AdModelFailure.classify(
        typeName: modelType, caseName: "rateLimited", text: "Too many sensitive requests"),
      .failed("Too many sensitive requests"))
  }

  func testAnUnknownCaseWithUnknownTextIsAFailureWithTheText() {
    XCTAssertEqual(
      AdModelFailure.classify(typeName: modelType, caseName: "somethingNew", text: "Something odd"),
      .failed("Something odd"))
  }

  func testAModelThatIsBusyOrNotDownloadedIsNotRefused() {
    for text in ["The model is busy", "The model assets are not downloaded yet", "Not ready"] {
      XCTAssertEqual(
        AdModelFailure.classify(typeName: modelType, caseName: "assetsUnavailable", text: text),
        .failed(text))
      XCTAssertEqual(
        AdModelFailure.classify(typeName: modelType, caseName: "somethingNew", text: text),
        .failed(text))
    }
  }

  func testWordsInTheTextOfAnotherKindOfErrorDoNotMakeItARefusal() {
    XCTAssertEqual(
      AdModelFailure.classify(
        typeName: "Foundation.URLError", caseName: "badServerResponse",
        text: "The file is sensitive"),
      .failed("The file is sensitive"))
  }

  func testTheUnsupportedLanguageKeepsItsPlainSentence() {
    XCTAssertEqual(
      AdModelFailure.classify(
        typeName: modelType, caseName: "unsupportedLanguageOrLocale", text: "x"),
      .failed("The on-device model does not support this language"))
  }

  func testAnErrorThatIsAlreadyOursComesBackUnchanged() {
    for error: AdDetectorError in [
      .tooLong, .refused, .failed("x"), .unavailable(.appleIntelligenceOff),
    ] {
      XCTAssertEqual(AdModelFailure.classify(error), error)
    }
  }

  private enum PlainModelError: Error { case refusal, timeout, odd }
  private enum PayloadModelError: Error { case refusal(String), contextSizeExceeded(Int) }

  func testTheNamesAreReadFromTheErrorItself() {
    XCTAssertEqual(AdModelFailure.classify(PlainModelError.refusal), .refused)
    XCTAssertEqual(AdModelFailure.classify(PayloadModelError.refusal("why")), .refused)
    XCTAssertEqual(AdModelFailure.classify(PayloadModelError.contextSizeExceeded(4096)), .tooLong)
    guard case .failed = AdModelFailure.classify(PlainModelError.timeout) else {
      return XCTFail("a timeout is a failure")
    }
    guard case .failed = AdModelFailure.classify(PlainModelError.odd) else {
      return XCTFail("an unknown case is a failure")
    }
  }

  func testAFailureMadeOfAnErrorKeepsItsNamesAtTheEndOfItsText() {
    guard case .failed(let text) = AdModelFailure.classify(DiaryFakeError.rateLimited("x")) else {
      return XCTFail("a rate limit is a failure")
    }
    let names = AdModelFailure.namesIn(text)
    XCTAssertEqual(names?.caseName, "rateLimited")
    XCTAssertEqual(names?.typeName, "PodcastAdsTests.DiaryFakeError")
    // Text that only looks like names gives none.
    XCTAssertNil(AdModelFailure.namesIn("Timed out"))
    XCTAssertNil(AdModelFailure.namesIn("Timed out [model error: some words]"))
    XCTAssertNil(AdModelFailure.namesIn("Timed out [model error: Module.Type two words]"))
    // The text that the rules decide on is not changed by them.
    XCTAssertEqual(
      AdModelFailure.classify(typeName: modelType, caseName: "timeout", text: "Timed out"),
      .failed("Timed out"))
  }

  func testTheNamesAreAvailableForTheDiary() {
    let names = AdModelFailure.names(of: PayloadModelError.refusal("why"))
    XCTAssertEqual(names.caseName, "refusal")
    XCTAssertTrue(names.typeName.hasSuffix("PayloadModelError"), names.typeName)
    XCTAssertEqual(AdModelFailure.names(of: PlainModelError.timeout).caseName, "timeout")
  }
}
