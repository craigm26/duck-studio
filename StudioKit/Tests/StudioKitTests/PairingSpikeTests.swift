import XCTest
@testable import StudioKit

/// The spike's reading logic, which is the only part of it that can be wrong in
/// a way nobody notices.
///
/// WHAT THESE TESTS ARE GUARDING. The spike answers a question on Pollen's
/// critical path, and the shape of the answer is a HANG rather than an error. So
/// the specific defect to prevent is a report that says something encouraging
/// about a run that established nothing — a run stopped at connect, or a read
/// served with `--require-pairing` off, reading as "looks good". A maintainer
/// acting on such a report flips a flag on the strength of an experiment nobody
/// performed.
///
/// Every reading below is therefore asserted twice: that it says the right thing,
/// and that it does NOT say the encouraging thing.
final class PairingSpikeTests: XCTestCase {

    // MARK: - builders

    private func run(_ outcomes: [PairingSpike.Step: PairingSpike.Outcome],
                     prompt: Bool? = nil,
                     requirePairing: Bool = true,
                     apiVersion: UInt8? = 16) -> PairingSpike.Run {
        PairingSpike.Run(outcomes: outcomes,
                         pairingPromptShown: prompt,
                         requirePairing: requirePairing,
                         deviceModel: "iPhone 15 Pro",
                         iOSVersion: "18.2",
                         robotAPIVersion: apiVersion)
    }

    /// Everything up to and including the read worked.
    private var throughTheRead: [PairingSpike.Step: PairingSpike.Outcome] {
        [.scan: .ok(seconds: 2.1), .connect: .ok(seconds: 0.8),
         .discover: .ok(seconds: 0.2), .readVersion: .ok(seconds: 4.4)]
    }

    private var cleanPass: PairingSpike.Run {
        var outcomes = throughTheRead
        outcomes[.subscribe] = .ok(seconds: 0.1)
        outcomes[.hello] = .ok(seconds: 0.3)
        outcomes[.authenticate] = .ok(seconds: 0.4)
        outcomes[.systemInfo] = .ok(seconds: 0.3)
        return run(outcomes, prompt: true)
    }

    private var hungRead: PairingSpike.Run {
        run([.scan: .ok(seconds: 2.1), .connect: .ok(seconds: 0.8),
             .discover: .ok(seconds: 0.2), .readVersion: .timedOut(afterSeconds: 60)],
            prompt: false, apiVersion: nil)
    }

    private var refusedRead: PairingSpike.Run {
        run([.scan: .ok(seconds: 2.1), .connect: .ok(seconds: 0.8),
             .discover: .ok(seconds: 0.2),
             .readVersion: .refused(seconds: 1.2, "Encryption is insufficient.")],
            prompt: false, apiVersion: nil)
    }

    private var stoppedAtConnect: PairingSpike.Run {
        run([.scan: .ok(seconds: 2.1), .connect: .timedOut(afterSeconds: 15)],
            prompt: nil, apiVersion: nil)
    }

    /// The reading section of a report, so a test about what a conclusion says is
    /// not fooled by the framing paragraph at the top, which necessarily names
    /// both possible answers.
    private func readingSection(of report: String) -> String {
        guard let marker = report.range(of: "Reading\n-------\n") else {
            XCTFail("the report has no reading section at all")
            return ""
        }
        return String(report[marker.upperBound...])
    }

    // MARK: - the sequence

    /// The roadmap's order: "scan, connect, `hello`, authenticate, `system.info`
    /// with `--require-pairing` on", with the GATT steps their contract requires
    /// in between.
    func testTheStepsAreTheRoadmapsSequenceInOrder() {
        XCTAssertEqual(PairingSpike.Step.allCases,
                       [.scan, .connect, .discover, .readVersion,
                        .subscribe, .hello, .authenticate, .systemInfo])
        // The read is before every write. `gatt.rs` makes this the contract, not
        // a preference: a client that subscribes and writes first is refused with
        // no error anybody can see.
        XCTAssertLessThan(PairingSpike.Step.readVersion.rawValue,
                          PairingSpike.Step.subscribe.rawValue)
        XCTAssertLessThan(PairingSpike.Step.readVersion.rawValue,
                          PairingSpike.Step.hello.rawValue)
    }

    func testEveryStepSaysWhatItEstablishesAndWhatAFailureThereWouldMean() {
        var establishes: Set<String> = []
        var failures: Set<String> = []
        for step in PairingSpike.Step.allCases {
            XCTAssertFalse(step.title.isEmpty)
            XCTAssertTrue(step.establishes.hasSuffix("."), "\(step) — \(step.establishes)")
            XCTAssertTrue(step.failureMeans.hasSuffix("."), "\(step) — \(step.failureMeans)")
            establishes.insert(step.establishes)
            failures.insert(step.failureMeans)
        }
        // A shared sentence would mean two steps whose failures are being read as
        // the same finding, which is the mistake this whole file exists about.
        XCTAssertEqual(establishes.count, PairingSpike.Step.allCases.count)
        XCTAssertEqual(failures.count, PairingSpike.Step.allCases.count)
    }

    // MARK: - the budgets

    /// A short budget on the read would manufacture the very hang the spike is
    /// trying to observe, so the read gets the largest budget of the eight and
    /// has to justify it in words.
    func testTheReadGetsTheLargestBudgetAndSaysWhy() {
        let read = PairingSpike.Step.readVersion
        for step in PairingSpike.Step.allCases where step != read {
            XCTAssertLessThan(step.timeoutSeconds, read.timeoutSeconds, "\(step)")
        }
        XCTAssertGreaterThanOrEqual(read.timeoutSeconds, 60)
        XCTAssertTrue(read.timeoutRationale.contains("NEVER returns"))
        // The human in the loop is half the justification: somebody has to see
        // the prompt and tap it, possibly after unlocking the phone.
        XCTAssertTrue(read.timeoutRationale.contains("tap Pair"))
    }

    /// Pollen measured advertising silences of 9, 14, 17 and once 31 seconds on
    /// the old 1.28 s default. A 30-second scan budget would report "no duck" for
    /// a duck that was there.
    func testTheScanBudgetOutlastsTheLongestSilenceTheyMeasured() {
        XCTAssertGreaterThan(PairingSpike.Step.scan.timeoutSeconds, 31)
        XCTAssertTrue(PairingSpike.Step.scan.timeoutRationale.contains("31 s"))
    }

    // MARK: - the three endings

    /// A refusal can be shown to a person; a hang cannot. The two must never read
    /// the same, and neither is spelled "failed".
    func testARefusalAndASilenceNeverReadTheSame() {
        let refused = PairingSpike.Outcome.refused(seconds: 1.2, "Encryption is insufficient.")
        let hung = PairingSpike.Outcome.timedOut(afterSeconds: 60)
        XCTAssertEqual(refused.line, "REFUSED after 1.20 s — Encryption is insufficient.")
        XCTAssertEqual(hung.line, "TIMED OUT after 60.00 s — no answer and no error")
        XCTAssertNotEqual(refused.line, hung.line)
        XCTAssertEqual(PairingSpike.Outcome.ok(seconds: 4.4).line, "ok — 4.40 s")
        XCTAssertEqual(PairingSpike.Outcome.notReached.line, "not reached")
        XCTAssertTrue(PairingSpike.Outcome.ok(seconds: 1).isOK)
        XCTAssertFalse(hung.isOK)
        XCTAssertFalse(refused.isOK)
        XCTAssertFalse(PairingSpike.Outcome.notReached.isOK)
    }

    func testAStepNobodyRanIsNotReachedRatherThanMissing() {
        let stopped = stoppedAtConnect
        XCTAssertEqual(stopped.outcome(for: .systemInfo), .notReached)
        XCTAssertEqual(stopped.stoppedAt, .connect)
        XCTAssertNil(cleanPass.stoppedAt)
    }

    // MARK: - the readings, one at a time

    func testACleanPassSupportsFlippingTheFlag() {
        let reading = cleanPass.reading
        XCTAssertEqual(reading.verdict, .flagCanDefaultOn)
        XCTAssertTrue(reading.headline.contains("supports flipping"))
        XCTAssertTrue(reading.body.contains("An encrypted link was therefore established"))
        XCTAssertTrue(reading.body.contains("the flag can be flipped and defaulted on"))
        // A finished run has no unfinished-run caveat bolted onto it.
        XCTAssertFalse(reading.body.contains("The run did not finish"))
    }

    /// The most valuable outcome available, and the one a tester is most likely
    /// to mistake for their own mistake.
    func testAHungReadReadsAsTheMacOSSymptomReproduced() {
        let reading = hungRead.reading
        XCTAssertEqual(reading.verdict, .readHung)
        XCTAssertTrue(reading.headline.contains("must not be defaulted on"))
        XCTAssertTrue(reading.body.contains("nothing came back at all"))
        // It has to hand the reader §5.5's own next move rather than stopping at
        // "it hung".
        XCTAssertTrue(reading.body.contains("bluetoothctl info <mac>"))
        XCTAssertTrue(reading.body.contains("Paired: no"))
        XCTAssertFalse(reading.body.contains("supports"))
    }

    /// An error is a different finding from a silence, and a more tractable one.
    func testARefusedReadIsMateriallyDifferentFromAHungOne() {
        let refused = refusedRead.reading
        XCTAssertEqual(refused.verdict, .readRefused)
        XCTAssertTrue(refused.headline.contains("instead of hanging"))
        // The refusal's own words survive into the reading; without them there is
        // nothing to chase.
        XCTAssertTrue(refused.body.contains("Encryption is insufficient."))
        XCTAssertTrue(refused.body.contains("cannot be put in front of anybody"))
        XCTAssertNotEqual(refused.headline, hungRead.reading.headline)
        XCTAssertNotEqual(refused.body, hungRead.reading.body)
    }

    /// THE FAILURE MODE THIS FILE EXISTS TO PREVENT, case one.
    func testARunThatNeverReachedTheReadEstablishesNothingAndSaysSo() {
        let reading = stoppedAtConnect.reading
        XCTAssertEqual(reading.verdict, .establishesNothing)
        XCTAssertTrue(reading.headline.contains("establishes nothing about §5.5"))
        XCTAssertTrue(reading.body.contains("that operation was never issued here"))
        // It names the step that stopped it, so the reader knows what to fix.
        XCTAssertTrue(reading.body.contains("Connect"))
        XCTAssertTrue(reading.body.contains("TIMED OUT after 15.00 s"))
        // And it is symmetrically unhelpful, on purpose: it supports nothing and
        // contradicts nothing.
        XCTAssertTrue(reading.body.contains("Nothing in this run supports flipping "
                                            + "--require-pairing on, and nothing in it contradicts "
                                            + "doing so either."))
        let section = readingSection(of: stoppedAtConnect.report())
        XCTAssertFalse(section.contains("can be flipped and defaulted on"))
        XCTAssertFalse(section.contains("This supports flipping"))
    }

    /// THE FAILURE MODE THIS FILE EXISTS TO PREVENT, case two — and the easier
    /// one to ship, because every step in the run says "ok".
    func testACleanReadWithTheFlagOffEstablishesNothing() {
        var outcomes = throughTheRead
        outcomes[.subscribe] = .ok(seconds: 0.1)
        outcomes[.hello] = .ok(seconds: 0.3)
        outcomes[.authenticate] = .ok(seconds: 0.4)
        outcomes[.systemInfo] = .ok(seconds: 0.3)
        let flagOff = run(outcomes, prompt: false, requirePairing: false)

        let reading = flagOff.reading
        XCTAssertEqual(reading.verdict, .readWasNotEncrypted)
        XCTAssertTrue(reading.headline.contains("establishes nothing about §5.5"))
        XCTAssertTrue(reading.body.contains("proves only that the pipe works"))
        XCTAssertTrue(reading.body.contains("Re-run it with btd started --require-pairing on"))
        // An eight-for-eight run must still not read as an answer.
        XCTAssertNil(flagOff.stoppedAt)
        XCTAssertFalse(reading.body.contains("the flag can be flipped and defaulted on"))
        XCTAssertFalse(readingSection(of: flagOff.report()).contains("This supports flipping"))
        // And it repeats what the off state costs, since that is why anybody
        // cares about the flag.
        XCTAssertTrue(reading.body.contains("readable by a bystander"))
    }

    /// The four scenarios the spike can produce must not be paraphrases of each
    /// other. If two of them read alike, the report has stopped distinguishing
    /// the answers it exists to distinguish.
    func testTheFourScenariosProduceFourMateriallyDifferentReadings() {
        let readings = [cleanPass, hungRead, refusedRead, stoppedAtConnect].map { $0.reading }
        XCTAssertEqual(Set(readings.map { $0.verdict.rawValue }).count, 4)
        XCTAssertEqual(Set(readings.map { $0.headline }).count, 4)
        XCTAssertEqual(Set(readings.map { $0.body }).count, 4)
    }

    // MARK: - the prompt observation

    /// `nil` is a third answer. A tester who was not watching the screen must not
    /// be reported as having watched it and seen nothing.
    func testAnUnobservedPromptIsNotTheSameAsNoPrompt() {
        var outcomes = throughTheRead
        outcomes[.subscribe] = .ok(seconds: 0.1)
        outcomes[.hello] = .ok(seconds: 0.3)
        outcomes[.authenticate] = .ok(seconds: 0.4)
        outcomes[.systemInfo] = .ok(seconds: 0.3)

        let seen = run(outcomes, prompt: true).reading.body
        let notSeen = run(outcomes, prompt: false).reading.body
        let notWatched = run(outcomes, prompt: nil).reading.body
        XCTAssertEqual(Set([seen, notSeen, notWatched]).count, 3)

        XCTAssertTrue(seen.contains("first-run path a new owner takes"))
        // No prompt on a successful read is most likely an existing bond, and
        // that is not evidence about a first-time owner.
        XCTAssertTrue(notSeen.contains("already bonded to this robot from an earlier run"))
        XCTAssertTrue(notWatched.contains("was not observed"))

        XCTAssertTrue(run(outcomes, prompt: nil).report()
            .contains("iOS pairing prompt: NOT OBSERVED"))
    }

    /// On a hang, the prompt is the most informative single fact available: a
    /// prompt means the phone tried to bond, no prompt means it never did.
    func testThePromptChangesWhatAHangMeans() {
        let outcomes: [PairingSpike.Step: PairingSpike.Outcome] =
            [.scan: .ok(seconds: 2.1), .connect: .ok(seconds: 0.8),
             .discover: .ok(seconds: 0.2), .readVersion: .timedOut(afterSeconds: 60)]
        let prompted = run(outcomes, prompt: true, apiVersion: nil).reading
        let unprompted = run(outcomes, prompt: false, apiVersion: nil).reading
        let unwatched = run(outcomes, prompt: nil, apiVersion: nil).reading

        XCTAssertEqual(Set([prompted, unprompted, unwatched].map { $0.body }).count, 3)
        XCTAssertTrue(prompted.body.contains("whatever refused it is on the robot's side"))
        XCTAssertTrue(unprompted.body.contains("nothing on this phone ever attempted to bond"))
        XCTAssertTrue(unwatched.body.contains("the single most useful thing to record"))
        // All three are still the same verdict — the flag stays off.
        for reading in [prompted, unprompted, unwatched] {
            XCTAssertEqual(reading.verdict, .readHung)
        }
    }

    // MARK: - a run that answers §5.5 and then breaks

    /// The read is what §5.5 asks about, so a later failure does not retract the
    /// read result — but it must not be swallowed either.
    func testAFailureAfterTheReadIsReportedWithoutRetractingTheReadResult() {
        var outcomes = throughTheRead
        outcomes[.subscribe] = .ok(seconds: 0.1)
        outcomes[.hello] = .timedOut(afterSeconds: 15)
        let broken = run(outcomes, prompt: true)

        let reading = broken.reading
        XCTAssertEqual(reading.verdict, .flagCanDefaultOn)
        XCTAssertTrue(reading.body.contains("An encrypted link was therefore established"))
        XCTAssertTrue(reading.body.contains("The run did not finish, though: hello"))
        XCTAssertTrue(reading.body.contains("does not weaken the read result above"))
        XCTAssertTrue(reading.body.contains("working end-to-end phone flow"))
        // The caveat names the first failure after the read, not the last step.
        XCTAssertFalse(reading.body.contains("system.info —"))
    }

    // MARK: - the deliverable

    func testTheReportCarriesWhatAMaintainerNeedsToJudgeAHang() {
        let text = hungRead.report()
        // Hardware and OS, because a hang on one radio generation is not a hang
        // on all of them.
        XCTAssertTrue(text.contains("Phone: iPhone 15 Pro, iOS 18.2"))
        // The flag, because a run with it off is a different experiment.
        XCTAssertTrue(text.contains("btd started with --require-pairing ON"))
        XCTAssertTrue(text.contains("iOS pairing prompt: not shown"))
        // No version was read, and the report says that rather than printing a
        // zero.
        XCTAssertTrue(text.contains("Robot API version: unknown — the read never returned one"))
        // The UUIDs, so a reader can tell which service was actually poked.
        XCTAssertTrue(text.contains(DuckLink.serviceUUID))
        XCTAssertTrue(text.contains(DuckLink.rpcUUID))
        // Every step is listed, with its budget, whether or not it ran.
        for step in PairingSpike.Step.allCases {
            XCTAssertTrue(text.contains(step.title), "missing \(step.title)")
        }
        XCTAssertTrue(text.contains("4. Read the API version [budget 60.00 s]: "
                                    + "TIMED OUT after 60.00 s — no answer and no error"))
        XCTAssertTrue(text.contains("5. Subscribe for answers [budget 10.00 s]: not reached"))
        // And the budget's justification travels with the failure, so the hang
        // can be believed.
        XCTAssertTrue(text.contains("On a Mac this read NEVER returns"))
        XCTAssertTrue(text.contains(hungRead.reading.headline))
        XCTAssertTrue(text.contains(hungRead.reading.body))
    }

    /// A step nobody attempted gets no paragraph explaining what its failure
    /// would have meant, because it did not fail.
    func testTheReportDoesNotExplainStepsThatNeverRan() {
        let text = stoppedAtConnect.report()
        XCTAssertTrue(text.contains(PairingSpike.Step.connect.failureMeans))
        XCTAssertFalse(text.contains(PairingSpike.Step.discover.failureMeans))
        XCTAssertFalse(text.contains(PairingSpike.Step.systemInfo.failureMeans))
    }

    /// The sentence a tester reads before pressing go. It has to say whose
    /// blocker this is and that a hang is a result, or the most valuable outcome
    /// gets quietly retried instead of reported.
    func testWhatThisIsForNamesTheBlockerAndThatEitherAnswerIsUseful() {
        let text = PairingSpike.whatThisIsFor
        XCTAssertTrue(text.contains("Pollen Robotics"))
        XCTAssertTrue(text.contains("--require-pairing"))
        XCTAssertTrue(text.contains("Both answers are worth having."))
        XCTAssertTrue(text.contains("A step that times out is a result, not a mistake"))
        XCTAssertTrue(text.contains("This is not a feature."))
    }

    /// Transcribed facts, pinned the same way `DuckLinkTests` pins the UUIDs: the
    /// factory PIN is public in Pollen's repository, and `system.authenticate`
    /// arrived in API version 4.
    func testTheAuthenticationFactsAreTheOnesInTheirRepository() {
        XCTAssertEqual(PairingSpike.factoryPIN, "000000")
        XCTAssertEqual(PairingSpike.authenticateAddedInAPIVersion, 4)
        XCTAssertTrue(PairingSpike.Step.authenticate.failureMeans.contains("API version 4"))
    }
}

extension PairingSpikeTests {

    /// THE EXPERIMENTAL CONDITION IS CHECKED IN EVERY BRANCH, NOT ONE.
    ///
    /// The reading consulted `requirePairing` only for a read that SUCCEEDED,
    /// so a hung or refused read asserted "issued against a robot started with
    /// --require-pairing on" regardless of what the tester set — and the screen
    /// defaults that toggle off, which made the false report the default one,
    /// in exactly the two outcomes Pollen most need. A report that misstates
    /// its own experimental condition is worse than no report.
    func testAHungReadWithTheFlagOffDoesNotClaimToReproduceTheHang() {
        let run = PairingSpike.Run(
            outcomes: [.scan: .ok(seconds: 2), .connect: .ok(seconds: 1),
                       .discover: .ok(seconds: 1), .readVersion: .timedOut(afterSeconds: 60)],
            pairingPromptShown: nil, requirePairing: false,
            deviceModel: "iPhone 17 Pro", iOSVersion: "26.5", robotAPIVersion: nil)
        XCTAssertEqual(run.reading.verdict, .establishesNothing)
        let said = run.reading.headline + run.reading.body
        XCTAssertFalse(said.contains("started with --require-pairing on"), said)
        XCTAssertFalse(said.contains("symptom reproduced"), said)
        XCTAssertTrue(said.contains("establishes nothing"), said)
    }

    func testARefusedReadWithTheFlagOffDoesNotBlameEncryption() {
        let run = PairingSpike.Run(
            outcomes: [.readVersion: .refused(seconds: 1.2, "Encryption is insufficient.")],
            pairingPromptShown: nil, requirePairing: false,
            deviceModel: "iPhone 17 Pro", iOSVersion: "26.5", robotAPIVersion: nil)
        XCTAssertEqual(run.reading.verdict, .establishesNothing)
        XCTAssertFalse(run.reading.body.contains("started with --require-pairing on"))
    }

    /// And with the flag ON the strong readings still stand — the guard must
    /// narrow the claim, not delete it.
    func testTheFlagOnStillReachesTheDecisiveReadings() {
        let hung = PairingSpike.Run(
            outcomes: [.readVersion: .timedOut(afterSeconds: 60)],
            pairingPromptShown: true, requirePairing: true,
            deviceModel: "iPhone 17 Pro", iOSVersion: "26.5", robotAPIVersion: nil)
        XCTAssertEqual(hung.reading.verdict, .readHung)

        let ok = PairingSpike.Run(
            outcomes: Dictionary(uniqueKeysWithValues:
                PairingSpike.Step.allCases.map { ($0, PairingSpike.Outcome.ok(seconds: 1)) }),
            pairingPromptShown: true, requirePairing: true,
            deviceModel: "iPhone 17 Pro", iOSVersion: "26.5", robotAPIVersion: 16)
        XCTAssertEqual(ok.reading.verdict, .flagCanDefaultOn)
    }
}
