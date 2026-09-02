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

    /// A FIXED MOMENT, WHICH IS THE WHOLE REASON THE KIT TAKES A DATE RATHER
    /// THAN READING ONE. `report()` prints when the run happened; if it asked
    /// the system that question itself, the line could only ever be asserted
    /// against another call to the same clock, and it would silently become the
    /// time somebody re-rendered the report rather than the time of the run.
    private static let aMoment = Date(timeIntervalSince1970: 1_788_264_000)

    private func run(_ outcomes: [PairingSpike.Step: PairingSpike.Outcome],
                     prompt: Bool? = nil,
                     requirePairing: Bool = true,
                     apiVersion: UInt8? = 16,
                     pin: String = PairingSpike.factoryPIN,
                     runNumber: Int? = nil,
                     sightings: [DuckLink.Sighting] = [],
                     tested: DuckLink.Sighting? = nil,
                     hello: DuckLink.Hello? = nil,
                     info: DuckLink.SystemInfo? = nil,
                     lateAnswers: [PairingSpike.Step: String] = [:],
                     notifications: [String] = [],
                     authenticateWritten: Bool = true) -> PairingSpike.Run {
        PairingSpike.Run(outcomes: outcomes,
                         pairingPromptShown: prompt,
                         requirePairing: requirePairing,
                         deviceModel: "iPhone 15 Pro",
                         iOSVersion: "18.2",
                         robotAPIVersion: apiVersion,
                         pin: pin,
                         startedAt: Self.aMoment,
                         runNumber: runNumber,
                         sightings: sightings,
                         tested: tested,
                         hello: hello,
                         info: info,
                         lateAnswers: lateAnswers,
                         notifications: notifications,
                         authenticateWritten: authenticateWritten)
    }

    /// The duck a report is about.
    private var theDuck: DuckLink.Sighting {
        DuckLink.Sighting(name: "microduck-a3f1", rssi: -58,
                          address: .at("192.168.1.24"), tier: .advertisedService)
    }

    /// Something else that was in the room.
    private var theOtherThing: DuckLink.Sighting {
        DuckLink.Sighting(name: "rubber-duckling", rssi: -91,
                          address: .notBroadcast, tier: .nameOnly)
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
            deviceModel: "iPhone 17 Pro", iOSVersion: "26.5", robotAPIVersion: nil,
            pin: PairingSpike.factoryPIN, startedAt: Self.aMoment)
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
            deviceModel: "iPhone 17 Pro", iOSVersion: "26.5", robotAPIVersion: nil,
            pin: PairingSpike.factoryPIN, startedAt: Self.aMoment)
        XCTAssertEqual(run.reading.verdict, .establishesNothing)
        XCTAssertFalse(run.reading.body.contains("started with --require-pairing on"))
    }

    /// And with the flag ON the strong readings still stand — the guard must
    /// narrow the claim, not delete it.
    func testTheFlagOnStillReachesTheDecisiveReadings() {
        let hung = PairingSpike.Run(
            outcomes: [.readVersion: .timedOut(afterSeconds: 60)],
            pairingPromptShown: true, requirePairing: true,
            deviceModel: "iPhone 17 Pro", iOSVersion: "26.5", robotAPIVersion: nil,
            pin: PairingSpike.factoryPIN, startedAt: Self.aMoment)
        XCTAssertEqual(hung.reading.verdict, .readHung)

        let ok = PairingSpike.Run(
            outcomes: Dictionary(uniqueKeysWithValues:
                PairingSpike.Step.allCases.map { ($0, PairingSpike.Outcome.ok(seconds: 1)) }),
            pairingPromptShown: true, requirePairing: true,
            deviceModel: "iPhone 17 Pro", iOSVersion: "26.5", robotAPIVersion: 16,
            pin: PairingSpike.factoryPIN, startedAt: Self.aMoment)
        XCTAssertEqual(ok.reading.verdict, .flagCanDefaultOn)
    }
}

// MARK: - everything the report has to say and used not to

/// THE REPORT IS THE DELIVERABLE, AND EVERY SENTENCE IN IT HAS TO BE TRUE OF THE
/// CODE. It is written to be pasted into Pollen's issue tracker by a stranger,
/// where a maintainer will decide on the strength of it whether a hang was a
/// hang. Each test below pins a claim the report was making that the harness was
/// not backing up — or a fact an engineer needs to reproduce the run and was not
/// being given.
extension PairingSpikeTests {

    /// A run that reached the end and looked at what came back.
    private var fullyAnswered: PairingSpike.Run {
        run(Dictionary(uniqueKeysWithValues:
                PairingSpike.Step.allCases.map { ($0, PairingSpike.Outcome.ok(seconds: 1)) }),
            prompt: true,
            runNumber: 3,
            sightings: [theDuck, theOtherThing],
            tested: theDuck,
            hello: DuckLink.Hello(apiVersion: 16, daemonVersion: "0.4.1", revision: "abc1234"),
            info: DuckLink.SystemInfo(name: "microduck-a3f1",
                                      serial: "10000000abcd1234", uptimeSeconds: 11520))
    }

    /// WHICH PIN WAS TRIED WAS NOWHERE IN THE REPORT. A maintainer reading
    /// "system.authenticate REFUSED" has no way to tell a wrong PIN from a
    /// broken method without it, and the factory one is published in their own
    /// repository so naming it costs nothing.
    func testTheReportNamesThePINThatWasTried() {
        XCTAssertTrue(fullyAnswered.report().contains("PIN tried: 000000 — the factory PIN"))
    }

    /// A PIN SOMEBODY SET ON THEIR OWN ROBOT IS A REAL SECRET, and this document
    /// exists to be pasted in public. The fact that a PIN was tried is always
    /// stated; the digits are quoted only in the case where they are already
    /// published.
    func testAProvisionedPINIsNotPrintedIntoADocumentMeantForAnIssueTracker() {
        var outcomes = throughTheRead
        outcomes[.subscribe] = .ok(seconds: 0.1)
        outcomes[.hello] = .ok(seconds: 0.3)
        outcomes[.authenticate] = .refused(seconds: 0.4, "The duck refused: bad pin (-32001)")
        let text = run(outcomes, pin: "849302").report()
        XCTAssertFalse(text.contains("849302"))
        XCTAssertTrue(text.contains("PIN tried: a PIN of this robot's own, 6 characters, NOT "
                                    + "printed here"))
    }

    /// A RUN THAT NEVER GOT THERE TRIED NO PIN. The value is carried from the
    /// moment a duck is picked, so "PIN tried: 000000" under a run that stopped
    /// at the scan describes a write that was never put on any wire.
    func testARunThatNeverReachedAuthenticateDoesNotClaimToHaveTriedAPIN() {
        let text = stoppedAtConnect.report()
        XCTAssertTrue(text.contains("PIN never tried — the run stopped before "
                                    + "system.authenticate. It would have used 000000"))
        XCTAssertFalse(text.contains("PIN tried:"))
        // And a run that did reach it says the other thing.
        XCTAssertTrue(fullyAnswered.report().contains("PIN tried: 000000"))
    }

    /// WHEN, AND HOW MANY TIMES. Neither was in the report, and both are things
    /// a maintainer asks first: a run with no date cannot be lined up against a
    /// log on the robot, and "run 7" says the tester is not filing their first
    /// attempt.
    func testTheReportCarriesWhenTheRunHappenedAndHowManyRunsThisIs() {
        let text = fullyAnswered.report()
        XCTAssertTrue(text.contains("Run started: 2026-09-01T12:00:00Z"), text)
        XCTAssertTrue(text.contains("this is run 3 from this phone against this peripheral"))
        // And it says what the count is actually keyed on, because that is not
        // the duck — see DuckLink.identifierIsNotAnIdentity.
        XCTAssertTrue(text.contains("change of Bluetooth address"))
        // Nothing counted, nothing claimed.
        XCTAssertFalse(run(throughTheRead).report().contains("this is run"))
    }

    /// THE SCAN STEP USED TO END AT THE FIRST SIGHTING OF ANYTHING, which need
    /// not be the duck that was then tested — so a report could time a hang
    /// against a robot whose row somebody never tapped. The window is listed.
    func testTheReportNamesTheDuckThatWasTestedAndWhatElseWasSeen() {
        let text = fullyAnswered.report()
        XCTAssertTrue(text.contains("Tested: microduck-a3f1, -58 dBm — advertises the robot's "
                                    + "service UUID"))
        XCTAssertTrue(text.contains("Also heard in the same window:"))
        XCTAssertTrue(text.contains("rubber-duckling, -91 dBm — a duck-ish name and nothing else"))
        // And it refuses to be read as a census: a device matching none of the
        // three tiers was never recorded at all.
        XCTAssertTrue(text.contains("not a census of the room"))
    }

    func testAScanThatSawNothingSaysSoRatherThanListingAnEmptyRoom() {
        let text = run(throughTheRead).report()
        XCTAssertTrue(text.contains("What the scan saw\n-----------------\nNothing was seen."))
        XCTAssertFalse(text.contains("Also seen"))
    }

    /// THE STEP CLAIMED "REAL DATA" AND THE HARNESS PARSED NOTHING BUT THE
    /// JSON-RPC ID. Either the report shows what the robot said or it must not
    /// use the word — and the daemon build and the SoC serial are the two most
    /// useful things the whole sequence produces.
    func testTheReportPrintsWhatHelloAndSystemInfoActuallyAnswered() {
        let text = fullyAnswered.report()
        XCTAssertTrue(text.contains("hello: btd 0.4.1, revision abc1234, API version 16"))
        XCTAssertTrue(text.contains("system.info: name \"microduck-a3f1\", "
                                    + "serial \"10000000abcd1234\", up 11520 s (3 h 12 m 0 s)"))
        XCTAssertTrue(text.contains("The serial is the durable identity"))
        // The step's own claim now matches what is printed under it.
        XCTAssertTrue(PairingSpike.Step.systemInfo.establishes.contains("serial"))
    }

    /// A run that never got an answer says so, rather than leaving a heading
    /// with nothing under it.
    /// A SILENCE AND AN UNREADABLE ANSWER ARE NOT THE SAME THING HERE EITHER.
    /// This section printed "no answer this app could read" under a step that
    /// had timed out with nothing arriving at all — the same substitution the
    /// whole document exists to prevent, made in a quieter place.
    func testAnUnansweredRunSaysWhyRatherThanBlamingItsOwnParser() {
        // hungRead never got past the read, so neither call was ever sent.
        let stopped = hungRead.report()
        XCTAssertTrue(stopped.contains("hello: not asked — the run stopped before this step."))
        XCTAssertTrue(stopped.contains("system.info: not asked — the run stopped before this "
                                       + "step. Nothing here names the robot."))
        XCTAssertFalse(stopped.contains("could not read"))

        // A call that WAS sent and answered with silence says that instead.
        var outcomes = throughTheRead
        outcomes[.subscribe] = .ok(seconds: 0.1)
        outcomes[.hello] = .timedOut(afterSeconds: 15)
        XCTAssertTrue(run(outcomes).report()
            .contains("hello: no answer at all inside 15.00 s."))

        // And a refusal keeps the robot's own words.
        outcomes[.hello] = .refused(seconds: 0.4, "The duck refused: bad pin (-32001)")
        XCTAssertTrue(run(outcomes).report()
            .contains("hello: refused — The duck refused: bad pin (-32001)"))
    }

    /// THE ONE CONTRADICTION THE REPORT SHIPPED WITH. A read answer that lands
    /// after its own deadline is kept — which version a robot runs is worth
    /// knowing however late — but the step keeps its `.timedOut`, and the Setup
    /// section was printing "Robot API version: 16, read as one byte off the RPC
    /// characteristic" above a Reading that said nothing came back at all.
    func testALateReadByteIsNotPrintedAsAReadThatWorked() {
        let late = run([.scan: .ok(seconds: 2.1), .connect: .ok(seconds: 0.8),
                        .discover: .ok(seconds: 0.2), .readVersion: .timedOut(afterSeconds: 60)],
                       prompt: true, apiVersion: 16)
        let text = late.report()
        XCTAssertTrue(text.contains("Robot API version: 16 — but that byte arrived AFTER the "
                                    + "read's 60.00 s budget had already run out"))
        XCTAssertFalse(text.contains("read as one byte off the RPC characteristic"))
        // The verdict is untouched: it is still a hang.
        XCTAssertEqual(late.reading.verdict, .readHung)
        // And a read that actually answered still reads plainly.
        XCTAssertTrue(cleanPass.report()
            .contains("Robot API version: 16, read as one byte off the RPC characteristic"))
    }

    /// AN AMBIGUITY THE RUN HAD ALREADY RESOLVED. "Either the PIN is wrong or
    /// the robot predates API version 4" — printed under a Setup section that
    /// names the robot's API version four lines earlier.
    func testAuthenticateResolvesTheRobotAgeAmbiguityFromTheVersionTheReadRecorded() {
        var outcomes = throughTheRead
        outcomes[.subscribe] = .ok(seconds: 0.1)
        outcomes[.hello] = .ok(seconds: 0.3)
        outcomes[.authenticate] = .refused(seconds: 0.4, "The duck refused: bad pin (-32001)")

        let modern = run(outcomes, prompt: true, apiVersion: 16)
        XCTAssertTrue(modern.explanation(for: .authenticate).contains("this is NOT the robot's age"))
        XCTAssertTrue(modern.explanation(for: .authenticate)
            .contains("The PIN itself was refused or went unanswered."))
        XCTAssertTrue(modern.report().contains("this is NOT the robot's age"))

        let ancient = run(outcomes, prompt: true, apiVersion: 3)
        XCTAssertTrue(ancient.explanation(for: .authenticate)
            .contains("this robot has no PIN method at all"))
        XCTAssertNotEqual(ancient.explanation(for: .authenticate),
                          modern.explanation(for: .authenticate))

        // Only when the read never returned a version does the ambiguity stand —
        // and then it says why it stands.
        let unknown = run(outcomes, prompt: true, apiVersion: nil)
        XCTAssertTrue(unknown.explanation(for: .authenticate).contains("API version 4"))
        XCTAssertTrue(unknown.explanation(for: .authenticate)
            .contains("This run cannot say which"))

        // Every other step is unchanged: the general sentence is the answer.
        for step in PairingSpike.Step.allCases where step != .authenticate {
            XCTAssertEqual(modern.explanation(for: step), step.failureMeans, "\(step)")
        }
    }

    /// THE REPORT DESCRIBED A SCAN THE CODE DOES NOT RUN. "Scanning UNFILTERED"
    /// is true of the CoreBluetooth call and misleading about what happens next:
    /// every device in range IS reported to the app, and the app then ranks them
    /// by three tiers and drops the rest.
    func testTheScanStepDescribesTheScanTheCodeActuallyRuns() {
        let says = PairingSpike.Step.scan.establishes
        XCTAssertTrue(says.contains("no service filter"))
        XCTAssertTrue(says.contains("ranked here in software"))
        XCTAssertTrue(says.contains("three tiers"))
        XCTAssertFalse(says.contains("scanning UNFILTERED"))
    }

    /// BLUETOOTH OFF WAS REPORTED AS THE DUCK'S SILENCE. With the radio off,
    /// `scanForPeripherals` is never called at all — nothing was ever going to
    /// answer — and the scan step sat out its whole budget and was written up as
    /// "TIMED OUT — no answer and no error" under a sentence blaming the robot
    /// for not advertising. That is a fabricated observation about somebody
    /// else's hardware, produced by a phone with its radio switched off.
    func testAPhoneSideRadioFailureIsNotReportedAsTheDucksSilence() {
        for problem in PairingSpike.RadioProblem.allCases {
            let blocked = run([.scan: .refused(seconds: 0.01, problem.reason)], apiVersion: nil)
            let text = blocked.report()
            XCTAssertTrue(text.contains("REFUSED after 0.01 s — \(problem.reason)"), "\(problem)")
            XCTAssertTrue(problem.reason.contains("Nothing here is about the duck."), "\(problem)")
            XCTAssertFalse(text.contains("1. Scan [budget 40.00 s]: TIMED OUT"), "\(problem)")
            // The reading stops the run where it stopped and claims nothing.
            XCTAssertEqual(blocked.reading.verdict, .establishesNothing)
            XCTAssertTrue(blocked.reading.body.contains(problem.reason), "\(problem)")
        }
        // The two the finding names, in the words it names them in.
        XCTAssertTrue(PairingSpike.RadioProblem.off.reason
            .hasPrefix("Bluetooth is off on this iPhone"))
        XCTAssertTrue(PairingSpike.RadioProblem.notPermitted.reason
            .hasPrefix("This app is not allowed to use Bluetooth"))
        // And the step's own sentence now puts the phone first.
        XCTAssertTrue(PairingSpike.Step.scan.failureMeans
            .contains("the first thing to rule out is this phone rather than the duck"))
    }

    /// ONE RUN IS ONE OBSERVATION, and a report that stopped at its own verdict
    /// invited a maintainer to act on a single sample of a radio.
    func testEveryReportEndsByAskingForAnotherRun() {
        for text in [cleanPass.report(), hungRead.report(),
                     refusedRead.report(), stoppedAtConnect.report()] {
            XCTAssertTrue(text.contains("One run is one observation."))
            XCTAssertTrue(text.contains("Forget This Device"))
            XCTAssertTrue(text.contains("Send every run, including the ones that disagree"))
        }
    }

    /// The flag is a person's answer, and the report says so rather than
    /// presenting it as something the phone measured.
    func testTheReportAdmitsTheFlagIsSomebodysAnswerAndNotAMeasurement() {
        let text = hungRead.report()
        XCTAssertTrue(text.contains("btd started with --require-pairing ON"))
        XCTAssertTrue(text.contains("as answered by whoever launched it"))
        XCTAssertTrue(text.contains("a person's answer and not a measurement"))
    }

    /// An answer is filed by the id it was asked under, so the three RPC steps
    /// need three distinct ids and the five GATT steps need none.
    func testEachRPCStepHasItsOwnIDAndTheGATTStepsHaveNone() {
        let withIDs = PairingSpike.Step.allCases.filter { $0.requestID != nil }
        XCTAssertEqual(withIDs, [.hello, .authenticate, .systemInfo])
        XCTAssertEqual(Set(withIDs.compactMap(\.requestID)).count, 3)
        for step in withIDs {
            XCTAssertEqual(PairingSpike.step(forRequestID: step.requestID!), step)
        }
        for step in PairingSpike.Step.allCases where step.requestID == nil {
            XCTAssertTrue([.scan, .connect, .discover, .readVersion, .subscribe].contains(step))
        }
        // An id this app never sent belongs to no step, which is what lets the
        // harness report a stranger's answer instead of crediting it to a step.
        XCTAssertNil(PairingSpike.step(forRequestID: 99))
    }

    /// Seconds AND words, because they answer different questions: the number is
    /// the field the robot returned and the gloss is what tells a reader the
    /// robot had been up ninety seconds when this ran.
    func testAnUptimeIsPrintedAsBothTheFieldAndTheReading() {
        XCTAssertEqual(PairingSpike.uptime(11520), "11520 s (3 h 12 m 0 s)")
        XCTAssertEqual(PairingSpike.uptime(90), "90 s (1 m 30 s)")
        XCTAssertEqual(PairingSpike.uptime(7), "7 s (7 s)")
        XCTAssertEqual(PairingSpike.uptime(0), "0 s (0 s)")
    }

    /// UTC, so the tester's locale is not part of the finding.
    func testATimestampMeansTheSameThingToEverybodyWhoReadsIt() {
        XCTAssertEqual(PairingSpike.timestamp(Self.aMoment), "2026-09-01T12:00:00Z")
    }
}

// MARK: - the reading's own prose

extension PairingSpikeTests {

    /// A REFUSAL CARRIES SOMEBODY ELSE'S WORDS AND THEY MAY ALREADY END. The
    /// reading appended a full stop to whatever the outcome line said, which
    /// produced "Nothing here is about the duck.." exactly when the reason had
    /// been written most carefully.
    func testAStoppedRunsReasonIsNotGivenTwoFullStops() {
        let blocked = run([.scan: .refused(seconds: 0.01, PairingSpike.RadioProblem.off.reason)],
                          apiVersion: nil)
        XCTAssertFalse(blocked.reading.body.contains(".."), blocked.reading.body)
        XCTAssertTrue(blocked.reading.body.contains("Nothing here is about the duck. §5.5"))
        // A line that does NOT end in a full stop still gets one.
        XCTAssertTrue(stoppedAtConnect.reading.body
            .contains("TIMED OUT after 15.00 s — no answer and no error. §5.5"))
        XCTAssertEqual(PairingSpike.stopped("ok — 1.00 s"), "ok — 1.00 s.")
        XCTAssertEqual(PairingSpike.stopped("Already done."), "Already done.")
    }

    /// THE SAME RESOLVED SENTENCE IN BOTH PLACES. The caveat the reading bolts
    /// onto a successful read names the first step that failed after it — which
    /// can be `authenticate`, and was printing the wrong-PIN-or-old-robot
    /// ambiguity there while the Steps section three inches above resolved it.
    func testTheCaveatAfterASuccessfulReadResolvesTheAuthenticateAmbiguityToo() {
        var outcomes = throughTheRead
        outcomes[.subscribe] = .ok(seconds: 0.1)
        outcomes[.hello] = .ok(seconds: 0.3)
        outcomes[.authenticate] = .refused(seconds: 0.4, "The duck refused: bad pin (-32001)")
        let broken = run(outcomes, prompt: true, apiVersion: 16)

        let body = broken.reading.body
        XCTAssertEqual(broken.reading.verdict, .flagCanDefaultOn)
        XCTAssertTrue(body.contains("The run did not finish, though: system.authenticate"))
        XCTAssertTrue(body.contains("this is NOT the robot's age"))
        XCTAssertFalse(body.contains("Either the PIN is wrong or the robot predates"))
    }

    // MARK: - the hang run, and every sentence that presupposes it did not happen

    /// THE RUN THIS SPIKE EXISTS TO PRODUCE, and the report was lying in it.
    /// `advance(after: .readVersion)` carries on past a read that timed out on
    /// purpose; the later steps then time out too, and their `failureMeans`
    /// — "the bond already succeeded upstream", "the link is up and
    /// encrypted", "the bond and the PIN both already proven above" — were
    /// printed under each of them. In this run every one of those is false.
    func testTheHangRunNeverClaimsABondWasProvenDownstreamOfTheRead() {
        let hang = run([
            .scan: .ok(seconds: 3), .connect: .ok(seconds: 1), .discover: .ok(seconds: 0.5),
            .readVersion: .timedOut(afterSeconds: 60),
            .subscribe: .ok(seconds: 0.2),
            .hello: .timedOut(afterSeconds: 15),
            .authenticate: .timedOut(afterSeconds: 15),
            .systemInfo: .timedOut(afterSeconds: 15),
        ], prompt: false, apiVersion: nil)
        let report = hang.report()
        for lie in ["already succeeded upstream", "already proven above", "up and encrypted",
                    "robot-age answer"] {
            XCTAssertFalse(report.contains(lie), "the hang run printed: \(lie)")
        }
        XCTAssertTrue(report.contains(PairingSpike.downstreamOfAnUnfinishedRead))
        XCTAssertEqual(hang.explanation(for: .hello), PairingSpike.downstreamOfAnUnfinishedRead)
        XCTAssertEqual(hang.explanation(for: .systemInfo), PairingSpike.downstreamOfAnUnfinishedRead)
        // The read itself keeps its own sentence — it is the finding.
        XCTAssertTrue(hang.explanation(for: .readVersion).contains("reproduces the macOS hang"))
    }

    /// A run that ended before the read was issued must not print the read's
    /// "a TIMEOUT here reproduces the macOS hang" under a headline saying the
    /// read was never reached.
    func testARunThatNeverIssuedTheReadSaysSoInsteadOfExplainingARead() {
        let dropped = run([.scan: .ok(seconds: 2), .connect: .ok(seconds: 1),
                           .discover: .ok(seconds: 0.5)], apiVersion: nil)
        XCTAssertTrue(dropped.reading.body.contains("The read was never issued"), dropped.reading.body)
        XCTAssertFalse(dropped.reading.body.contains("reproduces the macOS hang"), dropped.reading.body)
    }

    /// The caveat after a successful read goes through `stopped(_:)` like the
    /// other branch, so a reason that already ends in a full stop gets one.
    func testTheSuccessfulReadCaveatDoesNotDoubleTheFullStop() {
        var outcomes = throughTheRead
        outcomes[.subscribe] = .ok(seconds: 0.1)
        outcomes[.hello] = .refused(seconds: 0.4, "The link was gone before the write.")
        let body = run(outcomes, prompt: true).reading.body
        XCTAssertFalse(body.contains(".."), body)
        XCTAssertTrue(body.contains("before the write. That is a separate defect"), body)
    }

    /// "No answer at all" may never be printed about a robot that answered
    /// late. The step keeps its timeout; the report says the answer came.
    func testALateAnswerIsNeverWrittenUpAsSilence() {
        var outcomes = throughTheRead
        outcomes[.subscribe] = .ok(seconds: 0.1)
        outcomes[.hello] = .timedOut(afterSeconds: 15)
        let slow = run(outcomes, prompt: true,
                       lateAnswers: [.hello: "an answer for hello arrived 18.40 s after the step began, past its 15.00 s budget"])
        let report = slow.report()
        XCTAssertTrue(report.contains("LATE ANSWER: an answer for hello arrived 18.40 s"), report)
        XCTAssertTrue(report.contains("hello: no answer inside 15.00 s — but one ARRIVED LATE"), report)
        XCTAssertFalse(report.contains("no answer at all inside 15.00 s"), report)
        // Without a late answer the silence is still called a silence.
        let silent = run(outcomes, prompt: true)
        XCTAssertTrue(silent.report().contains("hello: no answer at all inside 15.00 s."))
    }

    /// A PIN whose write never reached the wire is not "tried".
    func testAPinIsNotPrintedAsTriedWhenItsWriteNeverLeftThePhone() {
        var outcomes = throughTheRead
        outcomes[.subscribe] = .ok(seconds: 0.1)
        outcomes[.hello] = .ok(seconds: 0.3)
        outcomes[.authenticate] = .refused(seconds: 0.01, "The link was gone before the write.")
        let unsent = run(outcomes, prompt: true, authenticateWritten: false)
        XCTAssertTrue(unsent.report().contains("PIN never put on the wire"), unsent.report())
        XCTAssertFalse(unsent.report().contains("PIN tried:"), unsent.report())
        let sent = run(outcomes, prompt: true, authenticateWritten: true)
        XCTAssertTrue(sent.report().contains("PIN tried: 000000"), sent.report())
    }

    /// A duck iOS handed back from memory is not something the radio heard.
    func testRememberedDucksAreNotListedAsHeard() {
        let fromMemory = DuckLink.Sighting(name: "microduck-a3f1", rssi: nil,
                                           address: .notBroadcast, tier: .knownBefore, heard: false)
        let silent = run([.scan: .ok(seconds: 40)], apiVersion: nil,
                         sightings: [fromMemory], tested: fromMemory)
        let report = silent.report()
        XCTAssertTrue(report.contains("NOTHING WAS HEARD ON THE RADIO"), report)
        XCTAssertTrue(report.contains("NOT heard in this window"), report)
        XCTAssertFalse(report.contains("Also heard"), report)
        // And a heard duck beside a remembered one keeps the two lists apart.
        let both = run([.scan: .ok(seconds: 3)], apiVersion: nil,
                       sightings: [theDuck, fromMemory], tested: theDuck)
        XCTAssertTrue(both.report().contains("Remembered from an earlier run and NOT heard this time:"))
        XCTAssertFalse(both.report().contains("NOTHING WAS HEARD"))
    }

    /// Notifications the robot sent are reported as what they are.
    func testNotificationsAreReportedAndNeverAsRefusals() {
        var outcomes = throughTheRead
        outcomes[.subscribe] = .ok(seconds: 0.1)
        let chatty = run(outcomes, prompt: true, notifications: ["update.progress", "update.progress"])
        XCTAssertTrue(chatty.report().contains("also sent 2 notification(s)"), chatty.report())
        XCTAssertTrue(chatty.report().contains("update.progress, update.progress"))
    }
}
