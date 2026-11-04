import XCTest
import DuckKit
@testable import StudioKit

/// A phone driver behind the same seam as Dream-1: the pilot drives with it unchanged.
final class LocalDreamRowsTests: XCTestCase {
    final class FakeNet: DriverNet, @unchecked Sendable {
        private let lock = NSLock()
        private var _calls = 0
        var calls: Int { lock.lock(); defer { lock.unlock() }; return _calls }
        var output: [Float] = Array(repeating: 0, count: 144)
        var onInfer: () -> Void = {}
        var fails = false
        func infer(_ input: DriverInput) throws -> [Float] {
            lock.lock(); _calls += 1; lock.unlock()
            onInfer()
            if fails { throw DuckNetS1.Problem.input(0) }
            return output
        }
    }

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var t = 0.0
        func now() -> Double { lock.lock(); defer { lock.unlock() }; return t }
        func date() -> Date { Date(timeIntervalSince1970: now()) }
        func advance(_ s: Double) { lock.lock(); t += s; lock.unlock() }
    }

    private final class Link: DuckPeer, @unchecked Sendable {
        let identity = DuckIdentity(name: "Sim", kind: .real)
        let transportKind: DuckTransportKind = .bridge
        let reach = DuckMethod.reach(for: .bridge).subtracting([.dream])
        private let lock = NSLock()
        private var _sent: [String] = []
        var sent: [String] { lock.lock(); defer { lock.unlock() }; return _sent }
        func call(_ c: DuckCall) async throws -> DuckReply {
            try vet(c, asNotification: false)
            lock.lock(); _sent.append(c.method.rawValue); lock.unlock()
            return DuckReply(id: 1, result: Data(#"{"accepted":true}"#.utf8), failure: nil)
        }
        func notify(_ c: DuckCall) async throws {
            try vet(c, asNotification: true)
            lock.lock(); _sent.append(c.method.rawValue); lock.unlock()
        }
        nonisolated func states() -> AsyncStream<DuckState> { AsyncStream { $0.finish() } }
    }

    private let manifest = try! DriverManifest.read(DriverFilesTests.manifest())
    private let picture = [UInt8](repeating: 128, count: 320 * 176 * 3)

    private func rows(_ net: FakeNet, clock: Clock = Clock(), deadline: Double = 1, hot: Bool = false,
                      decodes: Bool = true) -> LocalDreamRows {
        let pic = picture
        return LocalDreamRows(net: net, manifest: manifest, modelID: "driver@abc",
                              decode: { _ in decodes ? pic : nil }, now: { clock.now() },
                              deadline: deadline, tooHot: { hot })
    }

    private func refusal(_ source: LocalDreamRows, checkpoint: String = "driver@abc",
                         frames: [String: [String]] = ["head": ["J"]]) async -> String? {
        do {
            _ = try await source.act(checkpoint: checkpoint, prompt: "x", frames: frames, state: [:], reset: true)
            return nil
        } catch let e as DuckDream.ReadError { return e.message } catch { return "\(error)" }
    }

    func testItAnswers48UnNormalisedRows() async throws {
        let net = FakeNet()
        net.output[0] = 1          // vx row 0: 1 * 0.2 + 0.1
        let chunk = try await rows(net).act(checkpoint: "driver@abc", prompt: "ignored", frames: ["head": ["J", "J"]],
                                            state: [:], reset: true)
        XCTAssertEqual(chunk.rows.count, 48)
        XCTAssertEqual(chunk.rows[0].vx, 0.3, accuracy: 1e-6)
        XCTAssertNil(chunk.sessionID)
    }

    func testEachRefusalIsNamedAndTheNetIsNotAskedNeedlessly() async {
        let net = FakeNet()
        let wrong = await refusal(rows(net), checkpoint: "other")
        XCTAssertEqual(wrong, DuckDream.Words.notThisDriver)
        let hot = await refusal(rows(net, hot: true))
        XCTAssertEqual(hot, DuckDream.Words.tooHot)
        let empty = await refusal(rows(net), frames: [:])
        XCTAssertEqual(empty, DuckDream.Words.noPicture)
        let undecodable = await refusal(rows(net, decodes: false))
        XCTAssertEqual(undecodable, DuckDream.Words.noPicture)
        XCTAssertEqual(net.calls, 0, "nothing reached the network")
        net.fails = true
        let failed = await refusal(rows(net))
        XCTAssertEqual(failed, DuckDream.Words.driverFailed)
        net.fails = false
        net.output[4] = .nan
        let nan = await refusal(rows(net))
        XCTAssertEqual(nan, DuckDream.Words.driverFailed)
    }

    func testASlowAnswerIsRefusedNotPlayed() async {
        let net = FakeNet(), clock = Clock()
        net.onInfer = { clock.advance(1.2) }
        let slow = await refusal(rows(net, clock: clock))
        XCTAssertEqual(slow, DuckDream.Words.tooSlow(1200))
    }

    func testTimingsAreMedianAndNinetyFifth() async throws {
        let net = FakeNet(), clock = Clock()
        var step = 0.0
        net.onInfer = { step += 0.001; clock.advance(step) }
        let source = rows(net, clock: clock)
        for _ in 0..<20 {
            _ = try await source.act(checkpoint: "driver@abc", prompt: "", frames: ["head": ["J"]], state: [:], reset: false)
        }
        let t = await source.timings()
        XCTAssertEqual(t?.p50, 11)
        XCTAssertEqual(t?.p95, 19)
    }

    func testThePilotDrivesWithAPhoneDriverAndEndsWithAStop() async {
        let net = FakeNet(), clock = Clock(), duck = Link()
        net.output = (0..<144).map { $0 % 3 == 0 ? 1 : 0 }      // forward 0.3 every row
        await DreamPilot(checkpoint: "driver@abc", prompt: "walk to the ball", limit: 2.5)
            .run(on: duck, rows: rows(net, clock: clock), frames: { ["J", "J", "J"] }, events: { _ in },
                 sleep: { clock.advance($0) }, now: { clock.date() })
        let moves = duck.sent.filter { $0 == "robot.move" }.count
        XCTAssertEqual(moves, 25, "two and a half seconds of rows at 10 Hz")
        XCTAssertEqual(net.calls, 2, "one ask per 20 rows")
        XCTAssertEqual(duck.sent.last, "robot.stop")
    }

    // MARK: - which source, which models

    private let cloud = DuckDream.Model(id: "dream-1-ft:x-duck", owner: "mine", servable: true, fits: true)
    private let phone = DuckDream.Model(id: "driver@abc", owner: "phone", servable: true, fits: true,
                                        kind: .phone, title: "walk to the ball")

    func testPhoneDriversComeFirstAndOnlyOnTheSimulatedDuck() {
        XCTAssertEqual(DreamSourceChoice.merge(cloud: [cloud], phone: [phone], isSimDuck: true), [phone, cloud])
        XCTAssertEqual(DreamSourceChoice.merge(cloud: [cloud], phone: [phone], isSimDuck: false), [cloud])
        XCTAssertEqual(DreamSourceChoice.merge(cloud: [], phone: [phone], isSimDuck: true), [phone],
                       "no key no longer means no list")
        XCTAssertEqual(phone.label, "On this phone: walk to the ball")
        XCTAssertEqual(cloud.label, "dream-1-ft:x-duck")
    }

    func testTheChosenModelPicksTheSource() {
        XCTAssertEqual(DreamSourceChoice.pick(chosen: phone, hasKey: false, bridgeAnswersDream: false, isSimDuck: true), .phone)
        XCTAssertEqual(DreamSourceChoice.pick(chosen: phone, hasKey: true, bridgeAnswersDream: true, isSimDuck: false), .none)
        XCTAssertEqual(DreamSourceChoice.pick(chosen: cloud, hasKey: true, bridgeAnswersDream: true, isSimDuck: true), .direct)
        XCTAssertEqual(DreamSourceChoice.pick(chosen: cloud, hasKey: false, bridgeAnswersDream: true, isSimDuck: false), .bridge)
        XCTAssertEqual(DreamSourceChoice.pick(chosen: cloud, hasKey: false, bridgeAnswersDream: false, isSimDuck: true), .none)
        XCTAssertEqual(DreamSourceChoice.pick(chosen: nil, hasKey: true, bridgeAnswersDream: true, isSimDuck: true), .none)
    }

    func testTheNewWordsHaveNoEmDashes() {
        for line in [DuckDream.Words.oneJob("walk to the ball"), DuckDream.Words.drivingAs("x"), DuckDream.Words.tooSlow(5),
                     DuckDream.Words.tooHot, DuckDream.Words.simOnly, DuckDream.Words.noPicture,
                     DuckDream.Words.notThisDriver, DuckDream.Words.driverFailed, DuckDream.Words.timing(p50: 3, p95: 5)] {
            XCTAssertFalse(line.contains("\u{2014}"), line)
        }
    }
}
