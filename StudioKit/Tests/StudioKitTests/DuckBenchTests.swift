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
        // This body is a duck-bench/1 answer, from before the bench identified
        // its own plant. It must read as silence, not as an identification.
        XCTAssertNil(health.plantName)
        XCTAssertEqual(health.plantSentence,
                       "This bench does not say which world it runs, so a result from it "
                     + "cannot be matched to a result from another bench.")
    }

    /// The bench identifies the world it is actually running now — the file's
    /// bare name and a sha256 of its bytes. VERIFIED against the real thing:
    /// `sim/scene.mjb` in duck-sounds digests to 3f8c9ab9b409… , which is the
    /// canon plant every recorded clip in DuckKit came from (sim/PLANT.md).
    func testABenchThatIdentifiesItsWorldIsSaidToIdentifyIt() throws {
        let data = Data(#"""
        {"bench":"duck-bench/2","plant":"scene.mjb — Pollen robot_allcollisions, training parameters",
         "plantName":"scene.mjb",
         "plantDigest":"3f8c9ab9b409ba74c73c30179d5f7c12b025f631693f9eec78d80dca242547be",
         "tickHz":50,"cores":4,"policies":["BEST_alpha_stand.onnx"],"trains":false}
        """#.utf8)
        let health = try DuckBench.readHealth(data)
        XCTAssertEqual(health.plantName, "scene.mjb")
        XCTAssertEqual(health.plantSentence,
                       "Running scene.mjb, sha256 3f8c9ab9b409.")
    }

    /// A name with no digest is a bench that can be run and whose results
    /// cannot be compared, and the person pressing Run is told which.
    func testABenchThatNamesItsWorldWithoutDigestingItSaysSo() throws {
        let data = Data(#"""
        {"bench":"duck-bench/2","plant":"scene.mjb","plantName":"scene.mjb",
         "tickHz":50,"cores":4,"policies":[],"trains":false}
        """#.utf8)
        XCTAssertEqual(try DuckBench.readHealth(data).plantSentence,
                       "Running scene.mjb. It will not say which bytes that is, and two "
                     + "benches can call different worlds by that name.")
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

    // MARK: - captured off a live bench, not written by hand

    /// THESE TWO BODIES CAME OFF A SOCKET, AND THAT IS THE POINT. Every other
    /// bench fixture in this file is JSON somebody typed, and a hand-written
    /// fixture is exactly the evidence that let the placeholder "the bench's
    /// own plant" ship in the first place: it agreed with the reader because
    /// the same person wrote both. `Fixtures/bench/health.json` and
    /// `Fixtures/bench/perform.json` were captured on 2026-08-30 by running
    /// `node duckbench.mjs` on this machine and calling it over HTTP — the
    /// perform body from a real two-rollout run of BEST_alpha_stand against a
    /// two-keyframe track, with its frames/roots/commands trimmed to three rows
    /// so the file stays readable.
    private func captured(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/bench/\(name)",
                                                  withExtension: "json"),
                                "the captured \(name) fixture is missing")
        return try Data(contentsOf: url)
    }

    func testALiveBenchsHealthNamesTheCanonPlant() throws {
        let health = try DuckBench.readHealth(captured("health"))
        XCTAssertEqual(health.plantName, "scene.mjb")
        // The digest a real bench computed over its own scene file, which is
        // the one sim/PLANT.md settles as canon.
        XCTAssertEqual(health.plantDigest,
                       "3f8c9ab9b409ba74c73c30179d5f7c12b025f631693f9eec78d80dca242547be")
        XCTAssertEqual(health.plantSentence, "Running scene.mjb, sha256 3f8c9ab9b409.")
        // THE VERSION IS WHAT MAKES SILENCE READABLE LATER. duck-bench/2 could
        // not say which world it ran; /3 can. Without the bump, a bench too old
        // to answer and a bench that simply did not are the same bytes, and any
        // future sentence naming a cause would be guessing — which is how the
        // placeholder this all replaced came to exist.
        XCTAssertEqual(health.bench, "duck-bench/3")
    }

    func testALivePerformCarriesTheWorldItRanIn() throws {
        let outcome = try DuckBench.readOutcome(captured("perform"),
                                                   when: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(outcome.plantName, "scene.mjb")
        XCTAssertEqual(outcome.plantDigest?.prefix(12), "3f8c9ab9b409")
        XCTAssertEqual(outcome.plantSentence, "On scene.mjb, sha256 3f8c9ab9b409.")
        // And it is a real result, not a stub: two rollouts, both upright.
        XCTAssertEqual(outcome.rollouts, 2)
        XCTAssertEqual(outcome.achieves, 2)
        XCTAssertEqual(outcome.criterion,
                       "stayed upright to the end, over drop heights 0.120-0.130 m")
        XCTAssertFalse(outcome.told.contains("the bench's own plant"))
    }
}
