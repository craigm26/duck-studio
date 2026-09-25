import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import DuckEvidence
@testable import StudioKit

/// A router proposes and a person decides, so the two things tested hardest are
/// what reaches the duck (labels mapped here, never the router's numbers) and
/// what reaches the record (one correction per clause, consent carried).
final class DuckIntentPlanTests: XCTestCase {

    /// A real `duck-intent-plan/0`, as duckbatch's router wrote it, trimmed to
    /// three clauses. The `command` blocks are Pollen's numbers and are here so
    /// a test can show they are not the ones sent.
    static let routed = """
    {"format": "duck-intent-plan/0", "request": "walk slowly while looking right, then turn left, then say hello",
     "model": "decide",
     "steps": [
      {"clause": "walk slowly while looking right",
       "labels": {"action": "walk_forward", "speed": "slow", "head": "look_right", "sound": "chirp"},
       "confidence": {"action": 0.93, "speed": 0.71, "head": 0.52, "sound": 0.31},
       "command": {"kind": "twist", "twist": [0.0833, 0.0, 0.0], "head": [0, 0, -0.4, 0], "duration_s": 2.0}},
      {"clause": "turn left",
       "labels": {"action": "turn_left", "speed": "normal", "head": "straight", "sound": "chirp"},
       "confidence": {"action": 0.88, "speed": 0.66, "head": 0.61, "sound": 0.2},
       "command": {"kind": "twist", "twist": [0.0, 0.0, 0.6667], "head": [0, 0, 0, 0], "duration_s": 2.0}},
      {"clause": "say hello",
       "labels": {"action": "make_sound", "speed": "normal", "head": "straight", "sound": "greet"},
       "confidence": {"action": 0.97, "speed": 0.5, "head": 0.5, "sound": 0.9},
       "command": {"kind": "sound", "tag": "greet"}}
     ]}
    """

    private func plan(_ json: String = routed) throws -> DuckIntentPlan {
        try DuckIntentPlan.read(Data(json.utf8))
    }

    // MARK: - reading

    func testARoutedPlanReadsAsOneNodePerClauseWithItsConfidence() throws {
        let p = try plan()
        XCTAssertEqual(p.nodes.map(\.clause),
                       ["walk slowly while looking right", "turn left", "say hello"])
        XCTAssertEqual(p.model, "decide")
        XCTAssertEqual(p.nodes[0].confidence["head"], 0.52)
        XCTAssertTrue(p.nodes.allSatisfy { $0.labels == $0.proposed }, "nothing is edited on arrival")
    }

    func testALabelOutsideTheVocabularyRefusesThePlanRatherThanGuessing() {
        let bad = Self.routed.replacingOccurrences(of: "\"turn_left\"", with: "\"moonwalk\"")
        XCTAssertThrowsError(try plan(bad)) { error in
            XCTAssertEqual(error as? DuckIntentPlan.ReadError, .unknownLabel("action", "moonwalk"))
        }
    }

    func testAnotherFormatIsRefusedByName() {
        let other = Self.routed.replacingOccurrences(of: "duck-intent-plan/0", with: "duck-intent-plan/9")
        XCTAssertThrowsError(try plan(other)) { error in
            XCTAssertEqual(error as? DuckIntentPlan.ReadError, .wrongFormat("duck-intent-plan/9"))
        }
    }

    func testAPlanWithNoStepsSaysSoInsteadOfShowingAnEmptyChart() {
        let empty = #"{"format": "duck-intent-plan/0", "request": "hm", "steps": []}"#
        XCTAssertThrowsError(try plan(empty)) { error in
            XCTAssertEqual(error as? DuckIntentPlan.ReadError, .noSteps)
        }
    }

    // MARK: - flags

    func testOnlyLabelsUnderTheMeasuredLineOnHeadsThatMatterAreFlagged() throws {
        let p = try plan()
        XCTAssertEqual(DuckIntentPlan.autoAccept, 0.6, "r001's line: every error was at 0.56 or below")
        XCTAssertEqual(p.nodes[0].flagged, [.head], "0.52 on the head of a walk is asked about")
        XCTAssertEqual(p.nodes[1].flagged, [], "0.61 is over the line")
        XCTAssertEqual(p.nodes[2].flagged, [], "a sound has no speed or head to ask about")
        XCTAssertEqual(p.flaggedCount, 1)
    }

    func testChoosingALabelClearsItsFlagEvenIfTheChoiceIsTheSameHead() throws {
        var p = try plan()
        var walk = p.nodes[0]
        try walk.set(.head, to: "straight")
        p.update(walk)
        XCTAssertEqual(p.nodes[0].flagged, [])
        XCTAssertEqual(p.nodes[0].outcome, .edited)
    }

    func testEditingToALabelOutsideTheVocabularyIsRefused() throws {
        var walk = try plan().nodes[0]
        XCTAssertThrowsError(try walk.set(.speed, to: "ludicrous"))
        XCTAssertEqual(walk.labels, walk.proposed)
    }

    // MARK: - running

    func testMovementsReachTheDuckAsLabelsMappedHereAndNotAsTheRoutersNumbers() throws {
        let run = try plan().run()
        XCTAssertEqual(run.moves, [
            SequenceProposal.Move(go: "forward", seconds: 2, speed: 1.0 / 3.0),
            SequenceProposal.Move(go: "turn left", seconds: 2, speed: 2.0 / 3.0),
        ])
        let sequence = try SequenceProposal(name: "p", moves: run.moves)
            .resolve(named: "p", provenance: .drafted(model: "decide", asked: "x"),
                     venue: .sim, at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(sequence.steps.first?.twist.vx ?? 0, DuckDrive.maxForward / 3, accuracy: 1e-9,
                       "a third of THIS app's limit, not the router's 0.0833")
    }

    func testWhatIsKeptButNotSentIsSaidRatherThanDroppedQuietly() throws {
        let run = try plan().run()
        XCTAssertEqual(run.notSent.count, 2)
        XCTAssertTrue(run.notSent[0].contains("head"))
        XCTAssertTrue(run.notSent[1].contains("say hello"))
    }

    func testASkillAtTheEndIsLoadedWhenTheMovesFinish() throws {
        var p = try plan()
        var last = p.nodes[2]
        try last.set(.action, to: "kick_right")
        p.update(last)
        let run = try p.run()
        XCTAssertEqual(run.thenLoading, .kickRight)
        XCTAssertEqual(run.moves.count, 2)
    }

    func testASkillBeforeAMoveIsRefusedByNameBecauseASkillDoesNotHandBack() throws {
        var p = try plan()
        var first = p.nodes[0]
        try first.set(.action, to: "roll")
        p.update(first)
        XCTAssertThrowsError(try p.run()) { error in
            XCTAssertEqual(error as? DuckIntentPlan.RunRefusal,
                           .skillNotLast("walk slowly while looking right"))
        }
        p.move(from: 0, to: 3)
        XCTAssertEqual(try p.run().thenLoading, .roulade, "moved to the end, it runs")
    }

    func testAPlanThatIsOnlyASkillStillRunsWithOneSecondOfStandingFirst() throws {
        var p = try plan()
        for node in p.nodes.prefix(2) { var n = node; n.discarded = true; p.update(n) }
        var last = p.nodes[2]
        try last.set(.action, to: "peck_ground")
        p.update(last)
        let run = try p.run()
        XCTAssertEqual(run.moves, [SequenceProposal.Move(go: "stop", seconds: 1)])
        XCTAssertEqual(run.thenLoading, .groundPick)
    }

    func testDiscardedAndRefusedStepsAreNotSentAndAllOfThemIsNothingToRun() throws {
        var p = try plan()
        var sound = p.nodes[2]; sound.discarded = true; p.update(sound)
        var walk = p.nodes[0]; try walk.set(.action, to: "unsupported"); p.update(walk)
        XCTAssertEqual(try p.run().moves.map(\.go), ["turn left"])
        var turn = p.nodes[1]; turn.discarded = true; p.update(turn)
        XCTAssertThrowsError(try p.run()) { error in
            XCTAssertEqual(error as? DuckIntentPlan.RunRefusal, .nothingToRun)
        }
    }

    func testAChangedHoldTimeIsTheOneThatRuns() throws {
        var p = try plan()
        var turn = p.nodes[1]; turn.seconds = 3.5; p.update(turn)
        XCTAssertEqual(try p.run().moves[1].seconds, 3.5)
    }

    // MARK: - the record

    func testEveryClauseBecomesOneCorrectionWithItsOutcome() throws {
        var p = try plan()
        var walk = p.nodes[0]; try walk.set(.head, to: "straight"); p.update(walk)
        var sound = p.nodes[2]; sound.discarded = true; p.update(sound)
        p.move(from: 2, to: 0)
        let records = try p.corrections(router: .decide, share: .local, client: "Microduck Studio test")
        XCTAssertEqual(records.count, 3)
        let lines = records.map { $0.jsonLine() }
        XCTAssertTrue(lines[0].contains(#""outcome":"edited""#), "in the order proposed, not as dragged")
        XCTAssertTrue(lines[1].contains(#""outcome":"accepted""#))
        XCTAssertTrue(lines[2].contains(#""outcome":"rejected""#))
        XCTAssertFalse(lines[2].contains(#""final""#), "a discarded step has no final labels")
        XCTAssertTrue(lines.allSatisfy { $0.contains(#""vocabulary":"r001""#) })
    }

    func testRecordsDefaultToStayingOnThePhone() throws {
        let records = try plan().corrections(router: .decide, share: .local, client: "t")
        XCTAssertTrue(records.allSatisfy { !$0.mayLeaveDevice })
    }

    /// Writes an edited plan's records for duckbatch's reader, when asked to:
    /// `DUCK_PLAN_FEEDBACK_OUT=… swift test --filter DuckIntentPlanTests`, then
    /// `duckbatch feedback validate` on the file.
    func testWritesAPlansCorrectionsForTheReaderCrossCheck() throws {
        guard let out = ProcessInfo.processInfo.environment["DUCK_PLAN_FEEDBACK_OUT"] else { return }
        var p = try plan()
        var walk = p.nodes[0]; try walk.set(.head, to: "straight"); p.update(walk)
        var sound = p.nodes[2]; sound.discarded = true; p.update(sound)
        let lines = try p.corrections(router: .decide, share: .research, client: "Microduck Studio test")
            .map { $0.jsonLine() }
        try (lines.joined(separator: "\n") + "\n").write(toFile: out, atomically: true, encoding: .utf8)
    }

    // MARK: - the router

    func testTheHTTPRouterPostsTheTextAndReadsThePlanBack() async throws {
        let base = URL(string: "http://192.168.1.20:8771")!
        let router = HTTPIntentRouter(base: base) { request in
            XCTAssertEqual(request.url?.absoluteString, "http://192.168.1.20:8771/route")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String]
            XCTAssertEqual(body?["text"], "turn left")
            return Data(DuckIntentPlanTests.routed.utf8)
        }
        let p = try await router.plan(for: "turn left")
        XCTAssertEqual(p.nodes.count, 3)
        XCTAssertEqual(router.identity, .decide)
    }
}
