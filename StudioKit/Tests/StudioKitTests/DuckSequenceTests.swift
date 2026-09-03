import XCTest
import DuckKit
import DuckEvidence
@testable import StudioKit

/// A sequence is a recording of what somebody DROVE, and every assertion here
/// is about keeping that claim narrow: the bench's clock and no other, the
/// bench's own network names and no guesses, three ceilings that close a take
/// rather than discarding it, and a vocabulary in which "policy" only ever
/// means a trained network.
final class DuckSequenceTests: XCTestCase {

    private let forward = DuckDrive.Twist(vx: 0.3, vy: 0, vyaw: 0)
    private let turning = DuckDrive.Twist(vx: 0, vy: 0, vyaw: 1.5)
    private let walking = "alpha_walking.onnx"

    private func recording(startedAt: Date = Date(timeIntervalSince1970: 0))
        -> DuckSequenceRecording {
        DuckSequenceRecording(startedAt: startedAt, venue: .sim)
    }

    // MARK: - capture

    func testAStepIsWrittenOnlyWhenTheCommandChanges() {
        var take = recording()
        var ignored = 0
        for trip in 0..<50 {
            let sampled = take.sample(forward, atSim: Double(trip) / 10,
                                      policySaid: walking)
            if case .ignored = sampled { ignored += 1 }
        }
        XCTAssertEqual(take.steps.count, 1)
        XCTAssertEqual(ignored, 49)
    }

    func testANewNetworkNamedByTheBenchOpensANewStep() {
        var take = recording()
        take.sample(forward, atSim: 0, policySaid: walking)
        take.sample(forward, atSim: 0.1, policySaid: "roulade.onnx")
        XCTAssertEqual(take.steps.count, 2)
        XCTAssertEqual(take.steps[1].policySaid, "roulade.onnx")
    }

    func testASampleWithNoSimClockIsSkippedAndCountedRatherThanStamped() {
        var take = recording()
        guard case .skipped(let total) = take.sample(forward, atSim: nil,
                                                    policySaid: walking) else {
            return XCTFail("a clockless trip is counted, not stamped")
        }
        XCTAssertEqual(total, 1)
        XCTAssertTrue(take.steps.isEmpty)
        // The take goes on.
        take.sample(forward, atSim: 5, policySaid: walking)
        XCTAssertEqual(take.steps.count, 1)
        let note = DuckSequence.droppedNote(1)
        XCTAssertNotNil(note)
        XCTAssertTrue(note!.contains("no clock"), note!)
    }

    func testATakeWhereNothingEverGotAClockRefusesByName() {
        var take = recording()
        for _ in 0..<5 { take.sample(forward, atSim: nil, policySaid: walking) }
        XCTAssertEqual(take.refusalIfOfferedNow, .noSimClock)
        XCTAssertThrowsError(try take.finish(named: "x", endedBy: .tapped, at: Date())) {
            XCTAssertEqual($0 as? DuckSequence.Refusal, .noSimClock)
        }
    }

    func testTheClockIsTheBenchsAndTheFirstStampedStepIsZero() {
        var take = recording()
        take.sample(forward, atSim: 10.0, policySaid: walking)
        take.sample(turning, atSim: 12.4, policySaid: walking)
        XCTAssertEqual(take.steps[0].atSim, 0, accuracy: 1e-9)
        XCTAssertEqual(take.steps[1].atSim, 2.4, accuracy: 1e-9)
    }

    func testACommandHeldPastTheMoveCeilingClosesTheTakeAndKeepsIt() throws {
        var take = recording()
        take.sample(forward, atSim: 0, policySaid: walking)
        guard case .closed(let refusal) = take.sample(forward, atSim: 31,
                                                     policySaid: walking) else {
            return XCTFail("holding one command for 31 s must close the take")
        }
        XCTAssertEqual(refusal, .heldTooLong(DuckSequence.maximumMoveSeconds))
        XCTAssertEqual(take.steps.count, 1, "and keeps what was driven")
        let kept = try take.finish(named: "held", endedBy: .ceiling(refusal.message), at: Date())
        // TWO STEPS: the command, and the end of its hold at 31 s — the length
        // that was actually driven, not a hold with no length.
        XCTAssertEqual(kept.steps.count, 2)
        XCTAssertEqual(kept.steps.last?.atSim ?? 0, 31, accuracy: 1e-9)
    }

    /// A TAKE THAT ENDS ON A MOVING COMMAND KEEPS THE WHOLE HOLD. Centred for
    /// half a second, then forward held for ten: the take is 10.5 s of sim,
    /// the saved schedule's last entry is at 10.5, and a replay returns
    /// forward across the whole hold before it finishes. Before the closing
    /// step existed this take was 0.5 s long and forward lasted one trip.
    func testTheFinalHeldCommandIsKeptToItsEnd() throws {
        var take = recording()
        take.sample(.still, atSim: 0.0, policySaid: walking)
        take.sample(.still, atSim: 0.5, policySaid: walking)
        var t = 0.5
        while t <= 10.5 + 1e-9 {
            take.sample(forward, atSim: t, policySaid: walking)
            t += 0.1
        }
        XCTAssertEqual(take.simSeconds, 10.5, accuracy: 1e-6)
        let kept = try take.finish(named: "held", endedBy: .tapped, at: Date())
        XCTAssertEqual(kept.steps.count, 3)
        XCTAssertEqual(kept.steps.last?.atSim ?? 0, 10.5, accuracy: 1e-6)
        XCTAssertEqual(kept.steps.last?.twist, forward)
        var run = DuckSequenceRun(kept)
        var forwardTrips = 0
        var clock = 0.0
        while clock <= 11 {
            if case .command(let twist) = run.advance(toSimClock: clock), twist == forward {
                forwardTrips += 1
            }
            clock += 0.1
        }
        XCTAssertGreaterThan(forwardTrips, 50, "forward is returned across the hold, not once")
    }

    func testTheStepCeilingClosesTheTakeDuringCaptureNotAtTheEnd() throws {
        var take = recording()
        var closed: DuckSequence.Refusal?
        for trip in 0..<800 {
            // Alternating twists, so every trip is a change and every change
            // is a step.
            let sampled = take.sample(trip % 2 == 0 ? forward : turning,
                                      atSim: Double(trip) / 100, policySaid: walking)
            if case .closed(let refusal) = sampled { closed = refusal; break }
        }
        XCTAssertEqual(closed, .tooManySteps(DuckSequence.maximumSteps))
        XCTAssertEqual(take.steps.count, DuckSequence.maximumSteps)
        XCTAssertNoThrow(try take.finish(named: "long", endedBy: .tapped, at: Date()))
    }

    func testTheDurationCeilingClosesTheTakeDuringCapture() {
        var take = recording()
        take.sample(forward, atSim: 0, policySaid: walking)
        // Under the move ceiling every time, so only the whole-take one can
        // fire.
        var at = 0.0
        var closed: DuckSequence.Refusal?
        for trip in 0..<20 {
            at += 20
            let sampled = take.sample(trip % 2 == 0 ? turning : forward,
                                      atSim: at, policySaid: walking)
            if case .closed(let refusal) = sampled { closed = refusal; break }
        }
        XCTAssertEqual(closed, .tooLong(DuckSequence.maximumSeconds))
    }

    // MARK: - what a take can become

    private func kept(_ names: [String?]) throws -> DuckSequence {
        var take = recording()
        for (trip, said) in names.enumerated() {
            take.sample(trip % 2 == 0 ? forward : turning,
                        atSim: Double(trip) / 10, policySaid: said,
                        now: Date(timeIntervalSince1970: Double(trip)))
        }
        return try take.finish(named: "a take", endedBy: .tapped,
                               at: Date(timeIntervalSince1970: 100))
    }

    func testARecordingThatNeverChangedNetworkCanBeKeptAsAClip() throws {
        let sequence = try kept([walking, walking, walking])
        XCTAssertEqual(sequence.benchPolicy, walking)
        XCTAssertTrue(sequence.canBeRecordedOnTheBench)
        XCTAssertNil(sequence.benchRefusal)
        XCTAssertNil(sequence.cannotBeKept)
    }

    func testARecordingThatSwappedNetworkCannotBePostedAndSaysWhy() throws {
        let sequence = try kept([walking, "roulade.onnx", walking])
        XCTAssertNil(sequence.benchPolicy)
        XCTAssertFalse(sequence.canBeRecordedOnTheBench)
        XCTAssertTrue(try XCTUnwrap(sequence.benchRefusal)
            .contains("one bench recording names one policy"))
        XCTAssertEqual(sequence.cannotBeKept, sequence.benchRefusal)
    }

    func testATakeTheBenchNeverNamedAnythingForHasItsOwnSentence() throws {
        let sequence = try kept([nil, nil, nil])
        XCTAssertNil(sequence.benchRefusal, "it did not change network; it was never told one")
        XCTAssertEqual(sequence.cannotBeKept, DuckSequence.benchNeverNamedANetwork)
    }

    func testTheBenchScheduleIsTheStepsInTheBenchsOwnShape() throws {
        let sequence = try kept([walking, walking, walking])
        let schedule = sequence.benchSchedule()
        XCTAssertEqual(schedule.map(\.at), sequence.steps.map(\.atSim))
        for (step, wire) in zip(sequence.steps, schedule) {
            XCTAssertEqual(wire.vx, step.twist.vx)
            XCTAssertEqual(wire.vy, step.twist.vy)
            XCTAssertEqual(wire.vyaw, step.twist.vyaw)
        }
    }

    func testBothClocksNamesBothNumbersAndTheReason() {
        let line = DuckSequence.bothClocks(simSeconds: 3.4, wallSeconds: 19.2)
        XCTAssertTrue(line.contains("3.4 s of sim"), line)
        XCTAssertTrue(line.contains("19.2 s of your time"), line)
        XCTAssertTrue(line.contains("answering a request"), line)
    }

    func testWallSecondsIsStoredAndPrintedAndNeverUsedAsATimeBase() throws {
        let steps = [DuckSequence.Step(atSim: 0, twist: forward, policySaid: walking),
                     DuckSequence.Step(atSim: 1, twist: turning, policySaid: walking)]
        let quick = try DuckSequence.make(steps: steps, named: "a", provenance: .said("a"),
                                          wallSeconds: 1, venue: .sim, at: Date())
        let slow = try DuckSequence.make(steps: steps, named: "a", provenance: .said("a"),
                                         wallSeconds: 90, venue: .sim, at: Date())
        XCTAssertEqual(quick.simSeconds, slow.simSeconds)
        XCTAssertEqual(quick.benchSchedule().map(\.at), slow.benchSchedule().map(\.at))
        XCTAssertNotEqual(quick.wallSeconds, slow.wallSeconds, "and it is still stored")
    }

    // MARK: - the playhead

    private func threeSteps() throws -> DuckSequence {
        try DuckSequence.make(
            steps: [DuckSequence.Step(atSim: 0, twist: forward, policySaid: walking),
                    DuckSequence.Step(atSim: 1, twist: turning, policySaid: walking),
                    DuckSequence.Step(atSim: 2, twist: .still, policySaid: walking)],
            named: "three", provenance: .said("x"), wallSeconds: 0, venue: .sim, at: Date())
    }

    func testTheRunHandsBackTheCommandThatWasDrivenAtThatSimSecond() throws {
        var run = DuckSequenceRun(try threeSteps())
        XCTAssertEqual(run.advance(toSimClock: 0), .command(forward))
        XCTAssertEqual(run.advance(toSimClock: 0.5), .command(forward))
        XCTAssertEqual(run.advance(toSimClock: 1), .command(turning))
        XCTAssertEqual(run.advance(toSimClock: 1.9), .command(turning))
        XCTAssertEqual(run.advance(toSimClock: 2), .command(.still))
        XCTAssertEqual(run.advance(toSimClock: 2.1), .finished)
    }

    func testTheRunTakesItsOriginFromTheFirstClockItIsGiven() throws {
        let sequence = try threeSteps()
        var atZero = DuckSequenceRun(sequence)
        var atNineHundred = DuckSequenceRun(sequence)
        var one: [DuckSequenceRun.Beat] = []
        var two: [DuckSequenceRun.Beat] = []
        for tick in stride(from: 0.0, through: 2.5, by: 0.25) {
            one.append(atZero.advance(toSimClock: tick))
            two.append(atNineHundred.advance(toSimClock: 900 + tick))
        }
        XCTAssertEqual(one, two)
    }

    func testTheRunFinishesRatherThanRepeatingTheLastCommand() throws {
        var run = DuckSequenceRun(try threeSteps())
        _ = run.advance(toSimClock: 0)
        XCTAssertEqual(run.advance(toSimClock: 9), .finished)
        XCTAssertEqual(run.advance(toSimClock: 10), .finished)
    }

    func testASwapInTheRecordingComesBackAsABeat() throws {
        let sequence = try DuckSequence.make(
            steps: [DuckSequence.Step(atSim: 0, twist: forward, policySaid: walking),
                    DuckSequence.Step(atSim: 1, twist: turning, policySaid: "alpha_roulade.onnx")],
            named: "swapped", provenance: .said("x"), wallSeconds: 0, venue: .sim, at: Date())
        var run = DuckSequenceRun(sequence)
        XCTAssertEqual(run.advance(toSimClock: 0), .command(forward))
        XCTAssertEqual(run.advance(toSimClock: 1),
                       .swap(to: "alpha_roulade.onnx", then: turning))
        XCTAssertEqual(run.advance(toSimClock: 1), .command(turning),
                       "and it is announced once, not on every trip")
    }

    // MARK: - what is said about it

    func testTheSummaryStatesOnlyWhatWasMeasured() throws {
        let summary = try kept([walking, walking, walking]).summary
        XCTAssertTrue(summary.contains("s of physics"), summary)
        XCTAssertTrue(summary.contains("steps"), summary)
        for wallWord in ["your time", "wall", "real time", "seconds you"] {
            XCTAssertFalse(summary.contains(wallWord), summary)
        }
    }

    func testProvenanceSaysWhoWroteItAndHowItEnded() {
        for ending: DuckSequence.Ending in [.tapped, .paused, .stop, .ceiling("a ceiling")] {
            let sentence = DuckSequence.Provenance
                .recorded(trips: 4, skipped: 1, endedBy: ending).sentence
            XCTAssertTrue(sentence.contains("round trips"), sentence)
            XCTAssertTrue(sentence.contains(PadPilot.endedBy(ending)), sentence)
        }
        // "0 came back with no clock" is a true sentence and a bad one.
        let clean = DuckSequence.Provenance
            .recorded(trips: 4, skipped: 0, endedBy: .tapped).sentence
        XCTAssertFalse(clean.contains("0 "), clean)
        XCTAssertTrue(clean.contains("every one of them stamped"), clean)
        XCTAssertTrue(DuckSequence.Provenance
            .recorded(trips: 1, skipped: 0, endedBy: .stop).sentence
            .contains("Stop ended the take"))
        XCTAssertTrue(DuckSequence.Provenance.said("go forward").sentence
            .contains("go forward"))
        XCTAssertTrue(DuckSequence.Provenance.drafted(model: "gemma", asked: "go")
            .sentence.contains("gemma"))
    }

    func testAReplayNeverClaimsToBeTheRecording() {
        XCTAssertTrue(DuckSequence.replayIsARerun.contains("re-run"))
        XCTAssertTrue(DuckSequence.replayIsARerun.contains("simulated time"))
    }

    func testTheSuggestedNameCarriesTheNetworkAndTheLength() {
        let first = DuckSequence.suggestedName(policy: walking, simSeconds: 3.4, steps: 9,
                                               at: Date(timeIntervalSince1970: 1000))
        let second = DuckSequence.suggestedName(policy: walking, simSeconds: 3.4, steps: 9,
                                                at: Date(timeIntervalSince1970: 1001))
        XCTAssertTrue(first.contains(walking))
        XCTAssertTrue(first.contains("9 steps"))
        XCTAssertNotEqual(first, second, "two takes a second apart mint two names")
    }

    // MARK: - the file

    func testASequenceSurvivesARoundTrip() throws {
        let sequence = try kept([walking, "roulade.onnx", walking])
        let back = try DuckSequence.decode(try sequence.encoded())
        XCTAssertEqual(back.id, sequence.id)
        XCTAssertEqual(back.name, sequence.name)
        XCTAssertEqual(back.steps, sequence.steps)
        XCTAssertEqual(back.provenance, sequence.provenance)
        XCTAssertEqual(back.wallSeconds, sequence.wallSeconds, accuracy: 1e-6)
        XCTAssertEqual(back.venue, sequence.venue)
        XCTAssertEqual(back.steps.map(\.policySaid), sequence.steps.map(\.policySaid))
    }

    func testASequenceSavedWithoutAFieldStillOpens() throws {
        let json = """
        {"format":"duck-sequence/1","name":"old","steps":[{"atSim":0,"vx":0.3}]}
        """
        let sequence = try DuckSequence.decode(XCTUnwrap(json.data(using: .utf8)))
        XCTAssertEqual(sequence.wallSeconds, 0)
        XCTAssertEqual(sequence.steps.count, 1)
        XCTAssertEqual(sequence.venue, .sim)
    }

    func testAnUnknownFormatIsRefusedByName() {
        let message = DuckSequence.ReadError.wrongFormat("duck-sequence/9").message
        XCTAssertTrue(message.contains("duck-sequence/9"))
        XCTAssertTrue(message.contains(DuckSequence.format), message)
    }

    // MARK: - the three words

    /// THE CHECK THAT PROVES IT CAN FAIL. A guard that cannot fail ships green
    /// forever; this one is run against a deliberately bad sentence first, and
    /// the test fails if that sentence gets through.
    func testTheWordPolicyIsOnlyEverUsedAboutATrainedNetwork() throws {
        // Genuinely about a trained network, and the only places the word is
        // allowed to appear.
        let allowed = [
            "A policy is a trained network",
            "recording names one policy",
            "the standing policy takes over",
            "is the policy's business",
        ]
        let pattern = try NSRegularExpression(pattern: "(^|[^A-Za-z])polic(y|ies)")
        func offends(_ sentence: String) -> Bool {
            let range = NSRange(sentence.startIndex..., in: sentence)
            guard pattern.firstMatch(in: sentence, range: range) != nil else { return false }
            return !allowed.contains { sentence.contains($0) }
        }
        XCTAssertTrue(offends("This policy plays back what you drove."),
                      "the check must be able to fail")
        XCTAssertFalse(offends("Nothing about networks here."))
        for sentence in DuckSequence.allSentences {
            XCTAssertFalse(offends(sentence),
                           "\"policy\" is a trained network and nothing else: \(sentence)")
        }
    }

    func testTheThreeWordsAreSeparatedWhereSomebodyWillReadIt() {
        XCTAssertTrue(DuckSequence.whatThisIs.contains("A policy is a trained network"))
        XCTAssertTrue(DuckSequence.whatThisIs.contains("a motion is a track somebody authored"))
        XCTAssertTrue(DuckSequence.whatThisIs.contains("a macro, not a skill"))
    }

    /// A button holds an ID and not a name, so a rename cannot orphan one —
    /// and somebody about to rename the take three buttons play is told that
    /// before they do it.
    func testRenamingIsSaidNotToBreakABinding() {
        XCTAssertTrue(DuckSequence.renamingKeepsTheBindings.contains("id rather than its name"),
                      DuckSequence.renamingKeepsTheBindings)
    }

    /// What lands in Behaviours is a recording of the run the BENCH just made,
    /// not of the drive somebody did — and the sentence says so where they will
    /// go looking for it.
    func testWhatIsFiledOnTheBenchIsNamedAsARerunAndNotTheDrive() {
        let said = DuckSequence.keptAsAMotion("Fast turn")
        XCTAssertTrue(said.contains("Fast turn"), said)
        XCTAssertTrue(said.contains("Behaviours"), said)
        XCTAssertTrue(said.contains("rather than of the drive you did here"), said)
    }

    func testSharingIsAnExplicitNotYetWithItsReason() {
        XCTAssertTrue(DuckSequence.sharingIsNotYet.contains("declared file type"))
        XCTAssertTrue(DuckSequence.sharingIsNotYet.contains("all three or none"))
    }
}
