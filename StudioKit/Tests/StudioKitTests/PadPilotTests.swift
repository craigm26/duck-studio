import XCTest
import DuckKit
import DuckEvidence
@testable import StudioKit

/// The one loop, in three states.
///
/// THE PROPERTY THIS FILE EXISTS FOR is the last test: whatever state the pilot
/// is in and whatever it is handed, `step` returns exactly one command. A
/// replay written as a second `Task` would have produced two intent streams at
/// one bench with Stop able to cancel only the newest; here a replay is a state
/// of the loop, and the type makes the alternative unspellable.
final class PadPilotTests: XCTestCase {

    private let forward = DuckDrive.Twist(vx: 0.3, vy: 0, vyaw: 0)
    private let turning = DuckDrive.Twist(vx: 0, vy: 0, vyaw: 1.5)
    private let walking = "alpha_walking.onnx"
    private let clock = Date(timeIntervalSince1970: 0)

    private func sequence(_ steps: [DuckSequence.Step]) throws -> DuckSequence {
        try DuckSequence.make(steps: steps, named: "a take", provenance: .said("x"),
                              wallSeconds: 0, venue: .sim, at: clock)
    }

    private func twoSteps() throws -> DuckSequence {
        try sequence([DuckSequence.Step(atSim: 0, twist: forward, policySaid: walking),
                      DuckSequence.Step(atSim: 1, twist: turning, policySaid: walking)])
    }

    // MARK: - steering

    func testSteeringPassesTheSticksThrough() {
        var pilot = PadPilot()
        let go = pilot.step(steering: forward, simSeconds: 5, policySaid: walking,
                            wanting: nil, now: clock)
        XCTAssertEqual(go.command, forward)
        XCTAssertNil(go.load)
        XCTAssertNil(go.note)
        XCTAssertNil(pilot.line)
    }

    func testTheLineIsNilWhileMerelySteering() {
        var pilot = PadPilot()
        _ = pilot.step(steering: .still, simSeconds: nil, policySaid: nil,
                       wanting: nil, now: clock)
        XCTAssertNil(pilot.line)
        XCTAssertFalse(pilot.isRecording)
        XCTAssertFalse(pilot.isPlaying)
    }

    func testTheLoadIsSurfacedOnceEvenWhenTheMapKeepsAskingForIt() {
        var pilot = PadPilot()
        var surfaced = 0
        for _ in 0..<5 {
            let go = pilot.step(steering: forward, simSeconds: 1, policySaid: nil,
                                wanting: walking, now: clock)
            if go.load != nil { surfaced += 1 }
        }
        XCTAssertEqual(surfaced, 1, "a bench that refuses is not asked again every trip")
    }

    // MARK: - recording

    func testARecordingStampsFromTheBenchsClockAndNotTheStepCount() throws {
        var pilot = PadPilot()
        pilot.startRecording(venue: .sim, at: clock)
        for (index, stamp) in [5.0, 5.3, 5.4].enumerated() {
            _ = pilot.step(steering: index == 1 ? turning : forward,
                           simSeconds: stamp, policySaid: walking,
                           wanting: nil, now: clock)
        }
        // Three uneven stamps, three different commands... except the first and
        // the last are the same twist, so the take holds three steps only
        // because the middle one differed.
        pilot.cutOff(.tapped)
        let take = try XCTUnwrap(pilot.pending)
        XCTAssertEqual(take.steps.count, 3)
        for (step, expected) in zip(take.steps, [0.0, 0.3, 0.4]) {
            XCTAssertEqual(step.atSim, expected, accuracy: 1e-9,
                           "the bench's clock, not the step count")
        }
        XCTAssertFalse(pilot.isRecording)
    }

    func testTheRecordingLineCountsWhatWasMeasured() {
        var pilot = PadPilot()
        pilot.startRecording(venue: .sim, at: clock)
        _ = pilot.step(steering: forward, simSeconds: 1, policySaid: walking,
                       wanting: nil, now: clock)
        XCTAssertEqual(pilot.line, PadPilot.recordingLine(simSeconds: 0, steps: 1))
        XCTAssertTrue(pilot.isRecording)
    }

    func testCutOffKeepsWhatWasDrivenAndNamesHowItEnded() {
        for ending: DuckSequence.Ending in [.tapped, .paused, .stop] {
            var pilot = PadPilot()
            pilot.startRecording(venue: .sim, at: clock)
            _ = pilot.step(steering: forward, simSeconds: 1, policySaid: walking,
                           wanting: nil, now: clock)
            pilot.cutOff(ending)
            XCTAssertNotNil(pilot.pending)
            XCTAssertEqual(pilot.pendingEnding, ending)
            XCTAssertFalse(PadPilot.endedBy(ending).isEmpty)
            pilot.discardPending()
            XCTAssertNil(pilot.pending)
        }
    }

    func testAClosedCeilingEndsTheTakeWithItsOwnSentence() {
        var pilot = PadPilot()
        pilot.startRecording(venue: .sim, at: clock)
        _ = pilot.step(steering: forward, simSeconds: 0, policySaid: walking,
                       wanting: nil, now: clock)
        let go = pilot.step(steering: forward, simSeconds: 31, policySaid: walking,
                            wanting: nil, now: clock)
        XCTAssertEqual(go.note, DuckSequence.Refusal
            .heldTooLong(DuckSequence.maximumMoveSeconds).message)
        XCTAssertFalse(pilot.isRecording, "the take closed itself")
        XCTAssertNotNil(pilot.pending, "and kept everything up to that point")
        XCTAssertEqual(pilot.pendingEnding, .ceiling(go.note ?? ""))
    }

    // MARK: - replay

    func testAReplayFollowsTheSimClockAndNotTheStepCount() throws {
        var pilot = PadPilot()
        pilot.play(try twoSteps(), thenLoading: nil)
        // Sparse stamps SKIP steps rather than stretching the recording out.
        XCTAssertEqual(pilot.step(steering: .still, simSeconds: 100, policySaid: walking,
                                  wanting: nil, now: clock).command, forward)
        XCTAssertEqual(pilot.step(steering: .still, simSeconds: 101, policySaid: walking,
                                  wanting: nil, now: clock).command, turning)
    }

    func testAReplayWithNoClockYetSendsStillRatherThanGuessing() throws {
        var pilot = PadPilot()
        pilot.play(try twoSteps(), thenLoading: nil)
        let go = pilot.step(steering: forward, simSeconds: nil, policySaid: nil,
                            wanting: nil, now: clock)
        XCTAssertEqual(go.command, .still)
        XCTAssertTrue(pilot.isPlaying)
    }

    func testAReplayThatRunsOffTheEndHandsTheSticksBackWithoutAnnouncing() throws {
        var pilot = PadPilot()
        pilot.play(try twoSteps(), thenLoading: nil)
        _ = pilot.step(steering: .still, simSeconds: 0, policySaid: walking,
                       wanting: nil, now: clock)
        let go = pilot.step(steering: forward, simSeconds: 99, policySaid: walking,
                            wanting: nil, now: clock)
        XCTAssertEqual(go.command, forward, "the thumbs take over")
        XCTAssertNil(go.note, "and nothing is announced")
        XCTAssertFalse(pilot.isPlaying)
    }

    func testAChainedSlotIsSurfacedOnceTheReplayFinishes() throws {
        var pilot = PadPilot()
        pilot.play(try twoSteps(), thenLoading: .roulade)
        _ = pilot.step(steering: .still, simSeconds: 0, policySaid: walking,
                       wanting: nil, now: clock)
        let finishing = pilot.step(steering: .still, simSeconds: 99, policySaid: walking,
                                   wanting: nil, now: clock)
        XCTAssertEqual(finishing.thenLoading, .roulade)
        let after = pilot.step(steering: .still, simSeconds: 100, policySaid: walking,
                               wanting: nil, now: clock)
        XCTAssertNil(after.thenLoading, "once, not on every trip after")
    }

    func testASwapInAReplayComesBackAsALoadBeforeTheCommand() throws {
        let swapped = try sequence([
            DuckSequence.Step(atSim: 0, twist: forward, policySaid: walking),
            DuckSequence.Step(atSim: 1, twist: turning, policySaid: "alpha_roulade.onnx"),
        ])
        var pilot = PadPilot()
        pilot.play(swapped, thenLoading: nil)
        _ = pilot.step(steering: .still, simSeconds: 0, policySaid: walking,
                       wanting: nil, now: clock)
        let go = pilot.step(steering: .still, simSeconds: 1, policySaid: walking,
                            wanting: nil, now: clock)
        XCTAssertEqual(go.load, "alpha_roulade.onnx")
        XCTAssertEqual(go.command, turning)
    }

    func testCutOffEndsAReplayImmediatelyAndReturnsToSteering() throws {
        var pilot = PadPilot()
        pilot.play(try twoSteps(), thenLoading: .roulade)
        _ = pilot.step(steering: .still, simSeconds: 0, policySaid: walking,
                       wanting: nil, now: clock)
        pilot.cutOff(.stop)
        XCTAssertFalse(pilot.isPlaying)
        XCTAssertNil(pilot.pending, "a replay has nothing to keep")
        let go = pilot.step(steering: forward, simSeconds: 1, policySaid: walking,
                            wanting: nil, now: clock)
        XCTAssertEqual(go.command, forward)
        XCTAssertNil(go.thenLoading, "and the chain goes with it")
    }

    func testThePlayingLineCountsSimSecondsAgainstTheTakesOwnLength() throws {
        var pilot = PadPilot()
        pilot.play(try twoSteps(), thenLoading: nil)
        _ = pilot.step(steering: .still, simSeconds: 10, policySaid: walking,
                       wanting: nil, now: clock)
        _ = pilot.step(steering: .still, simSeconds: 10.5, policySaid: walking,
                       wanting: nil, now: clock)
        XCTAssertEqual(pilot.line, PadPilot.playingLine(name: "a take", at: 0.5, of: 1))
    }

    // MARK: - the property

    /// FOR ANY STATE AND ANY INPUT, EXACTLY ONE COMMAND. `Go.command` is not
    /// optional and there is no second door, so this walks the matrix and
    /// asserts the loop always has precisely one thing to send.
    func testTheresNeverMoreThanOneThingToSendPerRoundTrip() throws {
        let take = try twoSteps()
        let clocks: [Double?] = [nil, 0, 0.5, 1, 99]
        let steers = [DuckDrive.Twist.still, forward, turning]
        let wants: [String?] = [nil, walking, "roulade.onnx"]
        for clockValue in clocks {
            for steer in steers {
                for want in wants {
                    for start in 0..<3 {
                        var pilot = PadPilot()
                        if start == 1 { pilot.startRecording(venue: .sim, at: clock) }
                        if start == 2 { pilot.play(take, thenLoading: .walk) }
                        let go = pilot.step(steering: steer, simSeconds: clockValue,
                                            policySaid: walking, wanting: want, now: clock)
                        // One twist, always finite, and never two.
                        XCTAssertTrue(go.command.vx.isFinite)
                        XCTAssertTrue(go.command.vy.isFinite)
                        XCTAssertTrue(go.command.vyaw.isFinite)
                        // A load is a name or nothing; never an empty string,
                        // which `swap(to:)` would post as a policy called "".
                        if let load = go.load { XCTAssertFalse(load.isEmpty) }
                    }
                }
            }
        }
    }

    /// A take is never thrown away by the next thing pressed: playing a bound
    /// sequence mid-take ends the take the way the chip does, kept and offered.
    func testPlayingDuringATakeKeepsAndOffersTheTake() throws {
        var pilot = PadPilot()
        pilot.startRecording(venue: .sim, at: clock)
        _ = pilot.step(steering: forward, simSeconds: 1, policySaid: walking,
                       wanting: nil, now: clock)
        pilot.play(try twoSteps(), thenLoading: nil)
        XCTAssertNotNil(pilot.pending, "the take is offered, never dropped")
        XCTAssertEqual(pilot.pendingEnding, .tapped)
        XCTAssertTrue(pilot.isPlaying)
        XCTAssertFalse(pilot.isRecording)
    }

    /// THE STICKS DO NOT AIM AT A NETWORK THAT IS NOT ON THE SERVOS. Asking
    /// once per engagement is right until the ask does not take — a bench
    /// restarted, a swap from another screen, a post cut off by a Stop — and
    /// then a thumb on the stick moved nothing. The bench's own word for what
    /// is driving is what corrects it.
    func testTheWantedNetworkIsAskedForAgainWhenTheBenchIsDrivingAnother() {
        var pilot = PadPilot()
        let first = pilot.step(steering: forward, simSeconds: 0, policySaid: nil,
                               wanting: walking, now: clock)
        XCTAssertEqual(first.load, walking, "asked once, before the bench has said anything")
        let quiet = pilot.step(steering: forward, simSeconds: 0.1, policySaid: walking,
                               wanting: walking, now: clock)
        XCTAssertNil(quiet.load, "the bench is driving it: nothing to ask for")
        let corrected = pilot.step(steering: forward, simSeconds: 0.2,
                                   policySaid: "BEST_alpha_stand.onnx",
                                   wanting: walking, now: clock)
        XCTAssertEqual(corrected.load, walking,
                       "the bench says something else is driving, so it is asked for again")
    }

    /// And a bench that has answered nothing keeps the once-only rule, so a
    /// network it refuses is not re-posted on every round trip.
    func testANetworkIsNotReAskedWhileTheBenchHasNotSaidWhatIsDriving() {
        var pilot = PadPilot()
        XCTAssertEqual(pilot.step(steering: forward, simSeconds: 0, policySaid: nil,
                                  wanting: walking, now: clock).load, walking)
        for tick in 1...5 {
            XCTAssertNil(pilot.step(steering: forward, simSeconds: Double(tick) / 10,
                                    policySaid: nil, wanting: walking, now: clock).load)
        }
    }
}
