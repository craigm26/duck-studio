import XCTest
import DuckKit
@testable import StudioKit

/// Interpreting model output is the dangerous part, so it is tested here rather
/// than exercised by talking to a phone.
final class AutomationProposalTests: XCTestCase {

    private let known: Set<String> = ["hold", "sit", "stand", "kick_left", "roulade"]

    func testAWellFormedProposalResolves() throws {
        let rule = try AutomationProposal(
            name: "Back off", predicate: "somethingAheadWithin",
            value: 0.3, intent: "sit").resolve(knownIntents: known)
        XCTAssertEqual(rule.sentence, "When something is within 0.30 m ahead, play sit.")
        XCTAssertEqual(rule.origin, .model, "and it is marked as drafted, not typed")
    }

    /// The commonest generated failure: a predicate that sounds right.
    func testAnInventedPredicateIsRefusedWithTheNearestReal() {
        XCTAssertThrowsError(try AutomationProposal(
            name: "x", predicate: "somethingAheadWithinRange",
            value: 0.3, intent: "sit").resolve(knownIntents: known)) { error in
            guard case AutomationProposal.Unresolvable.unknownPredicate(_, let closest) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(closest, "somethingAheadWithin")
        }
    }

    /// Matching is EXACT. A rule that fires on a predicate the author did not
    /// write is a rule nobody wrote.
    func testMatchingIsExactNotFuzzy() {
        for wrong in ["SomethingAheadWithin", "something_ahead_within", "somethingahead"] {
            XCTAssertThrowsError(try AutomationProposal(
                name: "x", predicate: wrong, value: 0.3,
                intent: "sit").resolve(knownIntents: known), wrong)
        }
    }

    /// Resolution and validation are different questions and give different
    /// errors: unknown WORDS versus an inadmissible RULE.
    func testAnOutOfRangeDistanceFailsValidationNotResolution() {
        XCTAssertThrowsError(try AutomationProposal(
            name: "x", predicate: "somethingAheadWithin",
            value: 40, intent: "sit").resolve(knownIntents: known)) { error in
            XCTAssertTrue(error is AutomationValidator.Refusal,
                          "the words were fine; the rule was not: \(error)")
        }
    }

    func testAnInventedMotionIsCaughtByTheValidator() {
        // "stand_up" is one edit from "stand", so the reader gets pointed at it.
        XCTAssertThrowsError(try AutomationProposal(
            name: "x", predicate: "fallen", value: 0,
            intent: "stand_up").resolve(knownIntents: known)) { error in
            guard case AutomationValidator.Refusal.unknownIntent(_, let closest) = error else {
                return XCTFail("wrong error")
            }
            XCTAssertEqual(closest, "stand")
        }
        // "get_up" is close to nothing, and inventing a suggestion there would
        // send someone to a motion that has nothing to do with what they meant.
        XCTAssertThrowsError(try AutomationProposal(
            name: "x", predicate: "fallen", value: 0,
            intent: "get_up").resolve(knownIntents: known)) { error in
            guard case AutomationValidator.Refusal.unknownIntent(_, let closest) = error else {
                return XCTFail("wrong error")
            }
            XCTAssertNil(closest)
        }
    }

    /// The grounding must list only motions that exist right now — the
    /// commonest way a generated rule fails is naming one that sounds right.
    func testTheGroundingListsOnlyWhatExists() {
        let text = AutomationProposal.grounding(knownIntents: known)
        for intent in known { XCTAssertTrue(text.contains(intent), intent) }
        XCTAssertFalse(text.contains("headspin"), "not in this library, not in the grounding")
        for predicate in AutomationProposal.predicateNames {
            XCTAssertTrue(text.contains(predicate), predicate)
        }
        XCTAssertTrue(text.contains("Do not invent"))
    }

    /// A proposal and a typed rule are judged identically — being generated
    /// earns nothing.
    func testGenerationEarnsNoLatitude() throws {
        let proposal = AutomationProposal(name: "y", predicate: "fallen",
                                          value: 0, intent: "stand")
        let drafted = try proposal.resolve(knownIntents: known, origin: .model)
        let typed = try proposal.resolve(knownIntents: known, origin: .person)
        XCTAssertEqual(drafted.when, typed.when)
        XCTAssertEqual(drafted.then, typed.then)
        XCTAssertNotEqual(drafted.origin, typed.origin, "only the label differs")
    }
}
