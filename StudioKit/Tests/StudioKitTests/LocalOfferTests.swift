import XCTest
@testable import StudioKit

/// Local models and the offer rule (brains-layer.md 7): no vendor, the model's own licence, both
/// rows still required, and the EvidenceRow pinned to the exact weights.
final class LocalOfferTests: XCTestCase {
    typealias F = LocalFixtures

    static func terms(_ id: String, physicalControl: TermsRow.Answer = .allowed, age: Int? = 0) -> TermsRow {
        .localModel(id, checked: "2026-11-13", licence: "Apache-2.0", source: "https://huggingface.co/Qwen",
                    physicalControl: physicalControl, minimumAge: age)
    }

    static func row(_ id: String, version: String, gold: Tally? = Tally(28, of: 30)) -> EvidenceRow {
        EvidenceRow(providerId: id, modelVersion: version, date: "2026-11-20", training: Tally(7, of: 10),
                    holdout: Tally(6, of: 10), doNothingHoldout: Tally(0, of: 10), oracleHoldout: Tally(10, of: 10),
                    closedSetGold: gold)
    }

    func lan(evidence: EvidenceRow? = nil, terms: TermsRow? = nil, version: LocalModelVersion = F.pinned) throws -> LANPlanner {
        try LANPlanner(endpoint: F.endpoint(), version: version, evidence: evidence, terms: terms, http: StubLocalHTTP(json: "{}"))
    }

    func testTheLocalTermsRowSaysThereIsNoVendor() {
        let t = Self.terms("lan.qwen3.5:4b")
        XCTAssertFalse(t.hasVendor)
        XCTAssertEqual(t.localModelLicence, "Apache-2.0")
        XCTAssertEqual(t.byokInThirdPartyApp, .notApplicable)
        XCTAssertEqual(t.trainsOnImages, false)
        XCTAssertEqual(t.imageRetention, "No vendor. Nothing is kept anywhere but your own devices.")
        XCTAssertTrue(t.permits(key: .none))
        XCTAssertFalse(Self.terms("x", physicalControl: .unknown).permits(key: .none), "an unread licence hides the card")
        XCTAssertFalse(Self.terms("x", age: nil).permits(key: .none))
        XCTAssertEqual(LocalPlannerWords.terms(t), "No vendor keeps anything. The model's own licence applies: Apache-2.0.")
        XCTAssertNil(LocalPlannerWords.terms(OfferRuleTests.vendorTerms))
        XCTAssertTrue(OfferRuleTests.vendorTerms.hasVendor)
    }

    func testOldStoredRowsStillDecode() throws {
        let old = #"{"providerId":"byok.v","checked":"2026-11-01","source":"x","physicalControl":"allowed","byokInThirdPartyApp":"allowed","imageRetention":"30 days","trainsOnImages":false,"minimumAge":18}"#
        let row = try JSONDecoder().decode(TermsRow.self, from: Data(old.utf8))
        XCTAssertNil(row.localModelLicence)
        let t = Self.terms("lan.x")
        XCTAssertEqual(try JSONDecoder().decode(TermsRow.self, from: JSONEncoder().encode(t)), t)
    }

    func testWithNoEvidenceRowEveryLocalCardIsHidden() throws {
        let lanPlanner = try lan(terms: Self.terms("lan.qwen3.5:4b"))
        XCTAssertNil(lanPlanner.info.evidence)
        let mlx = PhoneMLXPlanner(repository: "a/b", version: LocalModelVersion(model: "a/b", checkpoint: "0123456789ab"),
                                  runner: StubRunner { _ in "" }, terms: Self.terms("phone.a/b"))
        for mode in BrainMode.allCases {
            for venue in BrainVenue.allCases {
                XCTAssertEqual(OfferRule.offer(for: lanPlanner.info, mode: mode, venue: venue), .hidden(.noEvidence))
                XCTAssertEqual(OfferRule.offer(for: mlx.info, mode: mode, venue: venue), .hidden(.noEvidence))
            }
        }
        XCTAssertEqual(OfferRule.offer(for: try lan().info, mode: .tell, venue: .practice), .hidden(.noEvidence))
    }

    func testAPassingRowWouldShowACard() throws {
        let id = "lan.qwen3.5:4b"
        let p = try lan(evidence: Self.row(id, version: F.pinned.string), terms: Self.terms(id))
        XCTAssertEqual(OfferRule.offer(for: p.info, mode: .tell, venue: .practice),
                       .offered(.init(label: "On your own computer. Slower.", number: "6/10 on the practice duck, 11-20",
                                      confirmation: .countdown)))
        XCTAssertEqual(OfferRule.offer(for: p.info, mode: .auto, venue: .practice),
                       .offered(.init(label: "On your own computer. Slower.", number: "6/10 on the practice duck, 11-20",
                                      confirmation: .newKindsOnly)))
        XCTAssertEqual(OfferRule.offer(for: p.info, mode: .tell, venue: .real), .hidden(.realDuckOff))
        let mlx = PhoneMLXPlanner(repository: "a/b", version: LocalModelVersion(model: "a/b", checkpoint: "0123456789ab"),
                                  runner: StubRunner { _ in "" },
                                  evidence: Self.row("phone.a/b", version: "a/b@0123456789ab"), terms: Self.terms("phone.a/b"))
        XCTAssertTrue(OfferRule.offer(for: mlx.info, mode: .tell, venue: .practice).canRun)
    }

    func testBothRowsAreStillRequired() throws {
        let id = "lan.qwen3.5:4b"
        XCTAssertEqual(OfferRule.offer(for: try lan(evidence: Self.row(id, version: F.pinned.string)).info, mode: .tell,
                                       venue: .practice), .hidden(.noTerms))
    }

    func testAnUnpinnedLocalModelIsHiddenEvenWithAPassingRow() throws {
        let id = "lan.qwen3.5:4b"
        let tag = LocalModelVersion(model: "qwen3.5:4b")
        let p = try lan(evidence: Self.row(id, version: tag.string), terms: Self.terms(id), version: tag)
        XCTAssertEqual(OfferRule.offer(for: p.info, mode: .tell, venue: .practice), .hidden(.unpinnedLocalModel))
    }

    func testAnotherCheckpointOrServedModelIsAnUntestedVersion() async throws {
        let id = "lan.qwen3.5:4b"
        let q8 = LocalModelVersion(model: "qwen3.5:4b", checkpoint: "ffffeeeedddd", quantisation: "Q8_0")
        let p = try lan(evidence: Self.row(id, version: F.pinned.string), terms: Self.terms(id), version: q8)
        guard case .untestedVersion = OfferRule.offer(for: p.info, mode: .tell, venue: .practice) else {
            return XCTFail("a row for Q4_K_M does not stand for Q8_0")
        }
        // The server answers with a different model than the one measured.
        let good = try LANPlanner(endpoint: F.endpoint(), version: F.pinned, evidence: Self.row(id, version: F.pinned.string),
                                  terms: Self.terms(id), http: StubLocalHTTP(json: F.ollama(content: F.walk, model: "llama3.2:3b")))
        let d = try await good.decide(F.ask())
        guard case .untestedVersion = OfferRule.offer(for: good.info, mode: .tell, venue: .practice,
                                                      liveModelVersion: d.provider.modelVersion) else {
            return XCTFail("a different served model cannot run on the measured model's row")
        }
        XCTAssertEqual(OfferRule.offer(for: d.provider, mode: .tell, venue: .practice), .hidden(.unpinnedLocalModel))
    }

    func testOwnCodeRowsAreUnaffected() {
        XCTAssertTrue(OfferRule.offer(for: OfferRuleTests.source(), mode: .tell, venue: .practice).canRun,
                      "the phone driver's checkpoint hash has no @ and needs none: it is this app's own code")
    }
}
