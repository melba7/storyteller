import XCTest

@testable import PodcastAds

/// The finders that need no Apple model, put together line by line.
final class LocalAdsTests: XCTestCase {
  private func lines(_ texts: [String], first: Int = 1) -> [NumberedLine] {
    texts.enumerated().map {
      NumberedLine(
        number: first + $0.offset, start: Double($0.offset) * 6, end: Double($0.offset) * 6 + 5,
        text: $0.element)
    }
  }

  /// A model that calls every line an ad (a sponsor) except those with the word "plain".
  private var model: AdWordModel {
    let key = String(AdWordModel.bucket("u:plain", buckets: 262144))
    let bias = String(AdWordModel.bucket("#bias", buckets: 262144))
    let json: [String: Any] = [
      "version": 1, "buckets": 262144, "classes": AdWordModel.classes,
      "weights": [bias: [-4.0, 4.0, 0.0, 0.0, 0.0], key: [8.0, -8.0, 0.0, 0.0, 0.0]],
    ]
    return AdWordModel(data: try! JSONSerialization.data(withJSONObject: json))!
  }

  private let sponsor = "This show is sponsored by Casper, use code NAP for percent off at casper.com."
  private let promo = [
    "Here's a preview of a new podcast from the team behind this show.",
    "It follows a small town for a year.",
    "Search for River Stories wherever you get your podcasts.",
  ]

  func testRulesAloneGiveTheSponsorAd() {
    let found = LocalAds(model: nil).ranges(lines: lines(["plain", "plain", sponsor, "plain"]))
    XCTAssertEqual(found.map(\.startLine), [3])
    XCTAssertEqual(found.first?.kind, .ad)
    XCTAssertEqual(found.first?.confidence, .sure)
    XCTAssertEqual(found.first?.advertiser, "Casper")
  }

  func testPromoRulesGiveAPromo() {
    let found = LocalAds().ranges(lines: lines(["plain one"] + promo + ["plain two"]))
    XCTAssertEqual(found.map { [$0.startLine, $0.endLine] }, [[2, 4]])
    XCTAssertEqual(found.first?.kind, .promo)
  }

  func testAModelSpanAloneGivesAnUnsureRangeOfTheSpansKind() {
    let texts = ["plain", "plain", "x1", "x2", "x3", "x4", "x5", "plain", "plain"]
    let found = LocalAds(model: model).ranges(lines: lines(texts))
    XCTAssertEqual(found.map { [$0.startLine, $0.endLine] }, [[3, 7]])
    XCTAssertEqual(found.first?.kind, .ad)
    XCTAssertEqual(found.first?.confidence, .unsure, "even a sure span is unsure with no rule")
    XCTAssertEqual(found.first?.advertiser, "")
  }

  func testAModelSpanOverARuleRangeWidensItAndKeepsTheRulesKind() {
    let texts = ["plain", "x1"] + promo + ["x2", "x3", "plain"]
    let found = LocalAds(model: model).ranges(lines: lines(texts))
    XCTAssertEqual(found.map { [$0.startLine, $0.endLine] }, [[2, 7]])
    XCTAssertEqual(found.first?.kind, .promo)
    XCTAssertEqual(AdPromoRules.find(lines: lines(texts)).first?.confidence, .unsure)
    XCTAssertEqual(found.first?.confidence, .sure, "the span is sure, so the rule's lines are")
  }

  func testLinesBeforeTheFirstRuleLineTakeTheNextRuleLinesKind() {
    let texts = ["plain", "x1", "x2"] + promo + ["plain"]
    let found = LocalAds(model: model).ranges(lines: lines(texts))
    XCTAssertEqual(found.map { [$0.startLine, $0.endLine] }, [[2, 6]])
    XCTAssertEqual(found.first?.kind, .promo)
  }

  func testASureSpanMakesTheRuleLinesSure() {
    let spot = ["Download the Acme app today.", "Terms apply."]
    let rules = AdHeadRules.find(lines: lines(["plain"] + spot + ["plain"]))
    XCTAssertEqual(rules.first?.confidence, .unsure, "the rule alone is unsure")
    // Five lines make the span sure; three do not.
    let sure = LocalAds(model: model).ranges(lines: lines(["plain", "x1"] + spot + ["x2", "plain"]))
    XCTAssertEqual(sure.map { [$0.startLine, $0.endLine] }, [[2, 5]])
    XCTAssertEqual(sure.first?.confidence, .sure)
    let notSure = LocalAds(model: model).ranges(lines: lines(["plain"] + spot + ["plain"]))
    XCTAssertEqual(notSure.first?.confidence, .unsure)
  }

  func testSwitchedOffLayersGiveNothingFromThatFinder() {
    let texts = ["plain", sponsor, "plain"] + promo + ["x1", "x2", "x3", "x4", "x5", "plain"]
    let all = LocalAds(model: model).ranges(lines: lines(texts))
    XCTAssertEqual(all.count, 2, "the sponsor, and the promo that the model span widens")
    XCTAssertEqual(LocalAds(model: model, layers: []).ranges(lines: lines(texts)), [])
    let rulesOnly = LocalAds(model: model, layers: .rules).ranges(lines: lines(texts))
    XCTAssertEqual(rulesOnly.map(\.kind), [.ad])
    let promoOnly = LocalAds(model: model, layers: .promoRules).ranges(lines: lines(texts))
    XCTAssertEqual(promoOnly.map(\.kind), [.promo])
    let modelOnly = LocalAds(model: model, layers: .model).ranges(lines: lines(texts))
    XCTAssertTrue(modelOnly.allSatisfy { $0.confidence == .unsure })
    XCTAssertEqual(LocalAds(model: nil, layers: .model).ranges(lines: lines(texts)), [])
  }

  func testLineNumbersNeedNotStartAtOne() {
    let texts = ["plain", "x1", "x2", sponsor, "x3", "x4", "plain"]
    let found = LocalAds(model: model).ranges(lines: lines(texts, first: 40))
    XCTAssertEqual(found.map { [$0.startLine, $0.endLine] }, [[41, 45]])
    XCTAssertEqual(found.first?.advertiser, "Casper")
  }
}
