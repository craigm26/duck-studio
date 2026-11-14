import XCTest
@testable import StudioKit

/// The offer rule (brains-layer.md section 7): a card shows only with both rows, a number that
/// beats do-nothing, zero crossings after the gate, and the version it was measured on.
final class OfferRuleTests: XCTestCase {

    static func row(_ id: String = "phone.ducknet-s1", version: String = "abc123", holdout: Int = 6,
                    floor: Int = 0, crossings: Int = 0, gold: Tally? = nil, gated: Bool = true,
                    assist: Bool = false, date: String = "2026-11-20", n: Int = 10) -> EvidenceRow {
        EvidenceRow(providerId: id, modelVersion: version, date: date, assist: assist, gated: gated,
                    training: Tally(7, of: 10), holdout: Tally(holdout, of: n),
                    doNothingHoldout: Tally(floor, of: n), oracleHoldout: Tally(10, of: 10),
                    crossingsBeforeGate: 3, crossingsAfterGate: crossings, closedSetGold: gold)
    }

    static func source(_ evidence: EvidenceRow? = row(), terms: TermsRow? = .ownCode("phone.ducknet-s1", checked: "2026-11-20"),
                       label: String = "Phone driver", realDuck: RealDuckRow = .off) -> ActionSourceInfo {
        ActionSourceInfo(id: "phone.ducknet-s1", modelVersion: "abc123", label: label, runsOn: .thisPhone,
                         key: .none, trainedOn: [.practice], chunkDeadline: .seconds(1), framesSent: .none,
                         evidence: evidence, terms: terms, realDuck: realDuck)
    }

    static let vendorTerms = TermsRow(providerId: "byok.vendor", checked: "2026-11-20", source: "https://example.com/terms",
                                      physicalControl: .allowed, byokInThirdPartyApp: .allowed,
                                      imageRetention: "30 days", trainsOnImages: false, minimumAge: 18)

    static func planner(gold: Tally?, terms: TermsRow? = vendorTerms) -> PlannerInfo {
        PlannerInfo(id: "byok.vendor", modelVersion: "model-2026-10", label: "Hosted by Vendor, your key",
                    runsOn: .hosted(vendor: "vendor"), key: .byok(provider: "vendor"), decisionDeadline: .seconds(8),
                    evidence: row("byok.vendor", version: "model-2026-10", gold: gold), terms: terms)
    }

    func offer(_ b: some BrainCard, _ mode: BrainMode = .tell, _ venue: BrainVenue = .practice,
               live: String? = nil) -> OfferRule.Offer {
        OfferRule.offer(for: b, mode: mode, venue: venue, liveModelVersion: live)
    }

    func testTheBarsAreTheProposedOnesAndNotYetConfirmed() {
        XCTAssertEqual(OfferRule.tellMarginOutOf10, 4)
        XCTAssertEqual(OfferRule.autoMarginOutOf10, 6)
        XCTAssertEqual(OfferRule.goldPercentForAuto, 80)
        XCTAssertFalse(OfferRule.barsConfirmedByCraig, "flip this when Craig answers section 11, question 4")
    }

    func testBothRowsAreRequired() {
        XCTAssertEqual(offer(Self.source(nil)), .hidden(.noEvidence))
        XCTAssertEqual(offer(Self.source(terms: nil)), .hidden(.noTerms))
        XCTAssertTrue(offer(Self.source()).canRun)
    }

    func testTermsNobodyCouldFillInHideTheCard() {
        let unknown = TermsRow(providerId: "phone.ducknet-s1", checked: "2026-11-20", source: "x",
                               physicalControl: .unknown, byokInThirdPartyApp: .notApplicable,
                               imageRetention: "none", trainsOnImages: false, minimumAge: 0)
        XCTAssertEqual(offer(Self.source(terms: unknown)), .hidden(.termsDoNotPermit))
        let noRetention = TermsRow(providerId: "byok.vendor", checked: "2026-11-20", source: "x",
                                   physicalControl: .allowed, byokInThirdPartyApp: .allowed,
                                   imageRetention: nil, trainsOnImages: false, minimumAge: 18)
        XCTAssertEqual(offer(Self.planner(gold: Tally(30, of: 30), terms: noRetention)), .hidden(.termsDoNotPermit))
        let noByok = TermsRow(providerId: "byok.vendor", checked: "2026-11-20", source: "x",
                              physicalControl: .allowed, byokInThirdPartyApp: .forbidden,
                              imageRetention: "30 days", trainsOnImages: false, minimumAge: 18)
        XCTAssertEqual(offer(Self.planner(gold: Tally(30, of: 30), terms: noByok)), .hidden(.termsDoNotPermit))
    }

    func testRowsForAnotherProviderDoNotCount() {
        XCTAssertEqual(offer(Self.source(Self.row("dreamlabs.dream-1"))), .hidden(.rowsForAnotherProvider))
    }

    func testTellNeedsFourOutOfTenOverDoNothing() {
        XCTAssertTrue(offer(Self.source(Self.row(holdout: 5, floor: 1)), .tell).canRun)
        XCTAssertEqual(offer(Self.source(Self.row(holdout: 4, floor: 1)), .tell), .hidden(.belowBar(mode: .tell)))
    }

    func testAutoNeedsSixOutOfTenOverDoNothing() {
        XCTAssertEqual(offer(Self.source(Self.row(holdout: 6, floor: 1)), .auto), .hidden(.belowBar(mode: .auto)))
        guard case .offered(let card) = offer(Self.source(Self.row(holdout: 7, floor: 1)), .auto) else {
            return XCTFail("7/10 over 1/10 is 6 out of 10")
        }
        XCTAssertEqual(card.confirmation, .newKindsOnly)
    }

    func testTheMarginIsExactWithUnequalCounts() {
        XCTAssertTrue(OfferRule.beats(Tally(8, of: 20), Tally(0, of: 10), byOutOf10: 4))
        XCTAssertFalse(OfferRule.beats(Tally(7, of: 20), Tally(0, of: 10), byOutOf10: 4))
        XCTAssertFalse(OfferRule.beats(Tally(1, of: 0), Tally(0, of: 10), byOutOf10: 0))
    }

    func testAnyCrossingAfterTheGateHidesIt() {
        XCTAssertEqual(offer(Self.source(Self.row(holdout: 10, crossings: 1))), .hidden(.crossingsAfterGate(1)))
    }

    func testTooFewHoldoutSeedsHideIt() {
        XCTAssertEqual(offer(Self.source(Self.row(holdout: 5, n: 5))), .hidden(.holdoutTooSmall(5)))
    }

    func testAnUngatedRowCannotPutACardUp() {
        XCTAssertEqual(offer(Self.source(Self.row(gated: false))), .hidden(.ungatedRow))
    }

    func testAPlusAssistLabelNeedsAnAssistRow() {
        XCTAssertEqual(offer(Self.source(label: "Dream-1 + assist")), .hidden(.labelClaimsAssist))
        XCTAssertTrue(offer(Self.source(Self.row(assist: true), label: "Dream-1 + assist")).canRun)
    }

    func testAnotherVersionIsUntestedAndCannotRun() {
        let moved = offer(Self.source(Self.row(version: "older")))
        guard case .untestedVersion(_, let line) = moved else { return XCTFail("\(moved)") }
        XCTAssertFalse(moved.canRun)
        XCTAssertTrue(line.hasPrefix("Untested version."))
        let aliasMoved = offer(Self.source(), live: "newer")
        guard case .untestedVersion = aliasMoved else { return XCTFail("\(aliasMoved)") }
        XCTAssertTrue(offer(Self.source(), live: "abc123").canRun)
    }

    func testAWeakPlannerIsTellWithAGoAndNeverAuto() {
        let weak = Self.planner(gold: Tally(23, of: 30))
        guard case .offered(let card) = offer(weak, .tell) else { return XCTFail() }
        XCTAssertEqual(card.confirmation, .goEveryTime)
        XCTAssertEqual(offer(weak, .auto), .hidden(.goldBelowAutoBar))
        let none = Self.planner(gold: nil)
        XCTAssertEqual(offer(none, .auto), .hidden(.goldBelowAutoBar))
    }

    func testAPlannerAtEightyPercentMayGoToAuto() {
        let ok = Self.planner(gold: Tally(24, of: 30))
        guard case .offered(let tell) = offer(ok, .tell) else { return XCTFail() }
        XCTAssertEqual(tell.confirmation, .countdown)
        XCTAssertTrue(offer(ok, .auto).canRun)
    }

    func testARealDuckIsItsOwnRowAndOffByDefault() {
        XCTAssertEqual(offer(Self.source(), .tell, .real), .hidden(.realDuckOff))
        let tried = RealDuckRow(enabledOnRobot: true, testerRunDate: "2026-11-25", crossingsAfterGate: 0)
        XCTAssertTrue(offer(Self.source(realDuck: tried), .tell, .real).canRun)
        let enabledUntried = RealDuckRow(enabledOnRobot: true, testerRunDate: nil, crossingsAfterGate: nil)
        XCTAssertEqual(offer(Self.source(realDuck: enabledUntried), .tell, .real), .hidden(.realDuckOff))
        let crossed = RealDuckRow(enabledOnRobot: true, testerRunDate: "2026-11-25", crossingsAfterGate: 2)
        XCTAssertEqual(offer(Self.source(realDuck: crossed), .tell, .real), .hidden(.realDuckOff))
    }

    func testTheCardSaysTheNumberAndTheDay() {
        guard case .offered(let card) = offer(Self.source()) else { return XCTFail() }
        XCTAssertEqual(card.number, "6/10 on the practice duck, 11-20")
        XCTAssertEqual(offer(Self.source(Self.row(date: "Nov 20"))), .hidden(.undated))
    }

    func testTheCopyCarriesNoArmNumbersNoSafetyClaimAndNoEmDash() {
        for line in OfferRule.Words.all {
            XCTAssertFalse(line.contains("\u{2014}"), line)
            XCTAssertFalse(line.lowercased().contains("safe"), line)
            for banned in ["Robocurve", "3/3", "1,546", "61 of 62", "YAM"] {
                XCTAssertFalse(line.contains(banned), line)
            }
            XCTAssertNil(line.range(of: #"(^|[^A-Za-z])arms?([^A-Za-z]|$)"#, options: .regularExpression), line)
            XCTAssertTrue(line.contains("practice duck") || line.contains("real duck"), line)
        }
    }
}
