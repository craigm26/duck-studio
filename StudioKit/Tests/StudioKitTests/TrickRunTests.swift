import XCTest
@testable import StudioKit

/// The trick game, whose whole balance is the corpus's measured odds.
final class TrickRunTests: XCTestCase {

    /// The real numbers, from intent-success.json on 2026-08-29.
    private let measured: [String: TrickRun.Measurement] = [
        "roulade": .init(achieves: 16, rollouts: 16, criterion: "ends standing"),
        "back_roll": .init(achieves: 14, rollouts: 16, criterion: "ends standing"),
        "headspin": .init(achieves: 1, rollouts: 16, criterion: "ends inverted"),
        "step_up": .init(achieves: 0, rollouts: 16, criterion: "ends standing on the flight"),
        "sit": .init(achieves: 16, rollouts: 16, criterion: "ends seated"),
    ]

    /// A trick pays the inverse of what it actually lands.
    func testAScoreIsTheInverseOfTheMeasuredOdds() {
        let run = TrickRun(measured: measured, seed: 1)
        func trick(_ id: String) -> TrickRun.Trick? { run.tricks.first { $0.id == id } }
        XCTAssertEqual(trick("roulade")?.score, 1, "16 of 16 is worth one")
        XCTAssertEqual(trick("headspin")?.score, 16, "1 of 16 is worth sixteen")
        XCTAssertEqual(trick("back_roll")?.score, 1, "14 of 16 rounds to one")
        XCTAssertEqual(trick("headspin")?.odds ?? 0, 1.0 / 16, accuracy: 1e-12)
    }

    /// A move measured at 0/16 is not hard, it is impossible on this floor —
    /// the stair moves need a step the flat ground does not have. It must not
    /// reach the card at all, and must never be scored as infinite.
    func testAMoveNothingEverAchievesIsNotOnTheCard() {
        let run = TrickRun(measured: measured, seed: 1)
        XCTAssertNil(run.tricks.first { $0.id == "step_up" })
        let impossible = TrickRun.Trick(id: "step_up", name: "Step up", achieves: 0,
                                        rollouts: 16, criterion: "")
        XCTAssertEqual(impossible.score, 0)
        XCTAssertFalse(impossible.isPossibleHere)
    }

    /// Hardest first, and stably ordered so the card does not shuffle itself.
    func testTheCardOpensOnWhatIsWorthAttempting() {
        let a = TrickRun(measured: measured, seed: 1).tricks.map(\.id)
        let b = TrickRun(measured: measured, seed: 99).tricks.map(\.id)
        XCTAssertEqual(a.first, "headspin")
        XCTAssertEqual(a, b, "the card is not the die — it must not vary with the seed")
    }

    /// The die is seeded, so a run can be replayed and disputed.
    func testARunIsReproducible() {
        func play(seed: UInt64) -> [Bool] {
            var run = TrickRun(measured: measured, seed: seed)
            return (0..<12).map { _ in run.attempt("back_roll")?.landed ?? false }
        }
        XCTAssertEqual(play(seed: 7), play(seed: 7))
        XCTAssertNotEqual(play(seed: 7), play(seed: 8))
    }

    /// Over many attempts the die must actually match the published odds —
    /// otherwise the number on screen is decoration.
    func testTheDieMatchesTheOddsItAdvertises() {
        var run = TrickRun(measured: measured, seed: 20260829)
        var landed = 0
        let attempts = 4000
        for _ in 0..<attempts where run.attempt("headspin")?.landed == true { landed += 1 }
        let rate = Double(landed) / Double(attempts)
        XCTAssertEqual(rate, 1.0 / 16, accuracy: 0.02,
                       "a 1-in-16 trick landed \\(landed) of \\(attempts)")
    }

    /// A combo rewards a streak and a miss ends it — capped, because an
    /// unbounded multiplier makes the safest move the only move.
    func testTheComboBuildsCapsAndBreaks() {
        var run = TrickRun(measured: measured, seed: 3)
        for expected in 1...TrickRun.comboCap {
            let attempt = run.attempt("roulade")     // 16/16, always lands
            XCTAssertEqual(attempt?.landed, true)
            XCTAssertEqual(attempt?.comboAfter, expected)
            XCTAssertEqual(attempt?.scored, expected, "one point times the combo")
        }
        XCTAssertEqual(run.attempt("roulade")?.comboAfter, TrickRun.comboCap,
                       "the combo is capped")
        XCTAssertEqual(run.score, 1 + 2 + 3 + 4 + 5 + 5)

        // A move that cannot land here breaks it.
        var unlucky = TrickRun(tricks: [
            .init(id: "never", name: "Never", achieves: 1, rollouts: 1_000_000, criterion: "")
        ], seed: 11)
        _ = unlucky.attempt("never")
        XCTAssertEqual(unlucky.combo, 0)
        XCTAssertEqual(unlucky.score, 0)
    }

    func testAnUnknownTrickIsRefusedRatherThanScored() {
        var run = TrickRun(measured: measured, seed: 1)
        XCTAssertNil(run.attempt("moonwalk"))
        XCTAssertEqual(run.attempts.count, 0)
        XCTAssertEqual(run.summary, "No tricks attempted.")
    }

    func testTheSummarySaysWhatHappened() {
        var run = TrickRun(measured: measured, seed: 5)
        for _ in 0..<6 { _ = run.attempt("roulade") }
        XCTAssertTrue(run.summary.contains("of 6 landed"), run.summary)
        XCTAssertTrue(run.summary.contains("Roulade"), run.summary)
    }

    /// The screen has to say what it is made of, because the modes read as
    /// editable and are not.
    func testTheCardSaysWhereItsPartsCanActuallyBeChanged() {
        let s = TrickRun.whatThisIsMadeOf
        XCTAssertTrue(s.contains("Nothing on this card can be edited here"), s)
        // It names both destinations rather than leaving "somewhere else".
        XCTAssertTrue(s.contains("Intents"), s)
        XCTAssertTrue(s.contains("Policies"), s)
        // And it keeps the remix caveat the draft path already makes: a remix
        // carries none of the recording's evidence.
        XCTAssertTrue(s.contains("carries none of the recording's evidence"), s)
        XCTAssertTrue(s.hasSuffix("."))
    }
}
