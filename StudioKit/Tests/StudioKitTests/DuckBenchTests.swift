import XCTest
import DuckKit
@testable import StudioKit

/// Talking to a machine on your network that has physics.
final class DuckBenchTests: XCTestCase {

    func testItAcceptsTheAddressesABenchActuallyHas() throws {
        for (text, host, port) in [
            ("192.168.1.20:8770", "192.168.1.20", 8770),
            ("192.168.1.20", "192.168.1.20", 8770),
            ("http://192.168.1.20:8770/", "192.168.1.20", 8770),
            ("  10.0.0.5:9000  ", "10.0.0.5", 9000),
            ("172.16.4.4", "172.16.4.4", 8770),
            ("duckbench.local:8770", "duckbench.local", 8770),
            ("localhost:8770", "localhost", 8770),
            ("100.122.199.6".replacingOccurrences(of: "100.122", with: "10.122"), "10.122.199.6", 8770),
        ] {
            let address = try DuckBench.address(text)
            XCTAssertEqual(address.host, host, text)
            XCTAssertEqual(address.port, port, text)
        }
    }

    /// A typo must not send a request to a stranger on the open internet.
    func testItRefusesAnythingThatIsNotOnYourNetwork() {
        for text in ["example.com", "8.8.8.8", "http://evil.example:8770", "203.0.113.9:8770"] {
            XCTAssertThrowsError(try DuckBench.address(text), text) { error in
                guard case DuckBench.Refusal.notLocal = error else {
                    return XCTFail("\(text) gave \(error)")
                }
            }
        }
        XCTAssertThrowsError(try DuckBench.address("")) {
            XCTAssertEqual($0 as? DuckBench.Refusal, .empty)
        }
        XCTAssertTrue(DuckBench.Refusal.notLocal("example.com").message.contains("example.com"))
    }

    func testTheCallsAreShaped() throws {
        let address = try DuckBench.address("192.168.1.20:8770")
        XCTAssertEqual(DuckBench.health(address).displayURL, "http://192.168.1.20:8770/health")
        let record = try DuckBench.record(address, policy: "flamingo-cycle/policy.onnx",
                                          seconds: 6,
                                          schedule: [.init(at: 0, vy: 1), .init(at: 1, vx: 1, vy: 1)])
        XCTAssertEqual(record.displayURL, "http://192.168.1.20:8770/record")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: record.body!) as? [String: Any])
        XCTAssertEqual(body["policy"] as? String, "flamingo-cycle/policy.onnx")
        XCTAssertEqual(body["seconds"] as? Double, 6)
        let schedule = try XCTUnwrap(body["schedule"] as? [[Any]])
        XCTAssertEqual(schedule.count, 2)
        XCTAssertEqual(schedule[1][0] as? Double, 1)
        XCTAssertEqual((schedule[1][1] as? [String: Double])?["vx"], 1)
    }

    func testATokenGoesInAHeaderAndNotTheAddress() throws {
        let address = try DuckBench.address("192.168.1.20:8770")
        let request = DuckBench.urlRequest(for: DuckBench.health(address), token: "secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertFalse(request.url!.absoluteString.contains("secret"))
        let open = DuckBench.urlRequest(for: DuckBench.health(address))
        XCTAssertNil(open.value(forHTTPHeaderField: "Authorization"))
    }

    /// The real answer this bench gives, so the decoder is pinned to it.
    func testItReadsTheBenchsOwnHealth() throws {
        let data = Data(#"""
        {"bench":"duck-bench/1","plant":"scene.mjb — Pollen robot_allcollisions, training parameters",
         "tickHz":50,"cores":4,"policies":["alpha_walking.onnx","flamingo-cycle/policy.onnx"],
         "records":true,"measures":true,"trains":false,
         "trainsWhy":"The accelerator here is an inference ASIC, and mjlab wants a GPU."}
        """#.utf8)
        let health = try DuckBench.readHealth(data)
        XCTAssertEqual(health.bench, "duck-bench/1")
        XCTAssertEqual(health.cores, 4)
        XCTAssertEqual(health.tickHz, DuckModel.tickHz)
        XCTAssertEqual(health.policies.count, 2)
        XCTAssertFalse(health.trains, "the bench is honest about not training")
        XCTAssertTrue(health.trainsWhy!.contains("inference ASIC"))
    }

    func testARecordingBecomesAClipThisAppCanDraw() throws {
        let frames = Array(repeating: Array(repeating: 0.0, count: 14), count: 3)
        let roots = Array(repeating: [0.0, 0, 0.12, 1, 0, 0, 0], count: 3)
        let payload: [String: Any] = ["format": "duck-intent-clips/3", "hz": 50,
                                      "policy": "flamingo-cycle/policy.onnx",
                                      "frames": frames, "roots": roots,
                                      "commands": Array(repeating: [1.0, 1, 0], count: 3),
                                      "endsUpright": true, "endHeight": 0.122]
        let clip = try DuckBench.readClip(try JSONSerialization.data(withJSONObject: payload),
                                          named: "flamingo on the bench")
        XCTAssertEqual(clip.name, "flamingo on the bench")
        XCTAssertEqual(clip.frames.count, 3)
        XCTAssertEqual(clip.roots.count, 3)
        XCTAssertEqual(clip.policy, "flamingo-cycle/policy.onnx")
        XCTAssertEqual(clip.endsIn, .standing)
        XCTAssertEqual(clip.hz, DuckModel.tickHz)
        XCTAssertFalse(clip.telemetry.commands.isEmpty)
    }

    /// A bench at another rate makes a clip that plays at the wrong speed and
    /// merely looks odd — which is the failure that gets shipped.
    func testABenchAtTheWrongRateIsRefused() throws {
        let payload: [String: Any] = ["hz": 30, "frames": [[0.0]], "roots": [[0.0,0,0,1,0,0,0]]]
        XCTAssertThrowsError(try DuckBench.readClip(
            try JSONSerialization.data(withJSONObject: payload), named: "x")) {
            XCTAssertEqual($0 as? DuckBench.ReadError, .wrongRate(30))
        }
    }

    func testTheBenchsErrorsArriveAsWords() throws {
        let refusal = Data(#"{"error":"unknown policy: ../../../etc/passwd"}"#.utf8)
        XCTAssertThrowsError(try DuckBench.readClip(refusal, named: "x")) {
            XCTAssertEqual($0 as? DuckBench.ReadError,
                           .bench("unknown policy: ../../../etc/passwd"))
        }
        XCTAssertThrowsError(try DuckBench.readHealth(Data("not json".utf8))) {
            XCTAssertEqual($0 as? DuckBench.ReadError, .notJSON)
        }
        XCTAssertThrowsError(try DuckBench.readClip(
            try JSONSerialization.data(withJSONObject: ["hz": 50, "frames": []]), named: "x")) {
            XCTAssertEqual($0 as? DuckBench.ReadError, .empty)
        }
    }

    func testItReadsTheSuccessTheBenchMeasured() throws {
        let data = Data(#"""
        {"policy":"flamingo-cycle/policy.onnx","rollouts":8,"achieves":8,
         "criterion":"ends standing, trunk at least 100 mm up",
         "randomised":"drop height 0.12-0.13 m","medianHeight":0.116,"worstHeight":0.116}
        """#.utf8)
        let success = try DuckBench.readSuccess(data)
        XCTAssertEqual(success.achieves, 8)
        XCTAssertEqual(success.rollouts, 8)
        XCTAssertEqual(success.medianHeight, 0.116)
        XCTAssertTrue(success.criterion.contains("100 mm"))
    }
}
