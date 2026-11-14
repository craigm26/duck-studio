import XCTest
@testable import StudioKit

/// The two vendors' terms rows, the card words, and the offer rule for both hosted planners.
final class HostedPlannerTermsTests: XCTestCase {

    func testOnlyTwoVendorsAndNoGemini() {
        XCTAssertEqual(HostedVendor.allCases, [.anthropic, .openai])
        for word in ["Gemini", "Google"] {
            XCTAssertFalse(HostedPlannerWords.all.joined().contains(word), word)
        }
    }

    func testTheRowsArePinnedToTheDateRead() {
        for v in HostedVendor.allCases {
            XCTAssertEqual(v.terms.providerId, v.providerId)
            XCTAssertEqual(v.terms.checked, "2026-11-13")
            XCTAssertFalse(v.terms.source.isEmpty)
            XCTAssertEqual(v.terms.trainsOnImages, false)
            XCTAssertTrue(v.terms.imageRetention?.contains("30 days") == true)
            XCTAssertFalse(HostedTerms.conditions(v).isEmpty)
            XCTAssertFalse(HostedTerms.openQuestions(v).isEmpty)
        }
        // Anthropic: BYOK in a third-party app is not addressed, and no minimum age is stated.
        XCTAssertEqual(HostedTerms.anthropic.byokInThirdPartyApp, .unknown)
        XCTAssertNil(HostedTerms.anthropic.minimumAge)
        XCTAssertFalse(HostedTerms.anthropic.permits(key: .byok(provider: "anthropic")))
        // OpenAI: every field answered, with its conditions.
        XCTAssertEqual(HostedTerms.openai.minimumAge, 13)
        XCTAssertTrue(HostedTerms.openai.permits(key: .byok(provider: "openai")))
    }

    func testTheDefaultModelsArePinned() {
        XCTAssertEqual(HostedVendor.anthropic.info().modelVersion, "claude-haiku-5-5")
        XCTAssertEqual(HostedVendor.openai.info().modelVersion, "gpt-6-luna")
        for v in HostedVendor.allCases {
            let info = v.info()
            XCTAssertEqual(info.runsOn, .hosted(vendor: v.name))
            XCTAssertEqual(info.key, .byok(provider: v.rawValue))
            XCTAssertEqual(info.decisionDeadline, .seconds(8))
            XCTAssertNil(info.evidence, "no measured run exists for \(v)")
            XCTAssertFalse(info.realDuck.isOn)
        }
    }

    // MARK: the offer rule

    func testBothCardsAreHiddenToday() {
        for v in HostedVendor.allCases {
            for mode in BrainMode.allCases {
                for venue in BrainVenue.allCases {
                    XCTAssertEqual(OfferRule.offer(for: v.info(), mode: mode, venue: venue), .hidden(.noEvidence), "\(v)")
                }
            }
        }
    }

    static func passing(_ v: HostedVendor, version: String? = nil) -> EvidenceRow {
        EvidenceRow(providerId: v.providerId, modelVersion: version ?? v.defaultModel, date: "2026-11-20",
                    training: Tally(7, of: 10), holdout: Tally(6, of: 10), doNothingHoldout: Tally(1, of: 10),
                    oracleHoldout: Tally(10, of: 10), crossingsAfterGate: 0, closedSetGold: Tally(27, of: 30))
    }

    func testAPassingRowShowsOpenAIAndAnthropicStaysHiddenOnItsTerms() {
        let openai = HostedVendor.openai.info(evidence: Self.passing(.openai))
        guard case .offered(let card) = OfferRule.offer(for: openai, mode: .tell, venue: .practice) else {
            return XCTFail("a passing row and a permitting terms row show the card")
        }
        XCTAssertEqual(card.label, "Hosted by OpenAI, your key")
        XCTAssertEqual(card.number, "6/10 on the practice duck, 11-20")
        XCTAssertEqual(OfferRule.offer(for: openai, mode: .tell, venue: .real), .hidden(.realDuckOff))
        XCTAssertEqual(OfferRule.offer(for: openai, mode: .tell, venue: .practice, liveModelVersion: "gpt-6-luna-next"),
                       .untestedVersion(label: card.label,
                                        line: "Untested version. 6/10 on the practice duck, 11-20, was for an earlier version."))

        let anthropic = HostedVendor.anthropic.info(evidence: Self.passing(.anthropic))
        XCTAssertEqual(OfferRule.offer(for: anthropic, mode: .tell, venue: .practice), .hidden(.termsDoNotPermit),
                       "BYOK in a third-party app is unknown in Anthropic's terms")
        // With that one question answered, the same row would show it.
        let answered = TermsRow(providerId: "byok.anthropic", checked: "2026-11-13", source: "an answer from Anthropic",
                                physicalControl: .allowed, byokInThirdPartyApp: .allowed,
                                imageRetention: HostedTerms.anthropic.imageRetention, trainsOnImages: false, minimumAge: 13)
        let info = HostedVendor.anthropic.info(evidence: Self.passing(.anthropic))
        let withAnswer = PlannerInfo(id: info.id, modelVersion: info.modelVersion, label: info.label, runsOn: info.runsOn,
                                     key: info.key, decisionDeadline: info.decisionDeadline,
                                     evidence: info.evidence, terms: answered)
        XCTAssertTrue(OfferRule.offer(for: withAnswer, mode: .tell, venue: .practice).canRun)
    }

    func testARowForAnotherModelIsUntested() {
        let info = HostedVendor.openai.info(evidence: Self.passing(.openai, version: "gpt-6.1-terra"))
        guard case .untestedVersion = OfferRule.offer(for: info, mode: .tell, venue: .practice) else {
            return XCTFail("a row for another model does not show this one")
        }
    }

    // MARK: the words

    func testTheCardCarriesEveryRequiredLine() {
        for v in HostedVendor.allCases {
            let card = HostedPlannerWords.card(v).joined(separator: "\n")
            XCTAssertTrue(card.contains("Decisions come from an AI model (\(v.name), \(v.modelName)), not a person."), card)
            XCTAssertTrue(card.contains("Your key stays on this device and is sent only to \(v.name)."), card)
            XCTAssertTrue(card.contains("not affiliated with or endorsed by \(v.name)"), card)
            XCTAssertTrue(card.contains("up to 30 days"), card)
            XCTAssertTrue(card.contains("An adult must watch the duck and can stop it at any time."), card)
            XCTAssertTrue(card.contains("parent or guardian"), card)
            XCTAssertTrue(card.contains("can be wrong"), card)
        }
    }

    func testTheWordsMakeNoClaimTheyCannotKeep() {
        for s in HostedPlannerWords.all + PlannerErrorWordsTests.allErrors.map(\.says) {
            let lower = s.lowercased()
            for banned in ["safe", "safety", "guarantee", "gpt-powered", "powered by"] {
                XCTAssertFalse(lower.contains(banned), "\(banned): \(s)")
            }
            XCTAssertFalse(s.contains("\u{2014}"), "no em-dashes: \(s)")
            // "GPT" appears only inside the model's own name.
            XCTAssertFalse(s.replacingOccurrences(of: "GPT-6 Luna", with: "").contains("GPT"), s)
        }
    }

    func testAPastedKeyIsCheckedForShapeAndVendor() {
        XCTAssertEqual(HostedVendor.anthropic.cleaned("  \(HostedFixtures.anthropicKey)\n"), .success(HostedFixtures.anthropicKey))
        XCTAssertEqual(HostedVendor.openai.cleaned(HostedFixtures.openaiKey), .success(HostedFixtures.openaiKey))
        XCTAssertEqual(HostedVendor.openai.cleaned(HostedFixtures.anthropicKey), .failure(.wrongVendor(.openai)))
        XCTAssertEqual(HostedVendor.anthropic.cleaned(HostedFixtures.openaiKey), .failure(.wrongVendor(.anthropic)))
        XCTAssertEqual(HostedVendor.anthropic.cleaned("   "), .failure(.empty))
        XCTAssertEqual(HostedVendor.anthropic.cleaned("sk-ant-\u{201C}x\u{201D}"), .failure(.badCharacters))
    }
}

enum PlannerErrorWordsTests {
    static let allErrors: [PlannerError] = [
        .noKey, .keyRefused(vendor: "OpenAI"), .noCredit(vendor: "Anthropic"),
        .rateLimited(vendor: "OpenAI", retryAfterS: 2.2), .rateLimited(vendor: "OpenAI", retryAfterS: nil),
        .busy(vendor: "Anthropic", status: 529), .refusedRequest(vendor: "OpenAI", status: 400, detail: "bad"),
        .unreadable(vendor: "OpenAI"), .network(vendor: "Anthropic"), .timedOut,
    ]
}
