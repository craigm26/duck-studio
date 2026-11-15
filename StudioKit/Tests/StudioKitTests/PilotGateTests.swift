import XCTest
import DuckKit
@testable import StudioKit

/// `DreamPilot`'s gate is required, and the ungated runs are a closed, named list (build 91,
/// brains-layer.md 6.2). These read the sources, as `MCPBoundaryTests` and `StopPathTests` do.
final class PilotGateTests: XCTestCase {

    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// Every Swift source in the kit and the app, with its path from the repo root.
    static func sources() throws -> [(String, String)] {
        var out: [(String, String)] = []
        for dir in ["StudioKit/Sources", "DuckStudio/Sources"] {
            let root = repo.appendingPathComponent(dir)
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                out.append((dir + "/" + url.path.dropFirst(root.path.count + 1), try String(contentsOf: url, encoding: .utf8)))
            }
        }
        return out
    }

    /// The callers allowed to run a pilot ungated, each with its reason.
    static let exempt: [String: PilotGate.Exemption] = [
        "StudioKit/Sources/StudioKit/DriverTrial.swift": .benchMeasurement,
        "DuckStudio/Sources/DreamRunView.swift": .appRunNotYetWired,
    ]

    func testOnlyTheListedCallersRunAPilotUngated() throws {
        let all = try Self.sources()
        XCTAssertGreaterThan(all.count, 50, "the sources were found")
        for (path, text) in all where text.contains(".exempt(.") && !path.hasSuffix("DuckDream.swift") {
            let reason = try XCTUnwrap(Self.exempt[path], "\(path) runs a pilot ungated and is not on the list")
            XCTAssertTrue(text.contains(".exempt(.\(String(describing: reason)))"), path)
        }
    }

    func testTheKitsOwnRunnersAlwaysEnforceTheGate() throws {
        for name in ["BrainRunner.swift", "PlannerLeg.swift"] {
            let text = try String(contentsOf: Self.repo.appendingPathComponent("StudioKit/Sources/StudioKit/\(name)"),
                                  encoding: .utf8)
            XCTAssertFalse(text.contains(".exempt("), "\(name) must never run a pilot ungated")
        }
        let leg = try String(contentsOf: Self.repo.appendingPathComponent("StudioKit/Sources/StudioKit/PlannerLeg.swift"),
                             encoding: .utf8)
        XCTAssertTrue(leg.contains("gate: .enforced("))
    }

    func testThePilotHasNoUngatedDefault() throws {
        let text = try String(contentsOf: Self.repo.appendingPathComponent("StudioKit/Sources/StudioKit/DuckDream.swift"),
                              encoding: .utf8)
        XCTAssertTrue(text.contains("                    gate: PilotGate) async {"), "required, with no default")
        XCTAssertFalse(text.contains("filter: (@Sendable"), "the old optional filter is gone")
    }

    func testTheExemptionsAreTheTwoNamedCallers() {
        XCTAssertEqual(Set(PilotGate.Exemption.allCases), [.benchMeasurement, .appRunNotYetWired])
        XCTAssertFalse(PilotGate.exempt(.benchMeasurement).isEnforced)
    }

    func testTheLatchLetsOnlyStopAndReadsThrough() {
        let passes: [DuckCall] = [.stop, .hello, .state, .subscribe(hz: nil), .skills, .policies,
                                  .dream(.end), .dream(.status), .dream(.keyCheck), .dream(.keyClear)]
        let refused: [DuckCall] = [.move(.still), .move(DuckDrive.Twist(vx: 0.1, vy: 0, vyaw: 0)), .enable, .initPose,
                                   .relax, .doSkill("kick_left"), .sound(.chirp),
                                   .dream(.act(checkpoint: "m", prompt: "p", frames: [:], state: [:], reset: true))]
        for c in passes { XCTAssertTrue(LatchedPeer.passesWhileLatched(c), "\(c)") }
        for c in refused { XCTAssertFalse(LatchedPeer.passesWhileLatched(c), "\(c)") }
    }

    static let fresh = PlannerLeg.Reading(odomAgeMs: 20, pose: .init(x: 0, y: 0, yaw: 0))

    // MARK: the gate bound in DreamPilot

    /// Required (build 91): `act()` before `bind()` throws, and a pilot with an unbound gate moves
    /// nothing and asks nothing.
    func testActBeforeBindThrowsAndAnUnboundPilotMovesNothing() async {
        var gate = DuckEnvelopeGate()
        XCTAssertThrowsError(try gate.act(.init(t: 0, twist: .still, odomAgeMs: 10, pose: nil))) {
            XCTAssertEqual($0 as? DuckEnvelopeGate.GateError, .notBound)
        }
        let duck = ControllerDuck(), clock = ControllerClock()
        final class Asked: DreamRows, @unchecked Sendable {
            var acts = 0
            func act(checkpoint: String, prompt: String, frames: [String: [String]],
                     state: [String: [Double]], reset: Bool) async throws -> DuckDream.Chunk {
                acts += 1
                return DuckDream.Chunk(rows: [DuckDrive.Twist(vx: 0.3, vy: 0, vyaw: 0)], sessionID: nil)
            }
            func end() async {}
        }
        let rows = Asked()
        let ended = Ended()
        await DreamPilot(checkpoint: "m", prompt: "walk", limit: 1)
            .run(on: duck, rows: rows, frames: { ["F"] }, events: { if case .ended(let s) = $0 { ended.set(s) } },
                 sleep: { clock.advance($0) }, now: { clock.now() },
                 gate: .enforced(GateHolder(DuckEnvelopeGate()), reading: { PilotGateTests.fresh }, runStart: clock.now()))
        XCTAssertEqual(rows.acts, 0, "nothing asked")
        XCTAssertEqual(duck.moves, 0, "nothing moved")
        XCTAssertEqual(ended.said, PlannerLeg.Words.gateNotBound)
    }

    final class Ended: @unchecked Sendable {
        private let lock = NSLock(); private var s: String?
        func set(_ v: String) { lock.withLock { s = v } }
        var said: String? { lock.lock(); defer { lock.unlock() }; return s }
    }

    func testTheEnforcedGateShapesEveryRowOnBothVenues() async {
        for venue in BrainVenue.allCases {
            let duck = ControllerDuck(), clock = ControllerClock()
            var g = DuckEnvelopeGate()
            g.bind(.init(providerId: "phone.ducknet-s1", modelVersion: "s1", venue: venue, mode: .auto, remote: false,
                         allowed: AllowedDecisions(kinds: [.walk])))
            let holder = GateHolder(g)
            await DreamPilot(checkpoint: "m", prompt: "walk", limit: 0.5)
                .run(on: duck, rows: StillThenFast(), frames: { ["F"] }, events: { _ in },
                     sleep: { clock.advance($0) }, now: { clock.now() },
                     gate: .enforced(holder, reading: { PilotGateTests.fresh }, runStart: clock.now()))
            let first = duck.moving.first
            XCTAssertEqual(first?.vx ?? 0, 0.1, accuracy: 1e-9, "\(venue): the rate rule eased the first row in")
            let after = await holder.gate
            XCTAssertGreaterThan(after.stats.counts[.rate] ?? 0, 0, "\(venue): counted")
            XCTAssertTrue(after.events.contains { $0.phase == "wait" }, "\(venue): the WAIT row is logged")
        }
    }

    final class StillThenFast: DreamRows, @unchecked Sendable {
        func act(checkpoint: String, prompt: String, frames: [String: [String]],
                 state: [String: [Double]], reset: Bool) async throws -> DuckDream.Chunk {
            DuckDream.Chunk(rows: Array(repeating: DuckDrive.Twist(vx: 0.3, vy: 0, vyaw: 0), count: 48), sessionID: nil)
        }
        func end() async {}
    }

    /// Required (build 91): `.move` is refused after `.stop` until re-arm.
    func testMoveIsRefusedAfterStopUntilRearm() async throws {
        let duck = ControllerDuck()
        let stopPath = StopPath(peer: duck)
        let peer = LatchedPeer(duck, latch: stopPath)
        try await peer.notify(.move(DuckDrive.Twist(vx: 0.1, vy: 0, vyaw: 0)))
        stopPath.stop()
        for twist in [DuckDrive.Twist(vx: 0.1, vy: 0, vyaw: 0), .still] {
            do {
                try await peer.notify(.move(twist))
                XCTFail("a move after a stop must be refused")
            } catch {
                XCTAssertEqual(error as? LatchedPeer.Refused, .latched(.move))
            }
        }
        for c in [DuckCall.doSkill("kick_left"), .enable, .initPose, .sound(.chirp)] {
            do { _ = try await peer.call(c); XCTFail("\(c) after a stop") } catch {
                XCTAssertNotNil(error as? LatchedPeer.Refused)
            }
        }
        _ = try await peer.call(.stop)
        _ = try await peer.call(.skills)
        XCTAssertEqual(duck.moving.count, 1, "only the move before the stop reached the duck")
        stopPath.rearm()
        try await peer.notify(.move(DuckDrive.Twist(vx: 0.2, vy: 0, vyaw: 0)))
        XCTAssertEqual(duck.moving.last?.vx, 0.2, "a person's re-arm opens it")
    }
}
