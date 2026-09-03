import XCTest
import DuckKit
@testable import StudioKit

/// A `/climb` cell that also answers with a picture, and the world that
/// picture is of.
///
/// THE CLIP IS A RENDER FLAG AND MUST NEVER TOUCH THE IDENTITY. The bench takes
/// `intentHash` over the `intent` object it receives, key order included, so a
/// `clip` key inside it would key the leaderboard by whether somebody asked to
/// watch. It rides on the request beside `rise`, `cell` and `tail`, and these
/// tests hold that line from the client's side.
final class DuckBenchClimbTests: XCTestCase {

    let address = DuckBench.Address(host: "127.0.0.1", port: 8770)

    private func captured(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/bench/\(name)",
                                                  withExtension: "json"),
                                "the \(name) fixture is missing")
        return try Data(contentsOf: url)
    }

    // MARK: - what goes out

    func testAClimbCallCarriesClipOnTheBodyAndNotInTheIntent() throws {
        let file = try StairsChallenge.intentData(named: "best_r6_ceilvaultC_60mm")
        let call = try DuckBench.climb(address, intent: file, rise: 0.060,
                                       cell: StairsChallenge.Grid.nominal, clip: true)
        let body = try HarnessJSON.parse(try XCTUnwrap(call.body))
        XCTAssertEqual(body.members?.map(\.key), ["intent", "rise", "cell", "tail", "clip"])
        XCTAssertEqual(body["clip"]?.boolValue, true)

        let intent = try XCTUnwrap(body["intent"])
        XCTAssertNil(intent["clip"], "a render flag must not reach the hashed object")
        XCTAssertEqual(intent.encoded(.pretty), file, "the intent is the file, byte for byte")
    }

    /// ABSENT, NOT FALSE, WHEN NOBODY ASKED: a scored cell without a clip has
    /// to be the request it has always been.
    func testACellScoredWithoutAClipSendsTheBodyItAlwaysSent() throws {
        let file = try StairsChallenge.intentData(named: "ctrl_do_nothing")
        let call = try DuckBench.climb(address, intent: file, rise: 0.060,
                                       cell: StairsChallenge.Grid.nominal)
        let body = try HarnessJSON.parse(try XCTUnwrap(call.body))
        XCTAssertEqual(body.members?.map(\.key), ["intent", "rise", "cell", "tail"])
    }

    // MARK: - what comes back

    func testAClimbAnswerWithAClipBecomesADrawableClip() throws {
        let data = try captured("climb-clip")
        let clip = try XCTUnwrap(try DuckBench.readClimbedClip(data, named: "lever_up"))
        XCTAssertEqual(clip.hz, DuckModel.tickHz)
        XCTAssertEqual(clip.frames.count, 211)
        XCTAssertEqual(clip.roots.count, 211)
        for frame in clip.frames { XCTAssertEqual(frame.count, 14) }
        XCTAssertEqual(clip.telemetry.commands.count, 211)

        let climbed = try DuckBench.readClimbed(data)
        XCTAssertEqual(climbed.clipTicks, 211)
        XCTAssertEqual(climbed.stable, true)
    }

    /// THE FIRST BENCH RECORDING IN THIS APP THAT ARRIVES WITH A REAL WORLD.
    func testAClimbClipCarriesTheFlightItRanOn() throws {
        let data = try captured("climb-clip")
        let climbed = try DuckBench.readClimbed(data)
        let stood = try XCTUnwrap(climbed.stood)
        XCTAssertEqual(stood.steps.count, 4)
        for (step, top) in zip(stood.steps, [0.06, 0.12, 0.18, 0.24]) {
            XCTAssertEqual(step.top, top, accuracy: 1e-4)
            XCTAssertEqual(step.y, 1.305, accuracy: 1e-9)
        }
        let clip = try XCTUnwrap(try DuckBench.readClimbedClip(data, named: "lever_up"))
        XCTAssertNotEqual(clip.environment, .bareFloor)
        XCTAssertEqual(clip.environment.steps.count, 4)
    }

    /// A cell scored without a clip is a complete answer, not a failure.
    func testAClimbAnswerWithNoClipStillReads() throws {
        let plain = Data(#"""
        {"hash":"a56d459fb649","rise":0.06,"cell":{"dh":0,"drop":0.12,"fmul":1},
         "honest":true,"stable":true,"uprightTailTicks":50,"tailTicks":50,
         "above_mm":116.17,"x_mm":237.36,"dy_mm":17.62,"feetOnTread":2,
         "peakAboveTread_mm":121.71,"maxTq":0.6405,"reachedFlight":true,"invalid":false,
         "criterion":"honest: …","seconds":0.48}
        """#.utf8)
        XCTAssertNil(try DuckBench.readClimbedClip(plain, named: "x"))
        let climbed = try DuckBench.readClimbed(plain)
        XCTAssertNil(climbed.stood)
        XCTAssertNil(climbed.clipTicks)
        XCTAssertEqual(climbed.uprightTailTicks, 50)
        XCTAssertEqual(climbed.cell, StairsChallenge.Grid.nominal)
    }

    /// A one-cell answer is stored as a `CellOutcome`, which knows it is not a
    /// score.
    func testACellOutcomeKeepsTheWorldTheCellStoodIn() throws {
        let cell = Pipeline.CellOutcome(try DuckBench.readClimbed(try captured("climb-clip")),
                                        when: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(cell.laid?.steps.count, 4)
        XCTAssertEqual(cell.laid?.bankCount, 14)
        XCTAssertEqual(cell.laid?.parked, 10)
        XCTAssertNil(cell.laid?.spawn, "a climb answer carries no spawn block")
        XCTAssertTrue(cell.told.contains("fourteen"), cell.told)
    }
}
