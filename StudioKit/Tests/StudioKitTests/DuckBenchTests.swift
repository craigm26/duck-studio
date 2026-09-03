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
         "tickHz":50,"cores":4,"policies":["alpha_stand.onnx"],"trains":false}
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

    /// THESE THREE BODIES CAME OFF A SOCKET, AND THAT IS THE POINT. Every other
    /// bench fixture in this file is JSON somebody typed, and a hand-written
    /// fixture is exactly the evidence that let the placeholder "the bench's
    /// own plant" ship in the first place: it agreed with the reader because
    /// the same person wrote both. `Fixtures/bench/health.json`,
    /// `Fixtures/bench/perform.json` and `Fixtures/bench/record.json` were
    /// captured on 2026-08-30 by running `node duckbench.mjs` on this machine
    /// and calling it over HTTP — the perform body from a real two-rollout run
    /// of alpha_stand against a two-keyframe track, the record body from a
    /// real half-second recording of the same policy under a neutral command,
    /// each with its frames/roots/commands trimmed to three rows so the file
    /// stays readable.
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

    /// A recording is kept and shared like any other clip, so it has to say
    /// which world it was made in — the same hole `/perform` had.
    func testALiveRecordingCarriesTheWorldItWasMadeIn() throws {
        let clip = try DuckBench.readClip(captured("record"), named: "standing on the bench")
        XCTAssertEqual(clip.policy, "alpha_stand.onnx")
        XCTAssertEqual(clip.frames.count, 3)
        XCTAssertEqual(clip.credit,
                       "Recorded on a bench on your network. On scene.mjb, sha256 3f8c9ab9b409.")
    }

    /// A bench too old to name its world leaves a clip that cannot be compared
    /// with anyone else's, and the credit says that rather than implying a
    /// world nobody recorded.
    func testARecordingFromABenchThatNamesNoWorldSaysSoInItsCredit() throws {
        let payload: [String: Any] = ["hz": 50, "policy": "alpha_stand.onnx",
                                      "frames": [Array(repeating: 0.0, count: 14)],
                                      "roots": [[0.0, 0, 0.12, 1, 0, 0, 0]],
                                      "endsUpright": true]
        let clip = try DuckBench.readClip(try JSONSerialization.data(withJSONObject: payload),
                                          named: "x")
        XCTAssertEqual(clip.credit,
                       "Recorded on a bench on your network. Nothing recorded which world this "
                     + "ran in, so nothing here can tell you. A result with no world beside it "
                     + "cannot be compared with one that has another.")
    }

    /// A name with no digest: runnable, not comparable, and said in the one
    /// place the sentence lives.
    func testARecordingFromABenchThatWillNotDigestItsWorldSaysThatToo() throws {
        let payload: [String: Any] = ["hz": 50, "policy": "alpha_stand.onnx",
                                      "plantName": "scene.mjb",
                                      "frames": [Array(repeating: 0.0, count: 14)],
                                      "roots": [[0.0, 0, 0.12, 1, 0, 0, 0]],
                                      "endsUpright": true]
        let clip = try DuckBench.readClip(try JSONSerialization.data(withJSONObject: payload),
                                          named: "x")
        XCTAssertEqual(clip.credit,
                       "Recorded on a bench on your network. On scene.mjb. This bench will not "
                     + "say which bytes that was, and two benches can call different worlds by "
                     + "that name — so a result from this one cannot be matched to a result "
                     + "from another.")
    }

    /// YOUR OWN RECORDING IS NOT A CONTRIBUTION. `ClipNote.provenance` captions
    /// any credited clip "Contributed — … This project did not train it and
    /// cannot see the simulator it was trained in", which was true while the
    /// only credited clips came from strangers. Stamping the plant onto bench
    /// recordings made it false about the person's own machine.
    func testAClipRecordedHereIsNotCaptionedAsSomebodyElses() {
        let credit = DuckBench.recordedCredit(plantName: "scene.mjb",
                                              plantDigest: "3f8c9ab9b409ba74c73c30179d5f7c12b0")
        XCTAssertTrue(DuckBench.wasRecordedHere(credit))
        let clip = DuckIntentClip(name: "run", hz: 50,
                                  frames: [[Double](repeating: 0, count: DuckModel.policyJointCount)],
                                  roots: [], netYaw: 0, loops: false,
                                  startsFrom: .standing, endsIn: .standing,
                                  policy: "alpha_walking.onnx", authored: false,
                                  environment: .bareFloor, credit: credit,
                                  telemetry: .none, variant: .legs)
        let note = try? XCTUnwrap(ClipNote.provenance(for: clip))
        XCTAssertEqual(note, credit, "it shows the credit, not a paragraph about a contributor")
        XCTAssertFalse(note?.contains("Contributed") ?? true)
        XCTAssertFalse(note?.contains("did not train it") ?? true)
        // And it still names the world, which is the whole reason the credit
        // carries the plant.
        XCTAssertTrue(note?.contains("scene.mjb") ?? false)
    }

    /// The case the caption WAS written for still reads as it did.
    func testAClipFromSomebodyElseIsStillCalledContributed() throws {
        let clip = DuckIntentClip(name: "headspin", hz: 50,
                                  frames: [[Double](repeating: 0, count: DuckModel.policyJointCount)],
                                  roots: [], netYaw: 0, loops: false,
                                  startsFrom: .standing, endsIn: .standing,
                                  policy: "headspin.onnx", authored: false,
                                  environment: .bareFloor, credit: "trained by a stranger",
                                  telemetry: .none, variant: .legs)
        let note = try XCTUnwrap(ClipNote.provenance(for: clip))
        XCTAssertTrue(note.hasPrefix("Contributed — trained by a stranger."), note)
    }

    /// A TAILNET HOST IS YOUR OWN MACHINE, AND THE BENCH USED TO DISAGREE WITH
    /// THE REST OF THE APP ABOUT IT. `ModelEndpoint.isLocalHost` accepted
    /// 100.64/10 with a comment explaining why Tailscale counts; `DuckBench`
    /// kept a narrower copy that did not. So the same host was private enough
    /// to send a sentence to and not private enough to send a policy to.
    ///
    /// It matters because of the arrangement this family is actually for: a
    /// phone, a physics bench and a GPU box on one tailnet and three different
    /// networks. Under the old rule the bench half of that was unreachable.
    func testTheBenchAcceptsATailnetHost() throws {
        for host in ["100.122.199.6", "100.64.76.122", "100.95.79.116"] {
            XCTAssertNoThrow(try DuckBench.address("http://\(host):8770"),
                             "\(host) is a tailnet address and is somebody's own machine")
        }
        // MagicDNS names resolve into that same range, so the name is accepted
        // for the same reason the number is.
        XCTAssertNoThrow(try DuckBench.address("http://forge.tail1234.ts.net:8770"))
    }

    /// And the refusal it exists for is untouched: a bench address is checked
    /// precisely so a typo cannot post a policy to a stranger.
    func testTheBenchStillRefusesTheOpenInternet() {
        for host in ["example.com", "8.8.8.8", "203.0.113.9", "100.200.0.1"] {
            XCTAssertThrowsError(try DuckBench.address("http://\(host):8770"),
                                 "\(host) is not on anybody's own network")
        }
    }

    /// The two rules are now one function, not two that agree today.
    func testTheBenchAndTheModelEndpointAnswerTheSameQuestionTheSameWay() {
        let hosts = ["localhost", "127.0.0.1", "::1", "10.0.0.4", "192.168.1.10",
                     "172.20.0.5", "100.64.76.122", "169.254.1.1", "pi.local",
                     "box.internal", "forge.tail1234.ts.net",
                     "example.com", "8.8.8.8", "100.200.0.1", "not a host"]
        for host in hosts {
            XCTAssertEqual(DuckBench.isLocal(host), ModelEndpoint.isLocalHost(host),
                           "\(host) got two different answers about being your own network")
        }
    }

    // MARK: - /tune

    /// THE REQUEST CARRIES THE RESIDUAL AND NOT A FILE, which is the design
    /// decision worth pinning: 28 numbers per candidate instead of 791,584
    /// bytes of base64, and one implementation of the fold rather than two.
    func testATuneRequestSendsTheResidualAndTheTermsItWants() throws {
        let address = try DuckBench.address("192.168.1.20")
        let call = try DuckBench.tune(
            address, policy: "alpha_walking.onnx",
            gain: [Double](repeating: 1.05, count: DuckModel.policyJointCount),
            offset: [Double](repeating: 0.01, count: DuckModel.policyJointCount),
            seconds: 6, drops: [0.121, 0.125, 0.129],
            schedule: DuckBench.walkingCommand,
            terms: DuckTuner.terms.map(\.key))
        XCTAssertEqual(call.method, "POST")
        XCTAssertEqual(call.url.absoluteString, "http://192.168.1.20:8770/tune")
        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try XCTUnwrap(call.body)) as? [String: Any])
        XCTAssertEqual(body["policy"] as? String, "alpha_walking.onnx")
        XCTAssertEqual((body["gain"] as? [Double])?.count, DuckModel.policyJointCount)
        XCTAssertEqual((body["offset"] as? [Double])?.count, DuckModel.policyJointCount)
        XCTAssertEqual(body["drops"] as? [Double], [0.121, 0.125, 0.129])
        XCTAssertEqual(body["terms"] as? [String], DuckTuner.terms.map(\.key))
        XCTAssertNil(body["onnx"], "no file goes over the wire — the bench holds the base")
    }

    func testATuneAnswerIsReadWithItsTermsAndItsDistance() throws {
        let json = """
        {"policy":"alpha_walking.onnx","episodes":3,"standing":3,
         "criterion":"ends standing, trunk at least 100 mm up","travelled":1.207,
         "terms":{"upright":0.9467,"pose":0.6353,"track_linear_velocity":0.51,
                  "track_angular_velocity":0.72,"body_ang_vel":0.83,"action_rate_l2":0.04},
         "refused":[{"name":"air_time","why":"no foot-contact sensor in scene.mjb"}],
         "plantName":"scene.mjb","plantDigest":"3f8c9ab9b409","seconds":6}
        """
        let tuned = try DuckBench.readTuned(Data(json.utf8))
        XCTAssertEqual(tuned.episodes, 3)
        XCTAssertEqual(tuned.standing, 3)
        XCTAssertEqual(tuned.travelled, 1.207)
        XCTAssertEqual(tuned.terms["upright"], 0.9467)
        XCTAssertEqual(tuned.refused.map(\.name), ["air_time"])
        XCTAssertEqual(tuned.plantName, "scene.mjb")
        // AND IT SCORES, because every term the reward needs is present.
        XCTAssertNoThrow(try DuckTuner.reward(tuned.terms))
    }

    /// A BENCH WITHOUT `/tune` IS NOT A BROKEN BENCH. Every shell in this
    /// family answers an unknown path with the same error shape, and the screen
    /// has to be able to read it as "this one cannot score a search" rather
    /// than as a failure.
    func testABenchWithNoTuneEndpointComesBackAsItsOwnWords() {
        XCTAssertThrowsError(try DuckBench.readTuned(Data(#"{"error":"no /tune here"}"#.utf8))) {
            XCTAssertEqual($0 as? DuckBench.ReadError, .bench("no /tune here"))
            XCTAssertEqual(($0 as? DuckBench.ReadError)?.message, "The bench said: no /tune here")
        }
    }

    /// A BENCH THAT ANSWERED WITH FEWER TERMS THAN IT WAS ASKED FOR MUST NOT
    /// BE SCORED. `readTuned` takes what it is given — a reader that invented a
    /// missing term would be worse — and `DuckTuner.reward` is where the
    /// omission becomes a refusal.
    func testATuneAnswerMissingATermIsReadAndThenRefused() throws {
        let json = """
        {"policy":"p","episodes":3,"standing":3,"travelled":1.0,
         "terms":{"upright":0.9,"pose":0.6,"track_linear_velocity":0.5,
                  "track_angular_velocity":0.7,"body_ang_vel":0.8}}
        """
        let tuned = try DuckBench.readTuned(Data(json.utf8))
        XCTAssertEqual(tuned.terms.count, 5)
        XCTAssertThrowsError(try DuckTuner.reward(tuned.terms)) {
            XCTAssertEqual($0 as? DuckTuner.Refusal, .termMissing("action_rate_l2"))
        }
    }

    /// PER-DROP REWARDS ARE WHAT A NOISE FLOOR IS MADE OF, so the reader has to
    /// carry them rather than summarise them away. A bench that sends only the
    /// aggregate is readable and unfloorable, and that has to be visible.
    func testPerDropEpisodesAreCarriedAndAreWhatTheFloorIsMadeOf() throws {
        let terms = DuckTuner.terms.map { "\"\($0.key)\": 0.5" }.joined(separator: ",")
        let other = DuckTuner.terms.map { "\"\($0.key)\": 0.6" }.joined(separator: ",")
        let json = """
        {"policy":"p","episodes":2,"standing":2,"travelled":1.1,"terms":{\(terms)},
         "perDrop":[{"drop":0.121,"travelled":1.0,"standing":true,"terms":{\(terms)}},
                    {"drop":0.129,"travelled":1.2,"standing":true,"terms":{\(other)}}]}
        """
        let tuned = try DuckBench.readTuned(Data(json.utf8))
        XCTAssertEqual(tuned.perDrop.count, 2)
        XCTAssertEqual(tuned.perDrop.first?.drop, 0.121)
        XCTAssertEqual(tuned.perDrop.last?.travelled, 1.2)
        let floor = try XCTUnwrap(DuckTuner.noiseFloor(
            try tuned.perDrop.map { try DuckTuner.reward($0.terms) }))
        XCTAssertGreaterThan(floor, 0, "two different episodes have a spread")

        // AND A BENCH THAT SENDS ONLY THE AGGREGATE IS UNFLOORABLE, VISIBLY.
        let flat = try DuckBench.readTuned(Data("""
        {"policy":"p","episodes":2,"standing":2,"travelled":1.1,"terms":{\(terms)}}
        """.utf8))
        XCTAssertTrue(flat.perDrop.isEmpty)
        XCTAssertNil(DuckTuner.noiseFloor(try flat.perDrop.map { try DuckTuner.reward($0.terms) }))
    }

    func testATuneAnswerWithNoEpisodesIsEmptyRatherThanZeroScored() {
        XCTAssertThrowsError(try DuckBench.readTuned(Data(#"{"episodes":0,"terms":{}}"#.utf8))) {
            XCTAssertEqual($0 as? DuckBench.ReadError, .empty)
        }
    }

    /// EVERY FACTORY'S PATH IS IN `routes`, AND NOTHING ELSE IS. The phone's
    /// loopback server forwards exactly `routes`; an endpoint a factory can
    /// name that is not in the list ships dead on that bench. `/tune` did.
    func testEveryCallThisTypeCanMakeIsARoutablePath() throws {
        let address = DuckBench.Address(host: "127.0.0.1", port: 1)
        let step = [DuckBench.Step(at: 0), DuckBench.Step(at: 0.5, vx: 0.5)]
        let calls: [DuckBench.Call] = [
            DuckBench.health(address),
            try DuckBench.record(address, policy: "p", seconds: 1, schedule: step),
            try DuckBench.measure(address, policy: "p", seconds: 1, rollouts: 1, schedule: step),
            try DuckBench.upload(address, onnx: Data([1, 2, 3])),
            try DuckBench.upload(address, onnx: Data([1, 2, 3]), parameters: Data([4])),
            try DuckBench.uploadParameters(address, canonicalBytes: Data([1])),
            try DuckBench.tune(address, policy: "p", gain: [1], offset: [0], seconds: 1,
                               drops: [0.12], schedule: step, terms: ["upright"]),
            try DuckBench.climb(address, intent: StairsChallenge.intentData(named: "ctrl_do_nothing"),
                                rise: 0.060, cell: StairsChallenge.Grid.fallback[0]),
            DuckBench.climbGrid(address),
            try DuckBench.chase(address, entrant: BallChallenge.Entrants.doNothing,
                                cell: BallChallenge.Grid.fallback[0]),
            DuckBench.chaseGrid(address),
            DuckBench.world(address),
            try DuckBench.setWorld(address,
                                   DuckWorld.plan(for: DuckScene.staircase(count: 4, rise: 0.060,
                                                                          run: 0.28, start: 0.12),
                                                  on: .pinned)),
        ]
        for call in calls {
            XCTAssertTrue(DuckBench.routes.contains(call.url.path),
                          "\(call.url.path) is not a routable path — the phone bench would 404 it")
        }
        XCTAssertTrue(DuckBench.routes.contains("/tune"))
        XCTAssertTrue(DuckBench.routes.contains("/climb"))
        XCTAssertTrue(DuckBench.routes.contains("/climb/grid"))
        XCTAssertTrue(DuckBench.routes.contains("/chase"))
        XCTAssertTrue(DuckBench.routes.contains("/chase/grid"))
        // THE PHONE'S OWN BENCH FORWARDS EXACTLY THIS SET. `/world` shipping
        // in a factory and not in this list would be a picker whose every
        // entry 404s on the bench the app carries — which is how `/tune`
        // shipped, once.
        XCTAssertTrue(DuckBench.routes.contains("/world"))
        XCTAssertEqual(DuckBench.routes.count, 16)
    }

    // MARK: - a run that carries the world it ran in

    /// A bench on the desk, and a pose the harness's fourteen slots accept.
    private var address: DuckBench.Address { DuckBench.Address(host: "127.0.0.1", port: 8770) }
    private var pose14: [Double] { Array(repeating: 0.0, count: DuckModel.policyJointCount) }


    /// CANONICAL JSON, SO TWO BODIES CAN BE COMPARED AT ALL. A dictionary has
    /// no key order; sorting the keys is the only way to ask whether two
    /// requests say the same thing.
    private func canonical(_ any: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: any,
                                                    options: [.sortedKeys]), as: UTF8.self)
    }

    private func decoded(_ call: DuckBench.Call) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: try XCTUnwrap(call.body))
                        as? [String: Any])
    }

    /// A REQUEST WITH NO WORLD IS THE REQUEST THIS ROUTE HAS ALWAYS MADE. Not
    /// `world: null`, not `spawn: null` — absent, so a bench that predates the
    /// field answers exactly what it always answered.
    func testAPerformWithNoWorldSendsExactlyTheBodyItAlwaysSent() throws {
        let call = try DuckBench.perform(address, keys: [(at: 0.4, pose: pose14)], seconds: 1)
        let body = try decoded(call)
        XCTAssertEqual(body.keys.sorted(), ["blend", "rollouts", "seconds", "track"])
        XCTAssertNil(body["world"])
        XCTAssertNil(body["spawn"])
    }

    /// ONE SPELLER FOR BOTH ROUTES. The bench validates a `/perform` world
    /// with the same function it validates a `POST /world` with, so a client
    /// that spelled them differently would be obeyed on one and refused on the
    /// other for the same drawing.
    func testAPerformWithAWorldSendsTheWorldSetWorldWouldHaveSent() throws {
        let scene = DuckScene(name: "Ball and a block",
                              props: [DuckScene.ball(x: 0.40, y: 0),
                                      DuckScene.block(x: 0.45, y: -0.30)])
        let plan = DuckWorld.plan(for: scene, on: .pinned)
        let performed = try decoded(try DuckBench.perform(address,
                                                          keys: [(at: 0.4, pose: pose14)],
                                                          seconds: 1, world: plan))
        let set = try decoded(try DuckBench.setWorld(address, plan))
        XCTAssertEqual(try canonical(try XCTUnwrap(performed["world"])), try canonical(set))
    }

    /// REFUSED BEFORE A REQUEST EXISTS: the bench would answer with the same
    /// reason, and a round trip to be told what was already known is a round
    /// trip that makes somebody wait to be refused.
    func testAPerformWithARefusingPlanIsNeverSent() {
        let plan = DuckWorld.plan(for: DuckScene.staircase(count: 15), on: .pinned)
        XCTAssertThrowsError(try DuckBench.perform(address, keys: [(at: 0.4, pose: pose14)],
                                                   seconds: 1, world: plan)) {
            XCTAssertEqual($0 as? DuckWorld.Refusal, .tooManySteps(asked: 15, bank: 14))
        }
    }

    func testASpawnGoesOnTheWireAsThreeNumbers() throws {
        let call = try DuckBench.perform(address, keys: [(at: 0.4, pose: pose14)], seconds: 1,
                                         spawn: DuckWorld.Point(x: 0.05, y: 1.305))
        let spawn = try XCTUnwrap(try decoded(call)["spawn"] as? [String: Double])
        XCTAssertEqual(spawn.keys.sorted(), ["x", "y", "z"])
        XCTAssertEqual(spawn["x"], 0.05)
        XCTAssertEqual(spawn["y"], 1.305)
        // A FLOOR POINT HAS NO HEIGHT AND A SPAWN DOES: the harness's own
        // 0.120, which is where /perform has always started its first rollout.
        XCTAssertEqual(spawn["z"], 0.120)
    }

    /// A move at blend 2.1153 would be PLAYED at 1.0 and REPORTED as 2.1153.
    func testABlendAboveOneIsRefusedRatherThanClamped() {
        XCTAssertThrowsError(try DuckBench.perform(address, keys: [(at: 0.4, pose: pose14)],
                                                   seconds: 1, blend: 2.1153)) {
            guard case DuckBench.Refusal.blendWouldBeClamped(let blend) = $0 else {
                return XCTFail("a clamped blend is its own refusal, got \($0)")
            }
            XCTAssertEqual(blend, 2.1153)
            XCTAssertTrue(DuckBench.blendWouldBeClamped(blend).contains("2.1153"))
        }
    }

    func testAPerformAnswerCarriesTheWorldThatActuallyStood() throws {
        let outcome = try DuckBench.readOutcome(captured("perform-stood"),
                                                when: Date(timeIntervalSince1970: 0),
                                                askedForWorld: true)
        let laid = try XCTUnwrap(outcome.laid)
        XCTAssertEqual(laid.steps.count, 4)
        let first = try XCTUnwrap(laid.steps.first)
        XCTAssertEqual(first.x, 0.29, accuracy: 1e-9)
        XCTAssertEqual(first.y, 1.305, accuracy: 1e-9)
        XCTAssertEqual(first.top, 0.06, accuracy: 1e-9)
        XCTAssertEqual(first.halfDepth, 0.17, accuracy: 1e-9)
        XCTAssertEqual(first.halfWidth, 0.17, accuracy: 1e-9)
        XCTAssertEqual(first.halfHeight, 0.10, accuracy: 1e-9)
        XCTAssertEqual(laid.parked, 10)
        XCTAssertEqual(laid.bankCount, 14)
        XCTAssertEqual(laid.spawn?.x, 0.05)
        XCTAssertEqual(laid.spawn?.y, 1.305)
        XCTAssertEqual(laid.spawn?.z, 0.12)
        let sag = try XCTUnwrap(laid.sagMillimetres)
        XCTAssertGreaterThan(sag, 0)
        XCTAssertLessThan(sag, 3, "a once-per-run lay sags past 3 mm inside fifty ticks")
        if case .laid = outcome.worldStanding {} else {
            XCTFail("a world came back, so the standing is laid")
        }
    }

    /// ONE READER FOR BOTH ROUTES. A `/perform` answer nests the whole `/world`
    /// readback under `stood` precisely so this is true; a second reader is a
    /// second thing to keep in step, and the day it drifts is the day the
    /// picture stops being the run.
    func testTheStoodBlockIsParsedByTheSameReaderAsTheWorldRoute() throws {
        let fromWorldRoute = try DuckBench.readWorld(captured("world"))
        let top = try XCTUnwrap(try JSONSerialization.jsonObject(with: captured("perform-stood"))
                                  as? [String: Any])
        let stood = try DuckBench.readWorld(try XCTUnwrap(top["stood"] as? [String: Any]))
        XCTAssertEqual(stood.bank, fromWorldRoute.bank)
        XCTAssertEqual(stood.arena, fromWorldRoute.arena)
        XCTAssertEqual(stood.parked, fromWorldRoute.parked)
    }

    /// A DRAFT WRITTEN BEFORE THIS BUILD MUST DECODE, not vanish. `DraftStore`
    /// decodes inside `compactMap { try? … }`, so a throw here is a draft list
    /// that silently shortens.
    func testAnOutcomeWithNoStoodKeyDecodesRatherThanVanishing() throws {
        let build46 = Data(#"""
        {"when": 0, "bench": "duck-bench/3", "plantName": "scene.mjb",
         "policy": "alpha_stand.onnx", "achieves": 8, "rollouts": 8,
         "criterion": "stayed upright to the end, over drop heights 0.120-0.130 m"}
        """#.utf8)
        let outcome = try JSONDecoder().decode(Pipeline.BenchOutcome.self, from: build46)
        XCTAssertEqual(outcome.rollouts, 8)
        XCTAssertNil(outcome.laid)
        XCTAssertNil(outcome.askedForWorld)
        XCTAssertEqual(outcome.worldStanding, .notRecorded)
    }

    /// "NOTHING WAS ASKED" AND "THE BENCH COULD NOT SAY" ARE THE SAME BYTES ON
    /// THE WIRE, and only the caller knows which happened.
    func testAskingForAWorldAndGettingNoneIsItsOwnState() throws {
        let noStood = try captured("perform")
        let asked = try DuckBench.readOutcome(noStood, when: Date(timeIntervalSince1970: 0),
                                              askedForWorld: true)
        XCTAssertEqual(asked.worldStanding, .askedAndTheBenchDidNotSay)
        let didNotAsk = try DuckBench.readOutcome(noStood, when: Date(timeIntervalSince1970: 0),
                                                  askedForWorld: false)
        XCTAssertEqual(didNotAsk.worldStanding, .benchsOwn)
        XCTAssertNotEqual(asked.worldSentence, didNotAsk.worldSentence)
    }

    /// THE FIRST READER OF `/perform`'s FRAMES. It has answered with them
    /// since it existed and this kit has thrown them away every time.
    func testAPerformAnswerBecomesAPictureInTheWorldThatStood() throws {
        let data = try captured("perform-stood")
        let outcome = try DuckBench.readOutcome(data, when: Date(timeIntervalSince1970: 0),
                                                askedForWorld: true)
        let laid = try XCTUnwrap(outcome.laid)
        let clip = try DuckBench.readPerformedClip(data, named: "lever_up", laid: laid)
        XCTAssertEqual(clip.hz, DuckModel.tickHz)
        XCTAssertEqual(clip.frames.count, 50, "fifty recorded ticks of a one-second track")
        XCTAssertEqual(clip.roots.count, clip.frames.count)
        XCTAssertEqual(clip.telemetry.commands.count, clip.frames.count)
        for frame in clip.frames { XCTAssertEqual(frame.count, 14) }
        // THE READBACK, NOT A HARDCODED BARE FLOOR.
        XCTAssertEqual(clip.environment, laid.asEnvironment)
        XCTAssertNotEqual(clip.environment, .bareFloor)
        XCTAssertEqual(clip.environment.steps.count, 4)
    }

    /// The harness's blocks are 200 mm and a tread above that really does
    /// float. Said out loud rather than drawn thicker.
    func testATreadAboveTwoHundredMillimetresIsFlagged() throws {
        let outcome = try DuckBench.readOutcome(captured("perform-stood"),
                                                when: Date(timeIntervalSince1970: 0),
                                                askedForWorld: true)
        XCTAssertTrue(try XCTUnwrap(outcome.laid).aTreadFloats,
                      "the 240 mm tread on a 200 mm block floats")

        let shallow = Pipeline.LaidWorld(
            name: "4 × 40 mm", steps: (1...4).map {
                .init(x: 0.29, y: 1.305, top: Double($0) * 0.04,
                      halfDepth: 0.17, halfWidth: 0.17, halfHeight: 0.1)
            }, ball: nil, props: [], notes: [], bankCount: 14, parked: 10,
            spawn: nil, sagMillimetres: nil, plantName: nil, plantDigest: nil)
        XCTAssertFalse(shallow.aTreadFloats)
    }


    /// WORKED EXAMPLE B — a drawn bare floor with a ball and a block.
    ///
    /// TWO THINGS THE APP HAS TO BE ABLE TO SAY OUT LOUD ARE IN HERE: the
    /// whole bank was parked, which is a real change to the plant every other
    /// number on this bench was measured in; and nothing said where the duck
    /// should stand, so it is on its compiled mark and anything laid on the
    /// bank's row would be 1.305 m to its left.
    func testAWorldLaidWithNoSpawnAndAParkedBankSaysBoth() throws {
        let answer = Data(#"""
        {"format":"duck-intent-clips/3","hz":50,"policy":"alpha_stand.onnx","authored":true,
         "plantName":"scene.mjb","plantDigest":"3f8c9ab9b409","blend":1,
         "frames":[[0,0,0,0,0,0,0,0,0,0,0,0,0,0]],"roots":[[0,0,0.12,1,0,0,0]],
         "commands":[[0,0,0]],"rollouts":8,"achieves":8,"criterion":"stayed upright",
         "stood":{"world":{"set":true,"name":"Ball and a block"},"steps":[],
                  "ball":{"x":0.4,"y":0.0,"z":0.05},"ballRadius":0.05,
                  "props":[{"name":"block_a","mass":0.03,"at":[0.45,-0.3,0.021]}],
                  "bank":{"count":14,"present":14,"parked":14,"y":1.305},
                  "unexpressed":[{"what":"spawn","field":"spawn","asked":null,
                                  "got":{"x":0,"y":0},
                                  "why":"nothing asked where the duck should stand"}],
                  "spawn":{"x":0,"y":0,"z":0.12},"sag_mm":0}}
        """#.utf8)
        let laid = try XCTUnwrap(try DuckBench.readOutcome(answer,
                                                           when: Date(timeIntervalSince1970: 0),
                                                           askedForWorld: true).laid)
        XCTAssertEqual(laid.parked, 14)
        XCTAssertEqual(laid.bankCount, 14)
        XCTAssertTrue(laid.wholeBankWasParked)
        XCTAssertNil(laid.noSpawnNote, "no flight stood, so there is nothing to be beside")
        XCTAssertEqual(laid.spawn?.x, 0)
        XCTAssertEqual(laid.spawn?.y, 0)
        XCTAssertFalse(laid.aTreadFloats, "nothing stood, so nothing floats")
        XCTAssertTrue(DuckWorld.laidSaid(laid).hasPrefix("No blocks stood: fourteen of the "
                                                       + "bank's fourteen are parked"),
                      DuckWorld.laidSaid(laid))
        // The ball is drawn where the readback found it, not where the scene
        // asked for it.
        XCTAssertEqual(laid.asProps.first?.x, 0.4)
        XCTAssertEqual(laid.asEnvironment.steps.count, 0)
    }


    /// A spawn-only /perform answers with a `stood` block whose world was
    /// never set: every block where it booted, nothing pinned. That is not a
    /// laid world, and reading it as one captioned the bench's own scattered
    /// blocks as a flight it re-pinned every tick.
    func testAStoodBlockThatSaysNoWorldStoodIsNotALaidWorld() throws {
        func block(set: Bool) -> [String: Any] {
            ["stood": ["world": ["set": set, "name": NSNull()],
                       "steps": [["x": 0.29, "y": 1.305, "top": 0.06, "halfDepth": 0.17,
                                  "halfWidth": 0.17, "halfHeight": 0.1]],
                       "ball": NSNull(), "props": [],
                       "bank": ["count": 14, "present": 14, "parked": 13, "y": 1.305],
                       "unexpressed": [],
                       "spawn": ["x": 0.05, "y": 1.305, "z": 0.12], "sag_mm": NSNull()]]
        }
        XCTAssertNil(try DuckBench.readStood(block(set: false)))
        XCTAssertNotNil(try DuckBench.readStood(block(set: true)))
    }
}
