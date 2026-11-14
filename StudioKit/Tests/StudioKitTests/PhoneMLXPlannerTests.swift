import XCTest
@testable import StudioKit

/// The on-phone MLX planner with its runner stubbed: the same constrained prompt and the same
/// strict reading as the LAN planner, held on Linux.
final class PhoneMLXPlannerTests: XCTestCase {
    typealias F = LocalFixtures
    static let repo = "mlx-community/Qwen3-1.7B-4bit"
    static let version = LocalModelVersion.huggingFace(repository: repo, snapshots: ["0123456789abcdef0123456789abcdef01234567"])

    func planner(deadline: Duration = PhoneMLXPlanner.decisionDeadline,
                 _ answer: @escaping @Sendable (StubRunner.Seen) async throws -> String) -> PhoneMLXPlanner {
        PhoneMLXPlanner(repository: Self.repo, version: Self.version, runner: StubRunner(answer: answer), deadline: deadline)
    }

    func testTheRunnerIsAskedWithTheShortListAndTheDeadline() async throws {
        let seen = LockedBox<StubRunner.Seen?>(nil)
        let p = planner { s in seen.value = s; return F.walk }
        let d = try await p.decide(F.ask(F.real))
        XCTAssertEqual(d.decision, .walk(forwardM: 0.5, sideM: 0))
        XCTAssertEqual(d.why, "the ball is ahead")
        let s = try XCTUnwrap(seen.value)
        XCTAssertEqual(s.repository, Self.repo)
        XCTAssertEqual(s.deadline, 10, accuracy: 0.001)
        XCTAssertTrue(s.instructions.contains("one of: sit, stand"))
        XCTAssertTrue(s.instructions.contains("Answer with one JSON object"))
        XCTAssertTrue(s.prompt.hasPrefix("Goal: walk to the ball"))
        XCTAssertEqual(d.provider.modelVersion, "mlx-community/Qwen3-1.7B-4bit@0123456789ab 4bit")
    }

    func testInfo() {
        let p = planner { _ in "" }
        XCTAssertEqual(p.info.id, "phone.mlx-community/Qwen3-1.7B-4bit")
        XCTAssertEqual(p.info.runsOn, .thisPhone)
        XCTAssertEqual(p.info.key, .none)
        XCTAssertEqual(p.info.framesSent, .none)
        XCTAssertEqual(p.info.label, "Local model on \(DeviceWords.current.this)")
        XCTAssertNil(p.info.evidence)
    }

    func testOutOfSetAndMalformedBecomeAsk() async throws {
        let skill = try await planner { _ in #"{"kind":"skill","name":"sit","why":"x"}"# }.decideWithReading(F.ask())
        XCTAssertEqual(skill.refusal, .kindNotAllowed(.skill))
        XCTAssertEqual(skill.decided.decision.kind, .ask)
        let prose = try await planner { _ in "Walk forward." }.decideWithReading(F.ask())
        XCTAssertEqual(prose.refusal, .notADecision)
        let thinkThenAnswer = try await planner { _ in "<think>left? no</think>" + F.walk }.decide(F.ask())
        XCTAssertEqual(thinkThenAnswer.decision, .walk(forwardM: 0.5, sideM: 0))
    }

    func testEmptyAndScratchpadOnlyAreRefused() async {
        await LocalPlannerTests.assertThrows(.emptyReply) { _ = try await self.planner { _ in "" }.decide(F.ask()) }
        await LocalPlannerTests.assertThrows(.spentItAllThinking) {
            _ = try await self.planner { _ in "<think>the ball, the ball" }.decide(F.ask())
        }
    }

    func testTheDeadlineStopsASlowModel() async {
        let p = planner(deadline: .milliseconds(100)) { _ in try await Task.sleep(for: .seconds(10)); return F.walk }
        let start = ContinuousClock.now
        await LocalPlannerTests.assertThrows(.timedOut(seconds: 1)) { _ = try await p.decide(F.ask()) }
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(3))
    }

    func testRunnerFailuresAreScrubbedAndPassedThrough() async {
        struct Boom: Error, CustomStringConvertible { var description: String }
        let key = "hf_" + String(repeating: "Fake", count: 6)
        let p = planner { _ in throw Boom(description: "download failed with token " + key) }
        do {
            _ = try await p.decide(F.ask())
            XCTFail("did not throw")
        } catch let e as LocalPlannerError {
            guard case .runnerFailed(let text) = e else { return XCTFail("\(e)") }
            XCTAssertFalse(text.contains(key))
            XCTAssertFalse(KeyScrub.containsKey(e.says))
        } catch { XCTFail("\(error)") }
        let own = planner { _ in throw LocalPlannerError.runnerFailed("Models do not run in the Simulator.") }
        await LocalPlannerTests.assertThrows(.runnerFailed("Models do not run in the Simulator.")) { _ = try await own.decide(F.ask()) }
    }

    func testOnlyADownloadedEndpointMakesOne() throws {
        let runner = StubRunner { _ in "" }
        let mlx = ModelEndpoint(name: "Qwen", kind: .downloadedMLX, model: Self.repo)
        XCTAssertEqual(try PhoneMLXPlanner(endpoint: mlx, version: Self.version, runner: runner).repository, Self.repo)
        XCTAssertThrowsError(try PhoneMLXPlanner(endpoint: F.endpoint(), version: Self.version, runner: runner))
    }
}
