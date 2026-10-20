import XCTest
import DuckKit
@testable import StudioKit

/// Dream-1 straight from the app: held to the same answers as OpenCastor's
/// `tests/test_dream.py`, which were read off Dream Labs' live services.
final class DreamDirectTests: XCTestCase {
    static let key = "dl_live_" + String(repeating: "a1b2c3d4", count: 4)

    final class FakeDream: DreamHTTP, @unchecked Sendable {
        struct Sent { let method: String; let path: String; let headers: [String: String]; let body: [String: Any]? }
        private let lock = NSLock()
        private var _sent: [Sent] = []
        var sent: [Sent] { lock.lock(); defer { lock.unlock() }; return _sent }
        var actReply = #"{"session_id":"ses_1","status":{"code":"DA-0000","name":"OK"},"actions":{"per_key":{"action.velocity":[[0.1,0,0.2],[0.2,0,0]]}},"timing":{"gateway_ms":55}}"#

        func send(method: String, url: URL, headers: [String: String], body: Data?) async throws -> (Int, Data) {
            let parsed = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            lock.lock(); _sent.append(Sent(method: method, path: url.path, headers: headers, body: parsed)); lock.unlock()
            let good = headers["Authorization"] == "Bearer \(DreamDirectTests.key)"
            switch url.path {
            case "/v1/models":
                if !good { return (401, Data(#"{"error":{"code":"invalid_api_key","message":"This api key is not valid."}}"#.utf8)) }
                return (200, Data(#"[{"id":"dreamlabs/dream-1-beta","owner":"public","servable":true,"cameras":["overhead"],"embodiment_config":null},{"id":"dream-1-ft:a1b2c3d4-duck","owner":"mine","servable":true,"cameras":["head"],"embodiment_config":{"state":{"velocity":[0,3]},"action":{"velocity":[0,3]},"video":{"head":"observation.images.head"}}}]"#.utf8))
            case "/v1/get_action":
                if !good { return (200, Data(#"{"session_id":"","status":{"code":"DA-1000","name":"UNAUTHORIZED","reason":"unknown_key","retryable":false,"retry_after_s":null},"actions":null,"timing":null}"#.utf8)) }
                return (200, Data(actReply.utf8))
            default:
                return (200, Data(#"{"status":{"code":"DA-0000"}}"#.utf8))
            }
        }
    }

    func testTheModelListMarksWhatADuckCanRun() async throws {
        let answer = try await DreamDirect(key: Self.key, version: "88", http: FakeDream()).models()
        XCTAssertEqual(answer.key, "…c3d4")
        XCTAssertEqual(answer.duckModels.map(\.id), ["dream-1-ft:a1b2c3d4-duck"])
    }

    func testARefusedKeyIsSaidInPlainWords() async {
        do {
            _ = try await DreamDirect(key: "dl_live_nopenope", version: "88", http: FakeDream()).models()
            XCTFail("a refused key was accepted")
        } catch let e as DuckDream.ReadError {
            XCTAssertEqual(e, .refused(DuckDream.Words.keyRefused))
        } catch { XCTFail("\(error)") }
    }

    func testAnActLearnsItsSessionThenSendsItBack() async throws {
        let fake = FakeDream()
        let dream = DreamDirect(key: Self.key, version: "88", http: fake)
        let frames = ["head": (0..<12).map { "F\($0)" }]
        let chunk = try await dream.act(checkpoint: "m", prompt: "walk", frames: frames,
                                        state: ["velocity": [0, 0, 0]], reset: true)
        XCTAssertEqual(chunk.rows.count, 2)
        _ = try await dream.act(checkpoint: "m", prompt: "walk", frames: frames, state: ["velocity": [0, 0, 0]], reset: false)
        let acts = fake.sent.filter { $0.path == "/v1/get_action" }
        XCTAssertTrue(acts[0].body?["session_id"] is NSNull)
        XCTAssertEqual(acts[1].body?["session_id"] as? String, "ses_1")
        let obs = try XCTUnwrap(acts[0].body?["observation"] as? [String: Any])
        XCTAssertEqual(obs["video.head"] as? [String], (3..<12).map { "F\($0)" }, "the last nine, oldest first")
        XCTAssertEqual(obs["prompt"] as? String, "walk")
        XCTAssertEqual(acts[0].headers["User-Agent"], "microduck-studio/88")
    }

    func testAResetEndsTheOldSessionFirst() async throws {
        let fake = FakeDream()
        let dream = DreamDirect(key: Self.key, version: "88", http: fake)
        _ = try await dream.act(checkpoint: "m", prompt: "x", frames: [:], state: [:], reset: true)
        _ = try await dream.act(checkpoint: "m", prompt: "x", frames: [:], state: [:], reset: true)
        XCTAssertEqual(fake.sent.map(\.path), ["/v1/get_action", "/v1/end_session", "/v1/get_action"])
        XCTAssertEqual(fake.sent[1].body?["session_id"] as? String, "ses_1")
    }

    func testAWarmingModelSaysHowLongToWait() async {
        let fake = FakeDream()
        fake.actReply = #"{"session_id":"","status":{"code":"DA-2000","name":"UNAVAILABLE","reason":"pool_warming","retryable":true,"retry_after_s":12}}"#
        do {
            _ = try await DreamDirect(key: Self.key, version: "88", http: fake)
                .act(checkpoint: "m", prompt: "x", frames: [:], state: [:], reset: true)
            XCTFail("warming was not raised")
        } catch let e as DuckDream.ReadError {
            XCTAssertEqual(e, .warming(12))
        } catch { XCTFail("\(error)") }
    }

    func testTheGatewaysKeyRefusalIsTheSameSentence() async {
        do {
            _ = try await DreamDirect(key: "dl_live_nopenope", version: "88", http: FakeDream())
                .act(checkpoint: "m", prompt: "x", frames: [:], state: [:], reset: true)
            XCTFail("a refused key was accepted")
        } catch let e as DuckDream.ReadError {
            XCTAssertEqual(e, .refused(DuckDream.Words.keyRefused))
        } catch { XCTFail("\(error)") }
    }

    func testTheFitTestIsCastorsTest() {
        XCTAssertTrue(DreamWire.fitsDuck(DuckDream.microduck))
        XCTAssertFalse(DreamWire.fitsDuck(nil))
        XCTAssertFalse(DreamWire.fitsDuck(["state": ["velocity": [0, 2]], "action": ["velocity": [0, 3]],
                                           "video": ["head": "x"]]))
        XCTAssertFalse(DreamWire.fitsDuck(["state": ["velocity": [0, 3]], "action": ["velocity": [0, 3]],
                                           "video": ["overhead": "x"]]))
    }

    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var t = Date(timeIntervalSince1970: 0)
        func now() -> Date { lock.lock(); defer { lock.unlock() }; return t }
        func advance(_ s: TimeInterval) { lock.lock(); t += s; lock.unlock() }
    }

    /// A duck link that only drives: no dream.* on it at all.
    private final class PlainLink: DuckPeer, @unchecked Sendable {
        let identity = DuckIdentity(name: "Pip", kind: .real)
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

    func testThePilotDrivesALinkWithNoDreamVerbsAtAll() async {
        let duck = PlainLink(), fake = FakeDream(), clock = Clock()
        let dream = DreamDirect(key: Self.key, version: "88", http: fake)
        await DreamPilot(checkpoint: "m", prompt: "walk", limit: 0.15)
            .run(on: duck, rows: dream, frames: { ["F"] }, events: { _ in },
                 sleep: { clock.advance($0) }, now: { clock.now() })
        XCTAssertFalse(duck.sent.contains { $0.hasPrefix("dream") })
        XCTAssertTrue(duck.sent.contains("robot.move"))
        XCTAssertEqual(duck.sent.last, "robot.stop")
        XCTAssertEqual(fake.sent.last?.path, "/v1/end_session", "the seat is given back after the stop")
    }
}
