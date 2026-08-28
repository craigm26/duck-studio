import XCTest
import DuckKit
@testable import StudioKit

/// The validator is the choke-point, so it gets most of the attention. The
/// likeliest author of a bad automation is a language model that named a
/// plausible intent nobody recorded.
final class AutomationTests: XCTestCase {

    private let known: Set<String> = ["hold", "sit", "stand", "kick_left", "roulade", "back_roll"]

    private func rule(_ when: Automation.Predicate,
                      _ then: Automation.Action = .play(intent: "sit"),
                      name: String = "Test") -> Automation {
        Automation(name: name, when: when, then: then, origin: .model)
    }

    func testAGoodRuleValidates() throws {
        XCTAssertNoThrow(try AutomationValidator.validate(
            rule(.somethingAheadWithin(metres: 0.3)), knownIntents: known))
    }

    /// The failure a model actually makes: a plausible name that is not a clip.
    /// Refusing without saying which is right leaves the person stuck.
    func testAnInventedIntentIsRefusedWithASuggestion() {
        XCTAssertThrowsError(try AutomationValidator.validate(
            rule(.fallen, .play(intent: "stand_up")), knownIntents: known)) { error in
            guard case AutomationValidator.Refusal.unknownIntent(let name, let closest) = error else {
                return XCTFail("wrong refusal: \(error)")
            }
            XCTAssertEqual(name, "stand_up")
            XCTAssertEqual(closest, "stand", "the nearest real clip")
            XCTAssertTrue((error as! AutomationValidator.Refusal).message.contains("Did you mean stand?"))
        }
    }

    /// A name with nothing close to it should not get a misleading suggestion.
    func testAWildlyWrongIntentGetsNoSuggestion() {
        XCTAssertThrowsError(try AutomationValidator.validate(
            rule(.fallen, .play(intent: "photosynthesize")), knownIntents: known)) { error in
            guard case AutomationValidator.Refusal.unknownIntent(_, let closest) = error else {
                return XCTFail("wrong refusal")
            }
            XCTAssertNil(closest, "inventing a 'did you mean' for this would mislead")
        }
    }

    /// A distance the sensor cannot report makes a rule that never fires —
    /// worse than an error, because it looks like it is working.
    func testADistanceOutsideTheSensorsRangeIsRefused() {
        for metres in [0.0, 0.005, 4.5, 100.0] {
            XCTAssertThrowsError(try AutomationValidator.validate(
                rule(.somethingAheadWithin(metres: metres)), knownIntents: known),
                "\(metres) m should be refused")
        }
        for metres in [0.02, 0.3, 4.0] {
            XCTAssertNoThrow(try AutomationValidator.validate(
                rule(.wayAheadClearBeyond(metres: metres)), knownIntents: known),
                "\(metres) m is inside the sensor's range")
        }
    }

    func testABatteryFractionMustBeAFraction() {
        XCTAssertThrowsError(try AutomationValidator.validate(
            rule(.batteryBelow(fraction: 20)), knownIntents: known))
        XCTAssertNoThrow(try AutomationValidator.validate(
            rule(.batteryBelow(fraction: 0.2)), knownIntents: known))
    }

    func testAnUnnamedAutomationIsRefused() {
        XCTAssertThrowsError(try AutomationValidator.validate(
            rule(.fallen, name: "   "), knownIntents: known))
    }

    /// The validator does not care who proposed it. A person can type a wrong
    /// intent name just as easily as a model can invent one.
    func testTheSameRuleIsJudgedTheSameWhoeverWroteIt() {
        for origin in [Automation.Origin.person, .model] {
            let bad = Automation(name: "x", when: .fallen,
                                 then: .play(intent: "nope"), origin: origin)
            XCTAssertThrowsError(try AutomationValidator.validate(bad, knownIntents: known))
        }
    }

    /// The sentence is what a person reads to decide whether the rule says what
    /// they meant, so it must read in the order things happen.
    func testTheSentenceReadsInTheOrderItHappens() {
        let r = rule(.somethingAheadWithin(metres: 0.3), .play(intent: "sit"))
        XCTAssertEqual(r.sentence, "When something is within 0.30 m ahead, play sit.")
    }

    func testDepthUnreliableIsItsOwnPredicate() {
        // Not "nothing is there". Glass and bright sun both produce a frame
        // that failed, and a rule that conflates them drives into what it
        // could not range.
        let r = rule(.depthUnreliable, .play(intent: "hold"))
        XCTAssertNoThrow(try AutomationValidator.validate(r, knownIntents: known))
        XCTAssertTrue(r.sentence.contains("cannot see reliably"), r.sentence)
    }

    /// Every predicate must be answerable from something the robot actually
    /// reports — the vocabulary is bounded by DuckToF and DuckState.
    func testEveryPredicateMapsToARealReading() {
        let toF = DuckToF.Frame(sequence: 1, atMicroseconds: 0, rows: 8, columns: 8,
                                distanceMillimetres: Array(repeating: 300, count: 64),
                                status: Array(repeating: 5, count: 64))
        XCTAssertNotNil(toF.nearestInCentre(), "somethingAheadWithin reads this")
        XCTAssertTrue(toF.isTrustworthy(), "depthUnreliable reads this")
        XCTAssertNotNil(DuckState(receivedAt: Date()).safety?.fallen ?? nil as Bool?
                        ?? Optional(false), "fallen reads DuckState.safety")
    }
}
