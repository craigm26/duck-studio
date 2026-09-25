import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import DuckKit
@testable import StudioKit

/// The cross is the point: each walker runs on each duck, the record names the
/// network and never the duck, and consistency across the swap is counted the
/// way the design pre-registered it.
final class MultiDuckTests: XCTestCase {

    private let a = MultiDuck.Walker(benchName: "alpha_walking.onnx", title: "Pollen walker",
        identity: .init(repo: "pollen-robotics/microduck-policies", file: "alpha_walking.onnx",
                        fingerprint: "sha256:aa"))
    private let b = MultiDuck.Walker(benchName: "uploaded-1.onnx", title: "Student",
        identity: .init(repo: "craigm26/microduck-duckbatch-b002-128x128", fingerprint: "sha256:bb"))
    private let address = DuckBench.Address(host: "127.0.0.1", port: 8799)

    private func pair() throws -> MultiDuck.Pair {
        try MultiDuck.Pair(ducks: ["huey", "dewey"], a: a, b: b, command: MultiDuck.commands[0],
                           id: UUID(uuidString: "11111111-2222-4333-8444-555555555555")!)
    }

    // MARK: - setting up

    func testAPairNeedsTwoDucksAndTwoDifferentNetworks() {
        XCTAssertThrowsError(try MultiDuck.Pair(ducks: ["duck"], a: a, b: b, command: MultiDuck.commands[0])) {
            XCTAssertEqual($0 as? MultiDuck.Refusal, .needTwoDucks(1))
        }
        XCTAssertThrowsError(try MultiDuck.Pair(ducks: ["huey", "dewey"], a: a, b: a,
                                                command: MultiDuck.commands[0])) {
            XCTAssertEqual($0 as? MultiDuck.Refusal, .sameWalker)
        }
    }

    func testTheWalkersSwapDucksBetweenTheTwoRuns() throws {
        let p = try pair()
        XCTAssertEqual(p.assignment(run: 1).first, a)
        XCTAssertEqual(p.assignment(run: 1).second, b)
        XCTAssertEqual(p.assignment(run: 2).first, b)
        XCTAssertEqual(p.assignment(run: 2).second, a)
    }

    func testSetUpLoadsEachDucksWalkerByNameAndResetsBoth() throws {
        let calls = try MultiDuck.setUp(try pair(), run: 2, at: address)
        let bodies = calls.map { String(decoding: $0.body ?? Data(), as: UTF8.self) }
        XCTAssertTrue(bodies[0].contains(#""duck":"huey""#) && bodies[0].contains("uploaded-1.onnx"),
                      "run 2 puts walker B on the first duck")
        XCTAssertTrue(bodies[1].contains(#""duck":"dewey""#) && bodies[1].contains("alpha_walking.onnx"))
        XCTAssertEqual(calls.map { $0.url.lastPathComponent }, ["policy", "policy", "reset", "reset"])
    }

    func testEveryCommandOfferedIsAboveTheWalkersDeadBandOrIsStanding() {
        for c in MultiDuck.commands {
            let moving = abs(c.twist.vx) > 0 || abs(c.twist.vyaw) > 0
            if moving {
                XCTAssertTrue(c.twist.vx == 0 || c.twist.vx >= 0.25,
                              "\(c.name): alpha_walking does not walk at 0.20 m/s (measured)")
            }
            XCTAssertLessThanOrEqual(c.seconds, MultiDuck.maxSeconds)
        }
    }

    func testARunIsEnoughTicksToCoverItsSeconds() {
        XCTAssertEqual(MultiDuck.ticks(for: MultiDuck.commands[0]), 75, "6 s at 2 × 0.04 s a tick")
    }

    // MARK: - the answer

    func testPickingTheTopDuckRecordsTheWalkerThatWasOnItInThatRun() throws {
        let p = try pair()
        let run1 = try MultiDuck.record(.left, reasons: [], pair: p, run: 1, share: .local, client: "t").jsonLine()
        let run2 = try MultiDuck.record(.left, reasons: [], pair: p, run: 2, share: .local, client: "t").jsonLine()
        XCTAssertTrue(run1.contains(#""choice":"a""#) && run1.contains(#""order":"a_left""#))
        XCTAssertTrue(run2.contains(#""choice":"b""#) && run2.contains(#""order":"b_left""#))
        XCTAssertTrue(run1.contains("multi/11111111-2222-4333-8444-555555555555/run1"))
        XCTAssertFalse(run1.contains("huey") || run1.contains("dewey"), "no duck's name in a record")
    }

    func testConsistencyIsTheSameWalkerAcrossTheSwapAndTiesSayNothing() {
        XCTAssertEqual(MultiDuck.consistent(run1: .left, run2: .right), true, "a both times")
        XCTAssertEqual(MultiDuck.consistent(run1: .left, run2: .left), false, "the top duck both times")
        XCTAssertNil(MultiDuck.consistent(run1: .tie, run2: .right))
    }

    func testPlaybackHoldsTheLastFrame() {
        var r = MultiDuck.Recording()
        let s = DuckStance.home
        r.append(first: s, second: s)
        r.append(first: s, second: s)
        XCTAssertEqual(r.duration, MultiDuck.Recording.frameSeconds, accuracy: 1e-12)
        XCTAssertEqual(r.stances(at: 99).first, s)
    }

    // MARK: - against a real two-duck bench, when there is one

    /// `DUCK_MULTI_BENCH=127.0.0.1:8799 swift test --filter MultiDuckTests`, against
    /// `DUCKBENCH_SCENE=scene_multiduck.mjb DUCKBENCH_PORT=8799 node duckbench.mjs`.
    func testACrossedRunDrivesBothDucksOnTheLiveBench() async throws {
        guard let text = ProcessInfo.processInfo.environment["DUCK_MULTI_BENCH"] else { return }
        let address = try DuckBench.address(text)
        func send(_ call: DuckBench.Call) async throws -> Data {
            try await URLSession.shared.data(for: DuckBench.urlRequest(for: call)).0
        }
        let health = try DuckBench.readHealth(try await send(DuckBench.health(address)))
        XCTAssertEqual(health.ducks, ["huey", "dewey"])
        let walker = MultiDuck.Walker(benchName: "alpha_walking.onnx", title: "walk",
                                      identity: .init(repo: "x", fingerprint: "sha256:aa"))
        let stander = MultiDuck.Walker(benchName: "alpha_stand.onnx", title: "stand",
                                       identity: .init(repo: "x", fingerprint: "sha256:bb"))
        let p = try MultiDuck.Pair(ducks: health.ducks, a: walker, b: stander, command: MultiDuck.commands[0])
        for run in 1...2 {
            for call in try MultiDuck.setUp(p, run: run, at: address) { _ = try await send(call) }
            var recording = MultiDuck.Recording()
            for _ in 0..<MultiDuck.ticks(for: p.command) {
                let calls = try MultiDuck.tick(p, at: address)
                let first = try DuckDrive.readLive(try await send(calls[0]))
                let second = try DuckDrive.readLive(try await send(calls[1]))
                recording.append(first: first.stance, second: second.stance)
            }
            let end = recording.stances(at: recording.duration)
            let walked = run == 1 ? end.first.root.x : end.second.root.x
            let stood = run == 1 ? end.second.root.x : end.first.root.x
            XCTAssertGreaterThan(walked, stood + 0.2,
                                 "run \(run): the walker's duck went further than the stander's")
        }
    }
}
