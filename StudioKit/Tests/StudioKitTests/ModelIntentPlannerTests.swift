import XCTest
@testable import StudioKit

/// The phone's planner asks what duckbatch measured and reads what duckbatch
/// reads. Both halves are pinned to duckbatch's own files.
final class ModelIntentPlannerTests: XCTestCase {

    // MARK: - the bundled files are duckbatch's, unchanged

    /// sha256 of `planner.export_for_phone`'s output at craigm26/duckbatch
    /// (p002). A different prompt is a different experiment, so a change here
    /// has to be a re-export, never an edit.
    static let pinned = [
        "Planner/instructions.txt": "95d86b7a9ad99bb4f698d8d0b308c108ae535dcc1d2336aa76a1c0424f28d5ee",
        "Planner/p002.json": "9dcea89908349acfa10e55cd498b124e3622a050c7a298136083950a32e62b5b",
    ]

    func testBundledFilesAreDuckbatchsExport() throws {
        for (path, sha) in Self.pinned {
            let name = (path as NSString).deletingPathExtension
            let ext = (path as NSString).pathExtension
            let url = try XCTUnwrap(ModelIntentPlanner.resource(name, ext), path)
            XCTAssertEqual(DuckPolicyInstall.digest(of: try Data(contentsOf: url)), sha, path)
        }
    }

    func testInstructionsLoadAndNameEveryAction() {
        XCTAssertFalse(ModelIntentPlanner.instructions.isEmpty)
        for action in DuckIntentPlan.Vocabulary.actions {
            XCTAssertTrue(ModelIntentPlanner.instructions.contains("- \(action):"), action)
        }
    }

    func testTheCheckSetLoads() {
        XCTAssertEqual(PlannerCheck.requests.count, 30)
        XCTAssertEqual(PlannerCheck.requests.first?.text, "peck the ground three times")
    }

    // MARK: - the reader agrees with duckbatch's, case by case

    private struct Case: Decodable {
        struct S: Decodable, Equatable {
            let skill, speed, head, sound: String
            let seconds: Double
            let `repeat`: Int
        }
        let reply: String
        let steps: [S]?
        let refused: String?
    }

    func testReaderAgreesWithDuckbatchOnEveryCase() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/planner/reader-cases",
                                                  withExtension: "json"))
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(cases.count, 12)
        for c in cases {
            let got = try? ModelIntentPlanner.steps(fromReply: c.reply)
            if let want = c.steps {
                let mine = try XCTUnwrap(got, "Swift refused what Python read: \(c.reply)")
                XCTAssertEqual(mine.map { Case.S(skill: $0.skill, speed: $0.speed, head: $0.head,
                                                  sound: $0.sound, seconds: $0.seconds,
                                                  repeat: $0.repeats) }, want, c.reply)
            } else {
                XCTAssertNil(got, "Swift read what Python refused (\(c.refused ?? "")): \(c.reply)")
            }
        }
    }

    // MARK: - reading into the editor

    func testRepeatsUnrollIntoNodesAndNothingIsFlagged() throws {
        let plan = try ModelIntentPlanner.read(
            reply: #"{"steps": [{"skill": "peck_ground", "repeat": 2}, {"skill": "make_sound", "sound": "none"}]}"#,
            request: "peck twice then make a noise", model: "test")
        XCTAssertEqual(plan.nodes.map(\.action), ["peck_ground", "peck_ground", "make_sound"])
        XCTAssertEqual(plan.nodes.map(\.clause),
                       ["Peck the ground (1 of 2)", "Peck the ground (2 of 2)", "Make a sound"])
        XCTAssertEqual(plan.nodes[2].labels["sound"], "chirp")
        XCTAssertEqual(plan.flaggedCount, 0)
        XCTAssertFalse(plan.nodes[0].measured)
    }

    func testDurationsReachTheRun() throws {
        let plan = try ModelIntentPlanner.read(
            reply: #"{"steps": [{"skill": "walk_forward", "speed": "slow", "seconds": 3}, {"skill": "stop", "seconds": 1}]}"#,
            request: "walk slowly for three seconds then stop", model: "test")
        let run = try plan.run()
        XCTAssertEqual(run.moves.map(\.seconds), [3, 1])
        XCTAssertEqual(run.moves.map(\.go), ["forward", "stop"])
    }

    func testAPlannerIsAnIntentRouter() async throws {
        let planner = ModelIntentPlanner(
            identity: .init(model: "gemma", revision: "test"),
            ask: { instructions, prompt in
                XCTAssertEqual(instructions, ModelIntentPlanner.instructions)
                XCTAssertEqual(prompt, "turn left")
                return "Sure: {\"steps\": [{\"skill\": \"turn_left\"}]}"
            })
        let routing: any IntentRouting = planner
        let plan = try await routing.plan(for: "turn left")
        XCTAssertEqual(plan.nodes.map(\.action), ["turn_left"])
        XCTAssertEqual(plan.model, "gemma")
    }

    func testARefusalIsNamed() {
        XCTAssertThrowsError(try ModelIntentPlanner.steps(fromReply: #"{"steps": [{"skill": "fly"}]}"#)) {
            XCTAssertEqual($0 as? ModelIntentPlanner.ReadError, .unknownLabel("skill", "fly"))
        }
        XCTAssertThrowsError(try ModelIntentPlanner.steps(fromReply: "no idea")) {
            XCTAssertEqual($0 as? ModelIntentPlanner.ReadError, .noJSON)
        }
    }

    // MARK: - the check scores as p002 did

    /// A plan that is the gold itself scores 30/30: the scorer and the set agree.
    func testGoldScoresPerfect() {
        let rows = PlannerCheck.requests.map { request -> PlannerCheck.Row in
            let steps = request.steps.map { s -> [String: Any] in
                var d: [String: Any] = ["skill": s.action, "repeat": s.repeat ?? 1]
                if let v = s.speed { d["speed"] = v }
                if let v = s.head { d["head"] = v }
                if let v = s.sound { d["sound"] = v }
                if let v = s.seconds { d["seconds"] = v }
                return d
            }
            let reply = String(data: try! JSONSerialization.data(withJSONObject: ["steps": steps]),
                               encoding: .utf8)!
            let plan = try? ModelIntentPlanner.read(reply: reply, request: request.text, model: "gold")
            return PlannerCheck.score(request, plan: plan, seconds: 1)
        }
        let summary = PlannerCheck.summarise(rows)
        XCTAssertEqual(summary.sequenceExact, 30)
        XCTAssertEqual(summary.fullyExact, 30)
        XCTAssertEqual(summary.unreadable, 0)
    }

    /// The router's failure modes score as p002 recorded them: a lost repeat
    /// is a wrong sequence, a missing duration is a right sequence but not
    /// fully right, and a refused reply counts as unreadable.
    func testFailuresScoreAsP002Did() throws {
        let set = PlannerCheck.requests
        let peck = try XCTUnwrap(set.first { $0.text == "peck the ground three times" })
        let once = try ModelIntentPlanner.read(reply: #"{"steps":[{"skill":"peck_ground"}]}"#,
                                               request: peck.text, model: "t")
        XCTAssertFalse(PlannerCheck.score(peck, plan: once, seconds: 1).sequenceExact)

        let five = try XCTUnwrap(set.first { $0.text == "walk forward for five seconds" })
        let two = try ModelIntentPlanner.read(reply: #"{"steps":[{"skill":"walk_forward","seconds":2}]}"#,
                                              request: five.text, model: "t")
        let row = PlannerCheck.score(five, plan: two, seconds: 1)
        XCTAssertTrue(row.sequenceExact)
        XCTAssertFalse(row.fullyExact)

        let refused = PlannerCheck.score(five, plan: nil, unreadable: "no JSON", seconds: 1)
        XCTAssertFalse(refused.sequenceExact)
        XCTAssertEqual(PlannerCheck.summarise([row, refused]).unreadable, 1)

        let jump = try XCTUnwrap(set.first { $0.text == "jump over the box" })
        let twice = try ModelIntentPlanner.read(
            reply: #"{"steps":[{"skill":"unsupported"},{"skill":"unsupported"}]}"#,
            request: jump.text, model: "t")
        XCTAssertTrue(PlannerCheck.score(jump, plan: twice, seconds: 1).fullyExact,
                      "consecutive refusals collapse to one, as in p002")
    }
}

extension ModelIntentPlannerTests {
    /// A planner's plan must still become `route_correction` records — the
    /// editor writes them with `try?`, so a refusal here would lose the
    /// person's edits silently.
    func testAPlannersPlanStillBecomesCorrections() throws {
        let plan = try ModelIntentPlanner.read(
            reply: #"{"steps": [{"skill": "sit_or_stand"}, {"skill": "make_sound", "sound": "greet"}]}"#,
            request: "sit down and say hello", model: "Apple on-device")
        let records = try plan.corrections(
            router: .init(model: "Apple on-device", revision: ModelIntentPlanner.promptSource),
            share: .local, client: "test")
        XCTAssertEqual(records.count, 2)
    }
}
