import XCTest
import DuckKit
@testable import StudioKit

/// Dream-1 through the bridge: the lines this app sends, what it reads back, and
/// how `DreamPilot` drives. Pinned against OpenCastor's `castor.microduck_bridge`
/// `DreamVerbs` (tests/test_dream.py there), which answers these verbs.
final class DuckDreamTests: XCTestCase {
    private final class FakeBridge: DuckPeer, @unchecked Sendable {
        let identity = DuckIdentity(name: "Pip", kind: .real)
        let transportKind: DuckTransportKind = .bridge
        let reach = DuckMethod.reach(for: .bridge)
        private let lock = NSLock()
        private var _sent: [String] = []
        var sent: [String] { lock.lock(); defer { lock.unlock() }; return _sent }
        var chunk = #"{"actions":{"per_key":{"action.velocity":[[0.9,0.0,0.2],[0.1,-0.5,-3.0]]}},"session_id":"ses_1"}"#
        var failActs = 0
        var failure = DuckReply.Failure(code: -32000, message: "Dream-1 refused the request: DA-2000 UNAVAILABLE (pool_warming)")

        private func record(_ c: DuckCall) throws {
            let line = String(decoding: try c.line(id: c.isNotification ? nil : 1), as: UTF8.self)
            lock.lock(); _sent.append(line.trimmingCharacters(in: .newlines)); lock.unlock()
        }

        func call(_ c: DuckCall) async throws -> DuckReply {
            try vet(c, asNotification: false)
            try record(c)
            if case .dream(let d) = c, d.verb == .act {
                if failActs > 0 { failActs -= 1; return DuckReply(id: 1, result: nil, failure: failure) }
                return DuckReply(id: 1, result: Data(chunk.utf8), failure: nil)
            }
            return DuckReply(id: 1, result: Data(#"{"ended":true}"#.utf8), failure: nil)
        }

        func notify(_ c: DuckCall) async throws {
            try vet(c, asNotification: true)
            try record(c)
        }

        nonisolated func states() -> AsyncStream<DuckState> { AsyncStream { $0.finish() } }
    }

    private func json(_ line: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: line) as? [String: Any])
    }

    // MARK: - the wire

    func testEachVerbIsSentUnderItsOwnNameNeverTheGlob() throws {
        let set = try json(DuckCall.dream(.keySet("dl_live_abcdefgh1234")).line(id: 2))
        XCTAssertEqual(set["method"] as? String, "dream.key.set")
        let params = try XCTUnwrap(set["params"] as? [String: Any])
        XCTAssertEqual(params["key"] as? String, "dl_live_abcdefgh1234")
        XCTAssertNotNil(params["embodiment"])
        XCTAssertEqual(try json(DuckCall.dream(.end).line(id: 3))["method"] as? String, "dream.end")
        XCTAssertNil(try json(DuckCall.dream(.status).line(id: 4))["params"])
        for verb in DuckDream.Verb.allCases { XCTAssertFalse(verb.rawValue.contains("*")) }
    }

    func testAnActCarriesTheDucksCameraAndTheLastCommand() throws {
        let act = try json(DuckCall.dream(.act(checkpoint: "dream-1-ft:a1b2c3d4-duck", prompt: "walk",
                                                frames: ["head": ["A", "B"]], state: ["velocity": [0.1, 0, 0]],
                                                reset: true)).line(id: 5))
        XCTAssertEqual(act["method"] as? String, "dream.act")
        let p = try XCTUnwrap(act["params"] as? [String: Any])
        XCTAssertEqual(p["checkpoint"] as? String, "dream-1-ft:a1b2c3d4-duck")
        XCTAssertEqual((p["frames"] as? [String: [String]])?["head"], ["A", "B"])
        XCTAssertEqual((p["state"] as? [String: [Double]])?["velocity"], [0.1, 0, 0])
        XCTAssertEqual(p["reset"] as? Bool, true)
    }

    func testTheKeyIsNeverInADescription() {
        let call = DuckDream.keySet("dl_live_secretsecret9876")
        XCTAssertFalse(String(describing: call).contains("secret"))
        XCTAssertFalse(String(reflecting: call).contains("secret"))
        XCTAssertTrue(String(describing: call).contains("9876"))
    }

    func testTheDucksBodyIsOpenCastorsConvention() throws {
        // castor.dream.MICRODUCK_EMBODIMENT, byte for byte in meaning.
        let data = try JSONSerialization.data(withJSONObject: DuckDream.microduck, options: [.sortedKeys])
        XCTAssertEqual(String(decoding: data, as: UTF8.self),
                       #"{"action":{"velocity":[0,3]},"state":{"velocity":[0,3]},"video":{"head":"observation.images.head"}}"#)
    }

    func testOnlyTheBridgeCarriesDream() {
        XCTAssertTrue(DuckMethod.reach(for: .bridge).contains(.dream))
        for t in [DuckTransportKind.ble, .webRTC, .bench] { XCTAssertFalse(DuckMethod.reach(for: t).contains(.dream)) }
        XCTAssertNotNil(BenchPeer.refusal(for: .dream(.status)))
    }

    func testAPastedKeyIsCleanedTheBridgesWay() {
        XCTAssertEqual(try DuckDream.cleaned("  dl_live_abc \n").get(), "dl_live_abc")
        XCTAssertThrowsError(try DuckDream.cleaned("dl_live_abc\u{201D}").get())
        XCTAssertThrowsError(try DuckDream.cleaned("   ").get())
    }

    func testTheGreetingSaysWhetherTheBridgeAnswersDream() throws {
        let on = try BridgeHandshake.read(Data(#"{"microduck":"v1","bridge":"microduck-bridge/1","deadman_ms":300,"policy_install":false,"dream":true}"#.utf8))
        XCTAssertTrue(on.answersDream)
        let old = try BridgeHandshake.read(Data(#"{"microduck":"v1","bridge":"microduck-bridge/1","deadman_ms":300}"#.utf8))
        XCTAssertFalse(old.answersDream)
    }

    // MARK: - what comes back

    func testOnlyRunnableDuckModelsAreOffered() throws {
        let body = #"{"key":"...c3d4","models":[{"id":"dreamlabs/dream-1-beta","owner":"public","servable":true,"fits":false},{"id":"dream-1-ft:a-duck","owner":"mine","servable":true,"fits":true},{"id":"dream-1-ft:a-wip","owner":"mine","servable":false,"fits":true}]}"#
        let answer = try DuckDream.readKey(DuckReply(id: 1, result: Data(body.utf8), failure: nil))
        XCTAssertEqual(answer.key, "...c3d4")
        XCTAssertEqual(answer.duckModels.map(\.id), ["dream-1-ft:a-duck"])
    }

    func testAChunkWithABadRowIsRefusedWhole() {
        let bad = #"{"actions":{"per_key":{"action.velocity":[[0.1,0,0],[0.1,0]]}}}"#
        XCTAssertThrowsError(try DuckDream.readChunk(DuckReply(id: 1, result: Data(bad.utf8), failure: nil)))
    }

    func testRowsAreClampedToTheSticks() {
        let t = DreamPilot.clamped(DuckDrive.Twist(vx: 2, vy: -2, vyaw: 9))
        XCTAssertEqual(t, DuckDrive.Twist(vx: DuckDrive.maxForward, vy: -DuckDrive.maxSideways, vyaw: DuckDrive.maxTurn))
    }

    // MARK: - the pilot

    private static func twist(_ line: String) -> [Double] {
        let top = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        let p = top?["params"] as? [String: Any] ?? [:]
        return ["vx", "vy", "vyaw"].map { (p[$0] as? NSNumber)?.doubleValue ?? .nan }
    }

    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var t = Date(timeIntervalSince1970: 0)
        func now() -> Date { lock.lock(); defer { lock.unlock() }; return t }
        func advance(_ s: TimeInterval) { lock.lock(); t += s; lock.unlock() }
    }

    private final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var _all: [DreamPilot.Event] = []
        var all: [DreamPilot.Event] { lock.lock(); defer { lock.unlock() }; return _all }
        func add(_ e: DreamPilot.Event) { lock.lock(); _all.append(e); lock.unlock() }
    }

    func testThePilotPlaysClampedRowsThenStopsAndEnds() async {
        let duck = FakeBridge()
        let clock = Clock(), events = Events()
        await DreamPilot(checkpoint: "m", prompt: "walk", limit: 0.35)
            .run(on: duck, frames: { ["F"] }, events: { events.add($0) },
                 sleep: { clock.advance($0) }, now: { clock.now() })
        let sent = duck.sent
        XCTAssertTrue(sent.first?.contains(#""method":"dream.act""#) == true)
        XCTAssertTrue(sent.first?.contains(#""reset":true"#) == true)
        let moves = sent.filter { $0.contains("robot.move") }.map(Self.twist)
        XCTAssertEqual(moves.first, [DuckDrive.maxForward, 0, 0.2])   // 0.9 clamped to the sticks
        XCTAssertEqual(moves.dropFirst().first, [0.1, -DuckDrive.maxSideways, -DuckDrive.maxTurn])
        // The last two lines, always and in this order: stop the duck, then give the seat back.
        XCTAssertEqual(Array(sent.suffix(2).map { $0.contains("robot.stop") || $0.contains("dream.end") }), [true, true])
        XCTAssertTrue(sent.suffix(2).first!.contains("robot.stop"))
        XCTAssertEqual(events.all.last, .ended(DuckDream.Words.timeUp))
    }

    func testTheSecondAskSendsWhatWasLastCommandedAndNoReset() async {
        let duck = FakeBridge()
        let clock = Clock()
        await DreamPilot(checkpoint: "m", prompt: "walk", limit: 0.25)
            .run(on: duck, frames: { ["F"] }, events: { _ in },
                 sleep: { clock.advance($0) }, now: { clock.now() })
        let acts = duck.sent.filter { $0.contains("dream.act") }
        XCTAssertGreaterThanOrEqual(acts.count, 2)
        XCTAssertTrue(acts[1].contains(#""reset":false"#))
        let p = try? JSONSerialization.jsonObject(with: Data(acts[1].utf8)) as? [String: Any]
        let state = (p?["params"] as? [String: Any])?["state"] as? [String: [Double]]
        XCTAssertEqual(state?["velocity"], [0.1, -DuckDrive.maxSideways, -DuckDrive.maxTurn])
    }

    func testAStartingModelIsWaitedForStandingStill() async {
        let duck = FakeBridge()
        duck.failActs = 1
        let clock = Clock(), events = Events()
        await DreamPilot(checkpoint: "m", prompt: "walk", limit: 11)
            .run(on: duck, frames: { ["F"] }, events: { events.add($0) },
                 sleep: { clock.advance($0) }, now: { clock.now() })
        XCTAssertTrue(events.all.contains(.waiting(DuckDream.Words.warming)))
        let sent = duck.sent
        XCTAssertTrue(sent[1].contains("robot.stop"), "held still while the model starts")
        XCTAssertTrue(sent.contains { $0.contains("robot.move") })
    }

    func testARefusalStopsTheDuckAndSaysWhy() async {
        let duck = FakeBridge()
        duck.failActs = 99
        duck.failure = DuckReply.Failure(code: -32602, message: "no Dream Labs key is saved on this robot; send dream.key.set first")
        let events = Events()
        await DreamPilot(checkpoint: "m", prompt: "walk")
            .run(on: duck, frames: { ["F"] }, events: { events.add($0) }, sleep: { _ in })
        XCTAssertFalse(duck.sent.contains { $0.contains("robot.move") })
        XCTAssertTrue(duck.sent.suffix(2).first!.contains("robot.stop"))
        XCTAssertEqual(events.all.last, .ended("no Dream Labs key is saved on this robot; send dream.key.set first"))
    }

    func testNoCameraNoAsk() async {
        let duck = FakeBridge()
        let events = Events()
        await DreamPilot(checkpoint: "m", prompt: "walk")
            .run(on: duck, frames: { [] }, events: { events.add($0) }, sleep: { _ in })
        XCTAssertFalse(duck.sent.contains { $0.contains("dream.act") })
        XCTAssertEqual(events.all.last, .ended(DuckDream.Words.needsCamera))
    }
}
