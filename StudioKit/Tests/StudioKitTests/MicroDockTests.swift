import XCTest
import Crypto
import DuckKit
import DuckEvidence
@testable import StudioKit

/// The MicroDock networks are recognised by what their weights are, and the Dock routine is
/// upstream's sequence with upstream's numbers.
final class MicroDockTests: XCTestCase {

    // MARK: - the files

    /// The two the app bundles, found from this file so it runs wherever the repository is.
    static func bundled(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("DuckStudio/Resources/\(name)")
    }

    static func file(of network: MicroDock.Network) throws -> URL {
        if network.bundled { return bundled(network.fileName) }
        return try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/microdock/\(network.fileName)",
                                               withExtension: nil))
    }

    /// The bytes as upstream ships them at c1ba96f (sha256 of each file, taken from the clone).
    static let upstreamFileDigests: [String: String] = [
        "scoot_dock.onnx": "068569fb2a3972fef41138c8060c04a00df912476433af7c973403079d25890d",
        "scoot_undock.onnx": "5e04b7cd04533cf0e0f6bab381330e70ff6419579685b7513dccf642b689826d",
        "scoot_dock_undock.onnx": "ed5eb3dfebff543a456ff70e86c7cbef3e35c31016d81b50084c37e62efddf56",
    ]

    func testTheFilesAreUpstreamsBytes() throws {
        for network in MicroDock.networks {
            let data = try Data(contentsOf: try Self.file(of: network))
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, Self.upstreamFileDigests[network.fileName], network.fileName)
        }
    }

    /// REGENERATE, NEVER RETYPE: every fingerprint in the table is the one DuckKit measures.
    func testEveryFingerprintIsMeasuredFromItsFile() throws {
        for network in MicroDock.networks {
            let policy = try DuckPolicy.load(contentsOf: try Self.file(of: network))
            XCTAssertEqual(policy.fingerprint, network.fingerprint, network.fileName)
            XCTAssertEqual(MicroDock.network(fingerprint: policy.fingerprint), network)
        }
    }

    func testNoneOfThemIsCalledAPollenRelease() throws {
        for network in MicroDock.networks {
            let policy = try DuckPolicy.load(contentsOf: try Self.file(of: network))
            XCTAssertEqual(DuckOfficialPolicies.standing(of: policy), .unrecognised, network.fileName)
        }
    }

    func testOnlyTheTwoTheRoutineDrivesAreBundled() {
        XCTAssertEqual(MicroDock.networks.filter(\.bundled), [MicroDock.scootBack, MicroDock.scootOut])
        XCTAssertEqual(MicroDock.networks.filter(\.experimental), [MicroDock.scootBoth])
        XCTAssertEqual(MicroDock.networks.map(\.title),
                       ["Scoot back (dock)", "Scoot out (undock)", "Scoot both ways (experimental)"])
    }

    func testTheSourceIsPinnedToOneCommit() {
        XCTAssertEqual(MicroDock.shortCommit, "c1ba96f")
        XCTAssertEqual(MicroDock.scootBoth.sourceURL.absoluteString,
                       "https://raw.githubusercontent.com/Vottivott/microduck-playground/"
                     + "c1ba96f596df5e99829cbb6590971eca97d96e2d/hardware/microdock-v2/policy/experimental/scoot_dock_undock.onnx")
        XCTAssertEqual(MicroDock.page.absoluteString, "https://microduckstudio.com/dock/")
        XCTAssertTrue(MicroDock.credit.contains("c1ba96f"))
        XCTAssertTrue(MicroDock.credit.contains("Apache-2.0"))
        XCTAssertTrue(MicroDock.credit.contains("none of these has run on a robot"))
    }

    // MARK: - the library

    /// A copy saved under its digest comes back under its own name and title, and as community
    /// work, not as a Pollen release.
    func testTheLibraryNamesThemByTheirWeights() throws {
        for network in MicroDock.networks {
            let data = try Data(contentsOf: try Self.file(of: network))
            let digestName = "\(network.fingerprint).onnx"
            let saved = PolicyLibrary.entry(for: data, name: digestName, origin: .imported)
            XCTAssertEqual(saved.title, network.title)
            XCTAssertEqual(saved.titleSource, .recognised)
            XCTAssertEqual(saved.fileName, network.fileName)
            XCTAssertEqual(saved.identity, .parameters(network.fingerprint))
            XCTAssertTrue(saved.isRunnable, network.fileName)

            let renamedOnTheWay = PolicyLibrary.entry(for: data, name: "my_dock.onnx", origin: .imported)
            XCTAssertEqual(renamedOnTheWay.title, network.title, "the weights decide, not the envelope")
            XCTAssertEqual(renamedOnTheWay.fileName, "my_dock.onnx", "a real name is never overwritten")
        }
    }

    func testAPersonsOwnNameStillWins() {
        let (title, source) = PolicyLibrary.titleLadder(
            typed: "Bedtime", release: nil, manifestName: nil, fileName: "scoot_dock.onnx",
            identity: .parameters(MicroDock.scootBack.fingerprint), recognised: MicroDock.scootBack)
        XCTAssertEqual(title, "Bedtime")
        XCTAssertEqual(source, .typed)
    }

    // MARK: - the routine

    func testTheRoutineIsUpstreamsSequence() {
        let steps = DockRoutine.steps
        XCTAssertEqual(steps.map(\.phase), [.sit, .handOver, .scootBack, .rest, .scootOut, .still, .stand])
        XCTAssertEqual(steps.map(\.role), [.sitStand, .scootBack, .scootBack, .scootBack,
                                           .scootOut, .scootOut, .sitStand])
        // docking_seated.py: --sit_s 4.0, --handover_s 0.5, --vback -0.05, --hold 3.0;
        // scoot_dock_commands.json: seconds 4.0; undocking_seated.py undock(): 0.05 until 70 mm or
        // 500 steps, 25 still, 175 standing.
        XCTAssertEqual(steps.map(\.vx), [1, 0, -0.05, 0, 0.05, 0, 0])
        XCTAssertEqual(steps.map(\.seconds), [4.0, 0.5, 4.0, 3.0, 10.0, 0.5, 3.5])
        XCTAssertEqual(steps.map(\.untilMetres), [nil, nil, nil, nil, 0.070, nil, nil])
        for step in steps { XCTAssertFalse(step.source.isEmpty, "\(step.phase) cites nothing") }
    }

    func testEachStepIsSentInHoldsTheBenchAccepts() {
        for step in DockRoutine.steps {
            let holds = DockRoutine.holds(for: step)
            XCTAssertEqual(holds.reduce(0, +), step.seconds, accuracy: 1e-9)
            XCTAssertTrue(holds.allSatisfy { $0 > 0 && $0 <= DockRoutine.longestHold })
            if step.untilMetres != nil {
                XCTAssertTrue(holds.allSatisfy { $0 <= DockRoutine.checkEvery + 1e-12 },
                              "a step with an end point looks at the duck every 0.1 s")
            }
        }
    }

    func testThePhoneBenchAlreadyHoldsEverything() throws {
        let held = ["alpha_sitstand.onnx", "alpha_stand.onnx", "velstand.onnx", "alpha_walking.onnx",
                    "scoot_dock.onnx", "scoot_undock.onnx"]
        let plan = try DockRoutine.plan(benchHolds: held, startedOn: "velstand.onnx").get()
        XCTAssertEqual(plan, DockRoutine.Plan(sitStand: "alpha_sitstand.onnx", scootBack: "scoot_dock.onnx",
                                              scootOut: "scoot_undock.onnx", handBack: "velstand.onnx"))
    }

    func testADeskBenchIsSentTheScootNetworksAndHandsBackToTheWalk() throws {
        let held = ["alpha_sitstand.onnx", "BEST_alpha_stand.onnx", "alpha_walking.onnx"]
        let plan = try DockRoutine.plan(benchHolds: held, startedOn: "alpha_sitstand.onnx").get()
        XCTAssertNil(plan.scootBack)
        XCTAssertNil(plan.scootOut)
        XCTAssertEqual(plan.handBack, "alpha_walking.onnx",
                       "a duck that started on the routine's own network goes back to the walk")
        XCTAssertEqual(DockRoutine.uploadName(MicroDock.scootBack), "scoot_dock")
    }

    func testABenchWithNoSitStandIsRefusedBeforeAnythingMoves() {
        XCTAssertEqual(DockRoutine.plan(benchHolds: ["alpha_walking.onnx"], startedOn: nil),
                       .failure(.noSitStand))
    }

    // MARK: - the run, against a bench that answers

    private actor FakeBench {
        var calls: [DuckBench.Call] = []
        var policy = "alpha_walking.onnx"
        var x = 0.0, t = 0.0
        let holds: [String]

        init(holds: [String]) { self.holds = holds }

        func answer(_ call: DuckBench.Call) -> Data {
            calls.append(call)
            let body = call.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            switch call.url.path {
            case "/health":
                return json(["bench": "duckbench", "policies": holds])
            case "/upload":
                return json(["policy": body["name"] as? String ?? "uploaded-x"])
            case "/policy":
                policy = body["policy"] as? String ?? policy
            case "/intent":
                // A bench where a scoot network moves at its command and nothing else moves.
                let vx = body["vx"] as? Double ?? 0, hold = body["hold"] as? Double ?? 0
                if policy.hasPrefix("scoot") { x += vx * hold }
                t += hold
            default: break
            }
            return json(["t": t, "joints": [Double](repeating: 0, count: DuckModel.policyJointCount),
                         "height": policy == "alpha_sitstand.onnx" ? 0.116 : 0.06, "upright": true,
                         "position": [x, 0, 0.06], "quaternion": [1, 0, 0, 0], "policy": policy,
                         "command": ["vx": 0.0, "vy": 0.0, "vyaw": 0.0]])
        }

        private func json(_ v: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: v) }
    }

    func testTheRunUploadsWhatIsMissingDrivesEachStepAndHandsBack() async throws {
        let bench = FakeBench(holds: ["alpha_sitstand.onnx", "alpha_walking.onnx"])
        let peer = try BenchPeer(address: DuckBench.Address(host: "127.0.0.1", port: 1)) { await bench.answer($0) }
        let outcome = try await peer.runDock(bundled: { _ in Data([1, 2, 3]) }, said: { _ in })

        let calls = await bench.calls
        let paths = calls.map(\.url.path)
        XCTAssertEqual(Array(paths.prefix(3)), ["/health", "/upload", "/upload"])
        let loads = calls.filter { $0.url.path == "/policy" }.compactMap {
            ($0.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })?["policy"] as? String
        }
        XCTAssertEqual(loads, ["alpha_sitstand.onnx", "scoot_dock", "scoot_dock", "scoot_dock",
                               "scoot_undock", "scoot_undock", "alpha_sitstand.onnx", "alpha_walking.onnx"])
        for call in calls { XCTAssertTrue(DuckBench.routes.contains(call.url.path), call.url.path) }

        // 4.0 s at -0.05 on this bench, and out until 70 mm at 0.05 in 0.1 s pieces.
        XCTAssertEqual(outcome.scootedBack, -0.2, accuracy: 1e-9)
        XCTAssertEqual(outcome.scootedOut, 0.070, accuracy: 0.0051)
        XCTAssertLessThan(outcome.scootOutSeconds, 10.0, "the scoot out ends at 70 mm, not at its cap")
        XCTAssertTrue(outcome.uprightThroughout)
        XCTAssertTrue(outcome.sentence.hasPrefix("Scooted back 200 mm and out 7"), outcome.sentence)
        XCTAssertTrue(outcome.sentence.hasSuffix("then stood up. Practice duck, no dock."), outcome.sentence)
    }

    func testAMissingBundledNetworkIsRefusedBeforeAnythingMoves() async throws {
        let bench = FakeBench(holds: ["alpha_sitstand.onnx"])
        let peer = try BenchPeer(address: DuckBench.Address(host: "127.0.0.1", port: 1)) { await bench.answer($0) }
        do {
            _ = try await peer.runDock(bundled: { _ in nil }, said: { _ in })
            XCTFail("ran without its networks")
        } catch let refusal as DockRoutine.Refusal {
            XCTAssertEqual(refusal, .notBundled("scoot_dock.onnx"))
        }
        let paths = await bench.calls.map(\.url.path)
        XCTAssertEqual(paths, ["/health"])
    }

    func testACancelledRunSendsNothingMore() async throws {
        let bench = FakeBench(holds: ["alpha_sitstand.onnx", "scoot_dock.onnx", "scoot_undock.onnx"])
        let peer = try BenchPeer(address: DuckBench.Address(host: "127.0.0.1", port: 1)) { await bench.answer($0) }
        let task = Task { try await peer.runDock(bundled: { _ in nil }, said: { phase in
            if phase == .scootBack { withUnsafeCurrentTask { $0?.cancel() } }
        }) }
        do {
            _ = try await task.value
            XCTFail("a cancelled run finished")
        } catch is CancellationError {}
        let loads = await bench.calls.filter { $0.url.path == "/policy" }.count
        XCTAssertEqual(loads, 2, "the sit and the hand-over, and nothing after the cancel")
    }

    // MARK: - the words

    func testTheWordsArePlainAndTheRealDuckReasonIsOneSentence() {
        for line in DockRoutine.Words.all + [MicroDock.credit] + MicroDock.networks.flatMap({ [$0.title, $0.purpose] })
            + DockRoutine.Phase.allCases.map(\.caption) {
            XCTAssertFalse(line.unicodeScalars.contains("\u{2014}"), line)
        }
        let real = DockRoutine.Words.realDuck
        XCTAssertEqual(real.filter { $0 == "." }.count, 1, real)
        XCTAssertTrue(real.hasSuffix("."))
        XCTAssertTrue(real.contains("robotd"))
        XCTAssertEqual(DockRoutine.Refusal.realDuck.sentence, real)
    }
}
