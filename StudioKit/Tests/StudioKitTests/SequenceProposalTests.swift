import XCTest
import DuckKit
@testable import StudioKit

/// Turning loose primitives into something that moves a duck is the dangerous
/// part, so it is tested here rather than exercised by talking to a phone.
///
/// NOTHING A MODEL SAYS ABOUT A SPEED IS TRUSTED, and the two tests that matter
/// most say it twice: a speed of five clamps to the driving limit rather than
/// multiplying it, and a negative one is refused by name rather than quietly
/// turning the duck round.
final class SequenceProposalTests: XCTestCase {

    private let clock = Date(timeIntervalSince1970: 0)

    private func resolve(_ moves: [SequenceProposal.Move]) throws -> DuckSequence {
        try SequenceProposal(name: "a", moves: moves)
            .resolve(named: "a", provenance: .said("x"), venue: .sim, at: clock)
    }

    // MARK: - the words

    func testTheWordsAModelIsOfferedAreExactlyTheWordsThatResolve() throws {
        for word in SequenceProposal.offeredWords {
            XCTAssertNoThrow(try SequenceProposal.twist(for: word, share: 1),
                             "\"\(word)\" is offered and does not resolve")
        }
        XCTAssertTrue(SequenceProposal.offeredWords.allSatisfy {
            DuckTalk.instructions.contains($0)
        }, "and every one of them is in what the model is told")
    }

    func testAnUnknownDirectionIsRefusedWithTheNearestWordWhenThereIsOne() {
        XCTAssertThrowsError(try SequenceProposal.twist(for: "forwards", share: 1)) { error in
            guard case SequenceProposal.Unresolvable
                .unknownDirection(_, let closest) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(closest, "forward")
        }
    }

    func testAnUnknownDirectionOffersNoHintWhenAHintWouldBeWrong() {
        XCTAssertThrowsError(try SequenceProposal.twist(for: "xyzzy", share: 1)) { error in
            guard case SequenceProposal.Unresolvable
                .unknownDirection(_, let closest) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertNil(closest)
        }
    }

    // MARK: - the clamps

    func testSpeedIsClampedToTheDrivingLimitsRatherThanTrusted() throws {
        let fast = try resolve([SequenceProposal.Move(go: "forward", seconds: 1, speed: 5)])
        XCTAssertEqual(fast.steps[0].twist.vx, DuckDrive.maxForward, accuracy: 1e-9)
        XCTAssertThrowsError(
            try resolve([SequenceProposal.Move(go: "forward", seconds: 1, speed: -1)])) {
            XCTAssertEqual($0 as? SequenceProposal.Unresolvable, .speedOutOfRange(-1))
        }
        let half = try resolve([SequenceProposal.Move(go: "forward", seconds: 1, speed: 0.5)])
        XCTAssertEqual(half.steps[0].twist.vx, DuckDrive.maxForward * 0.5, accuracy: 1e-9)
    }

    func testATwistUnderTheDeadZoneIsSaidPlainlyRatherThanLookingLikeAStall() throws {
        let gentle = try resolve([SequenceProposal.Move(go: "forward", seconds: 1, speed: 0.01)])
        let twist = gentle.steps[0].twist
        XCTAssertTrue(twist.standsStill)
        XCTAssertTrue(DuckDrive.says(twist).contains("the gait working"), DuckDrive.says(twist))
    }

    /// COMPARED AGAINST `DuckDrive.twist(for:)` WITH THE STICK PUSHED LEFT, so
    /// the two readers can never disagree about a sign. Pollen's contract fixes
    /// `vyaw` positive turning LEFT while a stick pushed left reads negative;
    /// both negations are load-bearing and neither is obvious.
    func testTurnLeftIsPositiveYawAndAgreesWithTwistForSticks() throws {
        let stick = DuckDrive.twist(for: DuckDrive.Sticks(
            left: .centred, right: DuckDrive.Stick(x: -1, y: 0)))
        let said = try SequenceProposal.twist(for: "turn left", share: 1)
        XCTAssertGreaterThan(said.vyaw, 0)
        XCTAssertEqual(said.vyaw, stick.vyaw, accuracy: 1e-9)

        let strafing = DuckDrive.twist(for: DuckDrive.Sticks(
            left: DuckDrive.Stick(x: -1, y: 0), right: .centred))
        let left = try SequenceProposal.twist(for: "left", share: 1)
        XCTAssertEqual(left.vy, strafing.vy, accuracy: 1e-9)
    }

    func testSecondsOutOfRangeNamesTheRange() {
        for bad in [0.0, 0.01, DuckSequence.maximumMoveSeconds + 1] {
            XCTAssertThrowsError(
                try resolve([SequenceProposal.Move(go: "forward", seconds: bad)])) {
                XCTAssertEqual($0 as? SequenceProposal.Unresolvable, .secondsOutOfRange(bad))
            }
        }
        let message = SequenceProposal.Unresolvable.secondsOutOfRange(0).message
        XCTAssertTrue(message.contains("0.1"), message)
        XCTAssertTrue(message.contains("30.0"), message)
    }

    func testAWholeSequenceOverTheCeilingIsRefusedBeforeItIsBuilt() {
        let moves = Array(repeating: SequenceProposal.Move(go: "forward", seconds: 30),
                          count: 8)
        XCTAssertThrowsError(try resolve(moves)) { error in
            guard case SequenceProposal.Unresolvable.tooLong(let seconds) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(seconds, 240, accuracy: 1e-9)
        }
    }

    func testNoMovesIsRefusedByName() {
        XCTAssertThrowsError(try resolve([])) {
            XCTAssertEqual($0 as? SequenceProposal.Unresolvable, .noMoves)
        }
    }

    // MARK: - what the model is told

    func testTheGroundingQuotesTheLimitsResolveClampsAgainst() {
        let grounding = SequenceProposal.grounding()
        XCTAssertTrue(grounding.contains(String(format: "%.2f", DuckDrive.maxForward)), grounding)
        XCTAssertTrue(grounding.contains(String(format: "%.2f", DuckDrive.maxTurn)), grounding)
        XCTAssertTrue(grounding.contains(String(format: "%.2f", DuckDrive.deadZone)), grounding)
        XCTAssertTrue(grounding.contains("0.30"), grounding)
        XCTAssertTrue(grounding.contains("1.50"), grounding)
        XCTAssertTrue(grounding.contains("0.05"), grounding)
    }

    func testTheInstructionsEndWithExactlyOneSampleObject() {
        let instructions = DuckTalk.instructions
        XCTAssertTrue(instructions.contains("Answer with JSON and nothing else."))
        XCTAssertTrue(instructions.contains("No explanation, no markdown fence."))
        XCTAssertTrue(instructions.hasSuffix("]}"), String(instructions.suffix(40)))
        XCTAssertEqual(instructions.components(separatedBy: "\"moves\"").count, 2,
                       "exactly one sample object, because a model shown two emits two")
    }

    // MARK: - reading a model's reply

    func testAModelsReplyBecomesAProposal() throws {
        let json = "{\"name\":\"Forward then left\",\"moves\":"
                 + "[{\"go\":\"forward\",\"seconds\":2.0,\"speed\":1.0},"
                 + "{\"go\":\"turn left\",\"seconds\":1.5}]}"
        let proposal = try SequenceProposal.read(fromJSON: json)
        XCTAssertEqual(proposal.name, "Forward then left")
        XCTAssertEqual(proposal.moves.map(\.go), ["forward", "turn left"])
        XCTAssertEqual(proposal.moves[1].speed, nil)
    }

    func testAQuotedNumberIsStillANumber() throws {
        let json = "{\"moves\":[{\"go\":\"forward\",\"seconds\":\"2\"}]}"
        XCTAssertEqual(try SequenceProposal.read(fromJSON: json).moves[0].seconds, 2)
    }

    func testAReplyWithNoMovesIsRefusedByName() {
        XCTAssertThrowsError(try SequenceProposal.read(fromJSON: "{\"name\":\"x\"}")) {
            XCTAssertEqual($0 as? SequenceProposal.DraftError, .missing("moves"))
        }
        XCTAssertThrowsError(try SequenceProposal.read(fromJSON: "not json")) {
            XCTAssertEqual($0 as? SequenceProposal.DraftError, .wrongType("the reply"))
        }
    }

    // MARK: - a reading becomes a sequence

    func testAReadingBecomesASequenceWithTheSameNumbers() throws {
        let reading = DuckTalk.read("forward for two seconds then turn left for 1.5 seconds")
        let sequence = try SequenceProposal(name: "said", moves: reading.moves)
            .resolve(named: "said", provenance: .said("forward…"), venue: .sim, at: clock)
        XCTAssertEqual(sequence.steps.first?.twist.vx, DuckDrive.maxForward)
        XCTAssertEqual(sequence.steps.last?.twist.vyaw, DuckDrive.maxTurn)
        XCTAssertEqual(sequence.wallSeconds, 0, "a typed sequence cost nobody any time")
        XCTAssertEqual(sequence.provenance, .said("forward…"))
    }

    func testASampledMoveIsOneStepPerHoldSeconds() throws {
        let sequence = try resolve([SequenceProposal.Move(go: "forward", seconds: 2)])
        XCTAssertEqual(sequence.steps.count, 20)
        XCTAssertEqual(sequence.steps[1].atSim, DuckDrive.holdSeconds, accuracy: 1e-9)
        XCTAssertTrue(sequence.steps.allSatisfy { $0.policySaid == nil },
                      "nothing measured it, so nothing claims to have")
    }

    func testASequenceWrittenFromWordsCannotBeKeptOnTheBenchAndSaysWhy() throws {
        let sequence = try resolve([SequenceProposal.Move(go: "forward", seconds: 2)])
        XCTAssertFalse(sequence.canBeRecordedOnTheBench)
        XCTAssertEqual(sequence.cannotBeKept, DuckSequence.benchNeverNamedANetwork)
    }

    /// THE NUMBERS, NOT THE WORDS, AND NOT COMPOSED IN A VIEW. What a person
    /// sees before anything moves is the twist, in `DuckDrive`'s own sentence —
    /// dead-zone line included, so a gentle move reads as the gait working
    /// rather than as a broken link.
    func testAMoveIsSpelledAsTheTwistItWillSend() {
        let full = SequenceProposal.spelled(
            SequenceProposal.Move(go: "forward", seconds: 2, speed: 1))
        XCTAssertTrue(full.contains("forward"), full)
        XCTAssertTrue(full.contains("2.0 s"), full)
        XCTAssertTrue(full.contains(String(format: "%.2f", DuckDrive.maxForward)), full)

        let gentle = SequenceProposal.spelled(
            SequenceProposal.Move(go: "forward", seconds: 1, speed: 0.01))
        XCTAssertTrue(gentle.contains("the gait working"), gentle)

        // A word that resolves to nothing spells itself rather than trapping.
        XCTAssertEqual(SequenceProposal.spelled(
            SequenceProposal.Move(go: "xyzzy", seconds: 1)), "xyzzy")
    }

    func testAStopOnlySequenceIsRefusedRatherThanSentAsNothing() {
        XCTAssertThrowsError(try resolve([SequenceProposal.Move(go: "stop", seconds: 1)])) {
            XCTAssertEqual($0 as? DuckSequence.Refusal, .empty)
        }
    }
}
