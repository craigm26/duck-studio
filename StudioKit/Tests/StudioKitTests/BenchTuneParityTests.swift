import XCTest
import DuckKit
import DuckEvidence
@testable import StudioKit

/// The two claims `/tune` rests on, checked against the other language.
///
/// WHY THIS FILE IS DIFFERENT FROM EVERY OTHER TEST HERE. Everything else in
/// this suite asserts that StudioKit says what it means to say. These two tests
/// assert that a program in ANOTHER REPOSITORY, in another language, computes
/// the same numbers — because `/tune` on the duck bench now folds a per-joint
/// gain into a network and weighs the run against Pollen's reward, and both of
/// those already exist here: `DuckPolicyWriter.folding` defines what a gain and
/// a trim mean, and `RunMetrics` defines what each reward term is. A second
/// implementation of either is the classic place for two plausible numbers to
/// disagree forever, so the two implementations are pinned to each other by
/// artefacts rather than by care.
///
/// NEITHER TEST NEEDS THE BENCH TO BE RUNNING, AND THAT IS DELIBERATE. A gate
/// that only works when a Pi is up is a gate that gets skipped. What crosses
/// the gap is files:
///
///   • THE TRACE. `Fixtures/tune/trace.json` is fifty control ticks the bench
///     recorded — trunk pose, the trunk's twist, fourteen joint angles, the
///     network's own fourteen outputs and the command, per tick — WITH the six
///     term values the bench computed from them. This test recomputes those six
///     through `RunMetrics` and requires agreement. `sim/tune_parity.mjs` in
///     duck-sounds recomputes them through the bench's own `rewardSums` and
///     requires the same. Change either transcription and exactly one side goes
///     red, which is the whole point.
///
///   • THE FOLD. The second test writes a policy folded by this package's own
///     writer, with a fixed gain and trim, to `StudioKit/.build/fold-fixture/`.
///     `sim/tune_parity.mjs` folds the same base with the bench's arithmetic
///     and compares the canonical bytes. Bytes, not behaviour: a fold that
///     agrees to five decimals is a different network from the one the app will
///     write, and the search would be scoring the wrong one.
final class BenchTuneParityTests: XCTestCase {

    // MARK: - the six terms, out of a trace the bench recorded

    /// What the fixture carries. Field for field, this is what a bench holds
    /// during one control tick and what no bench ANSWER has ever carried: the
    /// twist and the action are exactly the two things `/state` and `/record`
    /// cannot report, and four of the six terms cannot be computed without them.
    private struct Trace: Decodable {
        struct Tick: Decodable {
            /// x, y, z, qw, qx, qy, qz.
            let root: [Double]
            /// MuJoCo's own free-joint velocity: linear in the WORLD frame,
            /// angular in the BODY's. Carried so the bench's rotation into the
            /// trunk can be checked rather than trusted.
            let qvel: [Double]
            /// The same velocity as a clip stores it — the trunk's twist in its
            /// OWN frame, (vx, vy, vz, wx, wy, wz).
            let twist: [Double]
            let joints: [Double]
            let action: [Double]
            /// vx, vy, vyaw.
            let command: [Double]
        }
        let policy: String
        let hz: Double
        let ticks: [Tick]
        let terms: [String: Double]
        let tolerance: Double
        /// The bench's own `travelled` for this trace: the signed projection
        /// of the driven span's displacement onto the commanded direction, in
        /// the frame the duck started the span in.
        let travelled: Double
        let netDisplacement: Double
    }

    /// TWO FIXTURES, BECAUSE ONE CANNOT FAIL ON THREE THINGS. `trace` commands
    /// only vx, so a wrong sign on the commanded yaw rate, a swapped vy index
    /// or the turn-tracking term reading the wrong command all pass it.
    /// `trace-turning` commands vx, vy and vyaw at once.
    private static let fixtures = ["trace", "trace-turning"]

    private func trace(_ name: String = "trace") throws -> Trace {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json",
                                                  subdirectory: "Fixtures/tune"),
                                "missing Fixtures/tune/\(name).json — regenerate it with "
                              + "`node sim/tune_parity.mjs --emit` in duck-sounds")
        return try JSONDecoder().decode(Trace.self, from: Data(contentsOf: url))
    }

    /// A clip that carries exactly what the bench recorded, so `RunMetrics`
    /// scores the bench's own trace rather than a reconstruction of it.
    ///
    /// `policy` IS LOAD-BEARING AND NOT DECORATION. `RunMetrics.Task.forPolicy`
    /// picks the config off the filename, and only the velocity family has the
    /// three terms this fixture is mostly about; a clip that named a different
    /// policy would be scored under different weights and would quietly report
    /// three terms fewer.
    private func clip(_ t: Trace) -> DuckIntentClip {
        DuckIntentClip(
            name: "tune-parity",
            hz: t.hz,
            frames: t.ticks.map(\.joints),
            roots: t.ticks.map {
                DuckIntentClip.Root(x: $0.root[0], y: $0.root[1], z: $0.root[2],
                                    quaternion: ($0.root[3], $0.root[4], $0.root[5], $0.root[6]))
            },
            netYaw: 0, loops: false, startsFrom: .standing, endsIn: .standing,
            policy: t.policy, authored: false,
            environment: DuckIntentClip.Environment(ground: true, yaw: 0, steps: [], walls: []),
            telemetry: DuckIntentClip.Telemetry(actions: t.ticks.map(\.action),
                                                commands: t.ticks.map(\.command),
                                                twists: t.ticks.map(\.twist)))
    }

    func testTheBenchScoresTheSameSixTermsThisKitDoes() throws {
        for name in Self.fixtures { try sixTermsAgree(on: name) }
    }

    /// The turning fixture has to actually turn and step sideways, or it
    /// pins nothing the walking one does not.
    func testTheTurningFixtureCommandsEveryAxis() throws {
        let fixture = try trace("trace-turning")
        let commands = fixture.ticks.map(\.command)
        XCTAssertTrue(commands.contains { $0[1] != 0 }, "no vy was commanded")
        XCTAssertTrue(commands.contains { $0[2] != 0 }, "no vyaw was commanded")
        let yawRates = fixture.ticks.map { $0.twist[5] }
        XCTAssertGreaterThan(yawRates.map(abs).max() ?? 0, 0.05, "the duck never turned")
    }

    private func sixTermsAgree(on name: String) throws {
        let fixture = try trace(name)
        XCTAssertGreaterThan(fixture.ticks.count, 40,
                             "\(name): a handful of ticks would agree by accident")
        let metrics = RunMetrics(clip: clip(fixture))
        XCTAssertEqual(metrics.task, .velocity,
                       "the fixture has to be scored under the config the bench scored it under")

        var seen: [String: Double] = [:]
        for term in metrics.rewards {
            guard case .evaluated(let mean, _) = term.standing else {
                return XCTFail("\(term.name) came back unevaluated: \(term.standing)")
            }
            seen[term.name] = mean
        }
        // Every term the tuner will ask the bench for, and nothing missing:
        // two of the six weights are negative, so a term quietly absent reads
        // as the best possible value of the thing it punishes.
        for term in DuckTuner.terms {
            let mine = try XCTUnwrap(seen[term.key], "RunMetrics did not evaluate \(term.key)")
            let theirs = try XCTUnwrap(fixture.terms[term.key],
                                       "the bench did not record \(term.key)")
            XCTAssertEqual(mine, theirs, accuracy: fixture.tolerance,
                           "\(term.key): this kit says \(mine), the bench said \(theirs)")
        }
        // And the weighted sum, which is the number a search actually climbs.
        XCTAssertEqual(try DuckTuner.reward(seen), try DuckTuner.reward(fixture.terms),
                       accuracy: fixture.tolerance)
    }

    /// `travelled` — the number the walk guard and the objective rest on —
    /// recomputed here from the fixture's roots and commands, so the gate is
    /// not the bench's function checked against a number the same function
    /// wrote. The definition: sum the commanded (vx, vy) over the span, take
    /// its direction, rotate that direction into the world by the yaw the
    /// trunk had at the FIRST driven tick, and project the net displacement
    /// (last root minus first) onto it. With no linear command anywhere the
    /// plain net displacement stands in.
    func testTravelledIsTheProjectionOfTheDisplacementOntoTheCommand() throws {
        for name in Self.fixtures {
            let fixture = try trace(name)
            let first = fixture.ticks[0].root, last = fixture.ticks[fixture.ticks.count - 1].root
            let dx = last[0] - first[0], dy = last[1] - first[1]
            var sx = 0.0, sy = 0.0
            for tick in fixture.ticks { sx += tick.command[0]; sy += tick.command[1] }
            let magnitude = (sx * sx + sy * sy).squareRoot()
            let net = (dx * dx + dy * dy).squareRoot()
            XCTAssertEqual(net, fixture.netDisplacement, accuracy: fixture.tolerance, name)
            guard magnitude > 1e-12 else {
                return XCTAssertEqual(net, fixture.travelled, accuracy: fixture.tolerance, name)
            }
            let ux = sx / magnitude, uy = sy / magnitude
            let (w, x, y, z) = (first[3], first[4], first[5], first[6])
            let yaw = atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))
            let wx = ux * cos(yaw) - uy * sin(yaw), wy = ux * sin(yaw) + uy * cos(yaw)
            let mine = dx * wx + dy * wy
            XCTAssertEqual(mine, fixture.travelled, accuracy: fixture.tolerance,
                           "\(name): this kit projects \(mine), the bench said \(fixture.travelled)")
            // And it is a real walk in both fixtures, not a rounding of zero.
            XCTAssertGreaterThan(abs(mine), 0.02, name)
        }
    }

    /// The one place the two languages could agree on every formula and still
    /// describe different physics: MuJoCo keeps a free joint's LINEAR velocity
    /// in the world frame and its ANGULAR velocity in the body's, and a clip
    /// stores both in the body's. Rotating the wrong half is invisible for a
    /// duck walking due north and wrong for every other heading, so the fixture
    /// carries the raw velocity as well and the rotation is checked here.
    func testTheTwistInTheFixtureIsTheWorldVelocityRotatedIntoTheTrunk() throws {
        for name in Self.fixtures { try twistAgrees(on: name) }
    }

    private func twistAgrees(on name: String) throws {
        let fixture = try trace(name)
        var worst = 0.0
        for tick in fixture.ticks {
            let q = (tick.root[3], tick.root[4], tick.root[5], tick.root[6])
            // The conjugate rotates a world vector into the body.
            let conjugate = (q.0, -q.1, -q.2, -q.3)
            let body = RunMetrics.rotate(conjugate, (tick.qvel[0], tick.qvel[1], tick.qvel[2]))
            worst = max(worst, abs(body.0 - tick.twist[0]))
            worst = max(worst, abs(body.1 - tick.twist[1]))
            worst = max(worst, abs(body.2 - tick.twist[2]))
            // The angular half is already the body's and must not have moved.
            for k in 0..<3 { worst = max(worst, abs(tick.qvel[3 + k] - tick.twist[3 + k])) }
        }
        XCTAssertLessThan(worst, fixture.tolerance,
                          "the fixture's twist is not this kit's rotation of its own velocity")
    }

    // MARK: - the probe, against an answer a real bench actually sent

    /// `DuckBench.readTuned` against a `/tune` answer CAPTURED FROM THE BENCH,
    /// not composed here.
    ///
    /// WHY A CAPTURE AND NOT ANOTHER HAND-WRITTEN STRING. `DuckBenchTests`
    /// already reads a `/tune` body written to match the reader, which proves
    /// the reader parses what this repository imagines. It cannot catch the one
    /// failure that actually costs a release: a bench that answers with
    /// `standing` as a string, or `perDrop` under another name, or an `episodes`
    /// that JSON made a Double — every one of which leaves the reader throwing
    /// `.empty` and the screen saying "this bench cannot score a search" about a
    /// bench that can. This body came off 100.122.199.6:8770 on 2026-09-02, from
    /// exactly the request `TuneView.probe` sends: `alpha_walking.onnx`, the
    /// identity residual, one second, one drop of 0.1231 m,
    /// `DuckBench.walkingCommand`, all six terms.
    func testItReadsAnAnswerTheBenchActuallySent() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "tune-identity-probe",
                                                  withExtension: "json",
                                                  subdirectory: "Fixtures/bench"))
        let tuned = try DuckBench.readTuned(try Data(contentsOf: url))
        XCTAssertEqual(tuned.policy, "alpha_walking.onnx")
        XCTAssertEqual(tuned.episodes, 1)
        XCTAssertEqual(tuned.standing, 1)
        XCTAssertEqual(tuned.plantName, "scene.mjb")
        XCTAssertEqual(tuned.plantDigest?.prefix(12), "3f8c9ab9b409")
        XCTAssertTrue(tuned.refused.isEmpty,
                      "the bench computes all six; anything in `refused` here is a regression")
        XCTAssertEqual(tuned.perDrop.count, 1)
        XCTAssertEqual(tuned.perDrop.first?.drop, 0.1231)
        XCTAssertEqual(tuned.perDrop.first?.standing, true)
        // The whole gate the probe exists to be: every term present, so the
        // reward computes and the Start button is allowed to appear.
        XCTAssertNoThrow(try DuckTuner.reward(tuned.terms))
        for term in DuckTuner.terms {
            XCTAssertNotNil(tuned.terms[term.key], "the bench did not answer \(term.key)")
        }
        XCTAssertEqual(DuckTuner.readiness(for: .benchComputesThem).canSearch, true)
        // And it went somewhere, which is the number that keeps the reward
        // honest. 94.9 mm in one second, of which the first half is the settle.
        XCTAssertGreaterThan(tuned.travelled, 0.05)
        XCTAssertFalse(tuned.criterion.isEmpty,
                       "the bench has to say what `standing` means in its own words")
    }

    // MARK: - the fold, as bytes

    /// A gain and a trim chosen to be AWKWARD rather than tidy.
    ///
    /// 1.07 and 0.93 are not representable in binary32, which is the whole
    /// question: Swift rounds the gain to `Float` and then multiplies two
    /// binary32s, and a JavaScript transcription that multiplies a binary32
    /// weight by a binary64 gain gets a different last bit. Gains of 1.0 and
    /// 1.5 would hide that difference completely. The head slots are left at
    /// identity, as the search leaves them, so the test also proves an untouched
    /// slot comes back byte-identical.
    private static let gain: [Double] = [
        1.07, 0.93, 1.13, 0.87, 1.21,
        1, 1, 1, 1,
        0.79, 1.03, 0.9700000000000001, 1.29, 0.71,
    ]
    private static let trim: [Double] = [
        0.0123, -0.0456, 0.007, -0.0089, 0.0331,
        0, 0, 0, 0,
        -0.0202, 0.0011, -0.0333, 0.0444, -0.005,
    ]

    /// Write the base and the folded network out, for duck-sounds to fold the
    /// same base and compare.
    ///
    /// WHY `.build` AND NOT A TEMPORARY DIRECTORY. `NSTemporaryDirectory()` is
    /// a different path on every run and on every machine, so a Node script
    /// could not find it without being told — and a gate that has to be told
    /// where its input is, is a gate that runs once. `.build` is beside the
    /// package, is already ignored by git, and is where a reviewer can look.
    /// The fixture is a build product; `swift test` produces it, and
    /// `node sim/tune_parity.mjs` consumes it.
    func testItWritesAFoldedPolicyForTheBenchToMatch() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "alpha_walking",
                                                  withExtension: "onnx",
                                                  subdirectory: "Fixtures/policies"))
        let base = try DuckPolicy.load(contentsOf: url)
        let folded = try DuckPolicyWriter.folding(policy: base,
                                                  gain: Self.gain, offset: Self.trim)

        // The fold is exact arithmetic on the last layer alone, and this is the
        // assertion that says so in THIS language before anything is written for
        // the other one: every layer but the last is untouched, and the last
        // one is the base's scaled and shifted.
        let a = base.parameters, b = folded.parameters
        XCTAssertEqual(a.layers.count, b.layers.count)
        for index in 0..<(a.layers.count - 1) {
            XCTAssertEqual(a.layers[index].weights, b.layers[index].weights,
                           "layer \(index) moved, and only the last one may")
            XCTAssertEqual(a.layers[index].biases, b.layers[index].biases)
        }
        XCTAssertEqual(a.mean, b.mean)
        XCTAssertEqual(a.std, b.std)
        let last = a.layers[a.layers.count - 1], tuned = b.layers[b.layers.count - 1]
        for slot in 0..<last.outputs {
            let g = Float(Self.gain[slot])
            XCTAssertEqual(tuned.biases[slot], last.biases[slot] * g + Float(Self.trim[slot]))
            let row = slot * last.inputs
            XCTAssertEqual(tuned.weights[row], last.weights[row] * g)
            XCTAssertEqual(tuned.weights[row + last.inputs - 1],
                           last.weights[row + last.inputs - 1] * g)
        }

        let out = URL(fileURLWithPath: #filePath)      // …/Tests/StudioKitTests/<this file>
            .deletingLastPathComponent()               // …/Tests/StudioKitTests
            .deletingLastPathComponent()               // …/Tests
            .deletingLastPathComponent()               // …/StudioKit
            .appendingPathComponent(".build/fold-fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try base.canonicalParameterBytes
            .write(to: out.appendingPathComponent("base.bin"), options: .atomic)
        try folded.canonicalParameterBytes
            .write(to: out.appendingPathComponent("folded.bin"), options: .atomic)
        let recipe: [String: Any] = [
            "why": "Written by BenchTuneParityTests in StudioKit. base.bin is "
                 + "alpha_walking.onnx as DuckPolicy.canonicalParameterBytes; folded.bin is the "
                 + "same network after DuckPolicyWriter.folding with the gain and trim below. "
                 + "duck-sounds' sim/tune_parity.mjs folds base.bin with the bench's own "
                 + "arithmetic and must reproduce folded.bin byte for byte.",
            "policy": "alpha_walking.onnx",
            "gain": Self.gain,
            "trim": Self.trim,
            "baseFingerprint": base.fingerprint,
            "foldedFingerprint": folded.fingerprint,
        ]
        try JSONSerialization.data(withJSONObject: recipe, options: [.prettyPrinted, .sortedKeys])
            .write(to: out.appendingPathComponent("fold.json"), options: .atomic)

        // A fold that changed nothing would write two identical files and the
        // Node side would pass against the wrong thing.
        XCTAssertNotEqual(base.canonicalParameterBytes, folded.canonicalParameterBytes)
        XCTAssertEqual(base.canonicalParameterBytes.count, folded.canonicalParameterBytes.count,
                       "a fold adds no parameters; it is the same file with a different last layer")
    }
}
