import XCTest
@testable import StudioKit

/// The front door's answers, and every sentence it can put on the glass.
///
/// WHAT THESE TESTS ARE ACTUALLY FOR. `DeviceCard` makes seven judgements that
/// used to be made inside a `View`, where nothing on Linux could reach them:
/// which word describes a duck's pose, how stale a reply has to be before this
/// app stops claiming the duck is live, whether a control may be drawn at all,
/// and which of six kit types wrote the sentence in the banner. Each of those
/// is a decision somebody could quietly change and no build would notice — the
/// symptom is a screen that says "Upright" about a duck on its side, or a Drive
/// button that does nothing.
///
/// THE SENTENCE ASSERTIONS ARE IDENTITY ASSERTIONS, NOT SPELLING ONES. Almost
/// nothing here compares against a literal paragraph; it compares against the
/// constant the erroring type already publishes. That is the point of the
/// funnel: if `BenchSetup.Diagnosis.nothingListening` is reworded, the banner
/// says the new words, and this test keeps passing because it was never a
/// second copy of the old ones. What it does pin is that the banner did not
/// write its OWN.
final class DeviceCardTests: XCTestCase {

    // MARK: - the word for what it is doing

    func testTheFiveWordsAreDriveViewsOwnStrings() {
        XCTAssertEqual(DeviceCard.Doing.notDriving, "Not driving")
        XCTAssertEqual(DeviceCard.Doing.waitingForTheBench, "Waiting for the bench")
        XCTAssertEqual(DeviceCard.Doing.onItsSide, "On its side")
        XCTAssertEqual(DeviceCard.Doing.driving, "Driving")
        XCTAssertEqual(DeviceCard.Doing.upright, "Upright")
    }

    /// NOTHING BACK YET IS NOT THE SAME AS LYING DOWN. A nil `upright` means no
    /// state block has arrived on this link; reporting that as "On its side"
    /// would be this app inventing a fall.
    func testNoStateBlockYetSaysWhetherAnythingWasAsked() {
        XCTAssertEqual(DeviceCard.Doing.word(upright: nil, running: false),
                       DeviceCard.Doing.notDriving)
        XCTAssertEqual(DeviceCard.Doing.word(upright: nil, running: true),
                       DeviceCard.Doing.waitingForTheBench)
    }

    /// A FALLEN DUCK IS ON ITS SIDE WHETHER OR NOT SOMEBODY IS DRIVING. The
    /// pose is tested before the driving, which is the order `DriveView`'s own
    /// `duckWord` used.
    func testOnItsSideBeatsDriving() {
        XCTAssertEqual(DeviceCard.Doing.word(upright: false, running: true),
                       DeviceCard.Doing.onItsSide)
        XCTAssertEqual(DeviceCard.Doing.word(upright: false, running: false),
                       DeviceCard.Doing.onItsSide)
    }

    func testUprightSplitsOnWhetherItIsBeingDriven() {
        XCTAssertEqual(DeviceCard.Doing.word(upright: true, running: true),
                       DeviceCard.Doing.driving)
        XCTAssertEqual(DeviceCard.Doing.word(upright: true, running: false),
                       DeviceCard.Doing.upright)
    }

    // MARK: - who this duck is

    private static let benchIdentity = DuckIdentity(name: "192.168.1.20",
                                                    colourway: .teal, kind: .sim)
    private static let robotIdentity = DuckIdentity(name: "microduck-a1",
                                                    colourway: .yellow, kind: .real)

    /// A BENCH WITH NOBODY'S NAME ON IT IS NAMED AFTER ITS HOST, which is what
    /// `BenchPeer.init` fell back to and why: `/health` says "duck-bench" for
    /// every bench on the desk.
    func testAnUnnamedBenchIsNamedAfterItsHost() {
        let who = DeviceCard.Who.of(Self.benchIdentity)
        XCTAssertEqual(who.name, "192.168.1.20")
        XCTAssertEqual(who.nameCameFrom, .benchHost)
        XCTAssertEqual(who.kindWord, "sim")
        XCTAssertEqual(who.colourway, .teal)
    }

    func testAnUnnamedRobotIsNamedByItsAdvertisement() {
        let who = DeviceCard.Who.of(Self.robotIdentity)
        XCTAssertEqual(who.nameCameFrom, .localName)
        XCTAssertEqual(who.kindWord, "real")
    }

    func testATypedNameBeatsTheHost() {
        let who = DeviceCard.Who.of(Self.benchIdentity, typed: "Kitchen bench")
        XCTAssertEqual(who.name, "Kitchen bench")
        XCTAssertEqual(who.nameCameFrom, .typedByYou)
    }

    /// AN ACCIDENTAL SPACE IS NOT A NAME. A card titled " " is a card with its
    /// first question unanswered.
    func testWhitespaceIsNotATypedName() {
        let who = DeviceCard.Who.of(Self.benchIdentity, typed: "   ")
        XCTAssertEqual(who.name, "192.168.1.20")
        XCTAssertEqual(who.nameCameFrom, .benchHost)
    }

    /// THE ROBOT'S OWN ANSWER OUTRANKS EVERYTHING, including a name the person
    /// typed — because this is the one source in the list that came from the
    /// duck.
    func testSystemInfoBeatsATypedName() {
        let info = DuckLink.SystemInfo(name: "Ferdinand", serial: "SN-9", uptimeSeconds: 90)
        let who = DeviceCard.Who.of(Self.robotIdentity, typed: "Mine", systemInfo: info)
        XCTAssertEqual(who.name, "Ferdinand")
        XCTAssertEqual(who.nameCameFrom, .systemInfo)
    }

    /// THE KIND IS NEVER PROMOTED BY A NAME ARRIVING. A bench that answered
    /// `system.info` — which cannot happen, and is exactly the sort of thing a
    /// future bridge peer could be made to fake — is still a simulator.
    func testAnArrivingNameNeverMakesASimIntoARobot() {
        let info = DuckLink.SystemInfo(name: "Ferdinand", serial: "SN-9", uptimeSeconds: 90)
        let who = DeviceCard.Who.of(Self.benchIdentity, systemInfo: info)
        XCTAssertEqual(who.kind, .sim)
        XCTAssertEqual(who.kindWord, "sim")
    }

    /// The BLE case carries `DuckLink`'s own warning rather than a new one.
    func testTheLocalNameSentenceQuotesTheIdentityWarning() {
        XCTAssertTrue(DeviceCard.Who.Source.localName.says
            .contains(DuckLink.identifierIsNotAnIdentity))
    }

    func testEverySourceSaysSomething() {
        for source in DeviceCard.Who.Source.allCases {
            XCTAssertFalse(source.says.isEmpty, "\(source) has nothing to say")
        }
    }

    // MARK: - is it online

    private static let noon = Date(timeIntervalSince1970: 1_700_000_000)

    func testNeverAnsweredIsNotLiveAndSaysSo() {
        let presence = DeviceCard.Presence(lastReplyAt: nil, transport: .bench)
        XCTAssertFalse(presence.isLive(now: Self.noon))
        XCTAssertEqual(presence.standing(now: Self.noon), .neverAnswered)
        XCTAssertTrue(presence.says(now: Self.noon).contains("Nothing has ever come back"))
    }

    func testARecentReplyIsLive() {
        let presence = DeviceCard.Presence(lastReplyAt: Self.noon.addingTimeInterval(-1),
                                           transport: .bench)
        XCTAssertTrue(presence.isLive(now: Self.noon))
        XCTAssertEqual(presence.standing(now: Self.noon), .answering)
    }

    /// THE BOUNDARY IS INCLUSIVE AND IT IS ASSERTED ON BOTH SIDES, because a
    /// tolerance nobody has pinned is a tolerance somebody will change to `<`
    /// while tidying and never notice.
    func testTheToleranceBoundary() {
        let tolerance = DeviceCard.Presence.answeringWithin
        let exactly = DeviceCard.Presence(
            lastReplyAt: Self.noon.addingTimeInterval(-tolerance), transport: .bench)
        XCTAssertTrue(exactly.isLive(now: Self.noon))
        let justOver = DeviceCard.Presence(
            lastReplyAt: Self.noon.addingTimeInterval(-tolerance - 0.001), transport: .bench)
        XCTAssertFalse(justOver.isLive(now: Self.noon))
        XCTAssertEqual(justOver.standing(now: Self.noon), .waiting)
    }

    /// A CLOCK THAT MOVED BACKWARDS MUST NOT KILL A LIVE DUCK. A reply stamped
    /// in the future is still a reply.
    func testAReplyFromTheFutureIsStillLive() {
        let presence = DeviceCard.Presence(lastReplyAt: Self.noon.addingTimeInterval(30),
                                           transport: .bench)
        XCTAssertTrue(presence.isLive(now: Self.noon))
    }

    /// THE STALE SENTENCE SAYS BOTH HALVES. Silence on this screen is genuinely
    /// ambiguous — nothing answered, or nothing was asked — and a sentence that
    /// only said the first would be telling somebody their duck had gone away.
    func testTheStaleSentenceAdmitsNothingMayHaveBeenAsked() {
        let presence = DeviceCard.Presence(lastReplyAt: Self.noon.addingTimeInterval(-60),
                                           transport: .bench)
        let said = presence.says(now: Self.noon)
        XCTAssertTrue(said.contains("pull to refresh"), said)
        XCTAssertTrue(said.contains("gone away"), said)
    }

    /// EVERY SENTENCE NAMES THE LINK, because "nothing came back" is about the
    /// app and "nothing came back over Bluetooth" is about the world.
    func testEverySentenceNamesTheTransport() {
        for transport in DuckTransportKind.allCases {
            let never = DeviceCard.Presence(lastReplyAt: nil, transport: transport)
            XCTAssertTrue(never.says(now: Self.noon).contains(transport.label))
            let live = DeviceCard.Presence(lastReplyAt: Self.noon, transport: transport)
            XCTAssertTrue(live.says(now: Self.noon).contains(transport.label))
            let stale = DeviceCard.Presence(lastReplyAt: Self.noon.addingTimeInterval(-600),
                                            transport: transport)
            XCTAssertTrue(stale.says(now: Self.noon).contains(transport.label))
        }
    }

    // MARK: - battery

    /// A SIM DUCK GETS `DuckBattery`'S OWN SENTENCE and not a second one.
    func testASimDuckHasNoBatteryToRead() {
        let charge = DeviceCard.Charge.of(Self.benchIdentity)
        XCTAssertEqual(charge, .noneToRead(DuckBattery.noneToRead))
        XCTAssertEqual(charge.says, DuckBattery.noneToRead)
    }

    /// A REAL DUCK ON THIS APP'S LINKS GETS THE OTHER ABSENCE. There is a cell;
    /// nothing in the vocabulary asks it anything.
    func testARealDuckHasNoLinkThatReportsCharge() {
        let charge = DeviceCard.Charge.of(Self.robotIdentity)
        XCTAssertEqual(charge, .notReported(DeviceCard.Charge.linkCarriesNoCharge))
        XCTAssertEqual(charge.says, DeviceCard.Charge.linkCarriesNoCharge)
    }

    /// THE TWO SENTENCES MUST NOT BE THE SAME SENTENCE. They have different
    /// causes and a person can act on exactly one of them.
    func testTheTwoAbsencesAreDifferentSentences() {
        XCTAssertNotEqual(DeviceCard.Charge.linkCarriesNoCharge, DuckBattery.noneToRead)
    }

    /// NEITHER SENTENCE CONTAINS A PERCENTAGE. The whole point is that no
    /// number was measured.
    func testNeitherChargeSentenceQuotesANumber() {
        for sentence in [DuckBattery.noneToRead, DeviceCard.Charge.linkCarriesNoCharge] {
            XCTAssertFalse(sentence.contains("%"), sentence)
        }
    }

    // MARK: - can I control it

    /// A BENCH CARRIES DRIVE AND STOP, so both affordances may be drawn.
    func testABenchCarriesMoveAndStop() {
        let reach = DuckMethod.reach(for: .bench)
        for method in [DuckMethod.move, .stop] {
            let control = DeviceCard.Control.of(method, over: .bench, reach: reach)
            XCTAssertTrue(control.isLive, "\(method) should be live on a bench")
            XCTAssertNil(control.reason)
        }
    }

    /// BLUETOOTH DOES NOT, AND THE SENTENCE IS THE ROUTING TABLE'S OWN. It
    /// names the link and the method, which is what somebody staring at a
    /// missing Drive button needs told.
    func testBluetoothDoesNotCarryDrive() {
        let control = DeviceCard.Control.of(.move, over: .ble,
                                            reach: DuckMethod.reach(for: .ble))
        XCTAssertFalse(control.isLive)
        XCTAssertEqual(control.reason,
                       DuckCall.Misuse.outOfReach(.move, .ble).message)
    }

    /// A PEER THAT HAS NARROWED ITS REACH IS ANSWERED ON WHAT IT CARRIES, not
    /// on what its transport could. `DuckPeer` explicitly permits narrowing.
    func testANarrowedReachTakesTheControlAway() {
        let control = DeviceCard.Control.of(.move, over: .bench, reach: [.hello])
        XCTAssertFalse(control.isLive)
        XCTAssertEqual(control.reason,
                       DuckCall.Misuse.outOfReach(.move, .bench).message)
    }

    /// THE BENCH'S NAMED REFUSAL IS PREFERRED WHERE THERE IS ONE. There is none
    /// for move or stop today — `BenchPeer.refusal(for:)` answers nil for both
    /// — and this pins that, so the day a bench stops carrying one of them the
    /// card starts printing the bench's reason rather than the table's shrug.
    func testTheBenchHasNoNamedRefusalForTheTwoControls() {
        XCTAssertNil(BenchPeer.refusal(for: .move(.still)))
        XCTAssertNil(BenchPeer.refusal(for: .stop))
    }

    /// A METHOD WITH NO CALL SHAPE FALLS BACK TO THE TABLE rather than being
    /// asked a question about a pose nobody supplied. `robot.enable` is carried
    /// nowhere near a bench, so this is the routing table answering.
    func testAMethodOutsideTheTwoControlsIsAnsweredByTheTable() {
        let control = DeviceCard.Control.of(.enable, over: .bench,
                                            reach: DuckMethod.reach(for: .bench))
        XCTAssertFalse(control.isLive)
        XCTAssertEqual(control.reason,
                       DuckCall.Misuse.outOfReach(.enable, .bench).message)
    }

    // MARK: - the banner

    func testASetupDiagnosisCarriesItsOwnSentence() {
        let alarm = DeviceCard.Alarm.of(BenchSetup.Diagnosis.nothingListening)
        XCTAssertEqual(alarm?.sentence, BenchSetup.Diagnosis.nothingListening.message)
        XCTAssertEqual(alarm?.severity, .critical)
        XCTAssertEqual(alarm?.source, .benchSetup)
    }

    /// A CONNECTED BENCH IS NOT AN ALARM. Its message is good news, and good
    /// news in a red bar is a bar people stop reading.
    func testAConnectedDiagnosisIsNoAlarmAtAll() {
        XCTAssertNil(DeviceCard.Alarm.of(
            BenchSetup.Diagnosis.connected(policies: 9, plant: "flat")))
    }

    func testARadioProblemCarriesItsOwnReason() {
        let alarm = DeviceCard.Alarm.of(PairingSpike.RadioProblem.off)
        XCTAssertEqual(alarm.sentence, PairingSpike.RadioProblem.off.reason)
        XCTAssertEqual(alarm.source, .pairingSpike)
    }

    func testAReadErrorCarriesItsOwnMessage() {
        let alarm = DeviceCard.Alarm.of(DuckBench.ReadError.notJSON)
        XCTAssertEqual(alarm.sentence, DuckBench.ReadError.notJSON.message)
        XCTAssertEqual(alarm.source, .benchRead)
    }

    /// A NAMED REFUSAL IS A WARNING AND NOT A CRITICAL, because a peer that can
    /// refuse by name is a peer that is answering.
    func testABenchRefusalIsAWarning() {
        let alarm = DeviceCard.Alarm.of(BenchPeer.Refusal.resetIsNotTheInitialPose)
        XCTAssertEqual(alarm.sentence, BenchPeer.Refusal.resetIsNotTheInitialPose.message)
        XCTAssertEqual(alarm.severity, .warning)
        XCTAssertEqual(alarm.source, .benchRefusal)
    }

    /// THE DUCK'S OWN REFUSAL KEEPS ITS CODE, because a refusal by number is
    /// what somebody quotes in a bug report.
    func testADuckRefusalKeepsItsCode() {
        let failure = DuckReply.Failure(code: -32_601, message: "unknown method")
        let alarm = DeviceCard.Alarm.of(failure)
        XCTAssertEqual(alarm.sentence, failure.says)
        XCTAssertTrue(alarm.sentence.contains("-32601"), alarm.sentence)
        XCTAssertEqual(alarm.source, .duckRefusal)
    }

    func testNothingWrongDrawsNothing() {
        XCTAssertTrue(DeviceCard.Banner.nothingWrong.isEmpty)
        XCTAssertNil(DeviceCard.Banner.nothingWrong.worst)
        XCTAssertTrue(DeviceCard.Banner.of([]).isEmpty)
    }

    /// WORST FIRST, because the screen puts this above everything and a person
    /// reading downwards should meet the thing that invalidates the rest of the
    /// card before they read the rest of it.
    func testTheBannerPutsCriticalsFirst() {
        let warning = DeviceCard.Alarm.of(BenchPeer.Refusal.nothingHasHappenedYet)
        let critical = DeviceCard.Alarm.of(PairingSpike.RadioProblem.notPermitted)
        let banner = DeviceCard.Banner.of([warning, critical])
        XCTAssertEqual(banner.worst?.source, .pairingSpike)
        XCTAssertEqual(banner.alarms.map(\.severity), [.critical, .warning])
    }

    /// STABLE INSIDE A SEVERITY. Two criticals swapping places between runs is
    /// a banner whose top line changes when nothing about the duck did.
    func testOrderInsideASeverityIsTheCallersOrder() {
        let first = DeviceCard.Alarm.of(DuckBench.ReadError.empty)
        let second = DeviceCard.Alarm.of(DuckBench.ReadError.notJSON)
        let banner = DeviceCard.Banner.of([first, second])
        XCTAssertEqual(banner.alarms.map(\.sentence), [first.sentence, second.sentence])
        let flipped = DeviceCard.Banner.of([second, first])
        XCTAssertEqual(flipped.alarms.map(\.sentence), [second.sentence, first.sentence])
    }

    /// TWO ALARMS FROM DIFFERENT PLACES BOTH SURVIVE, which is the reason this
    /// is a list: fixing a bench address and then discovering Bluetooth was off
    /// as well is two visits where it should have been one.
    func testEveryAlarmSurvives() {
        let banner = DeviceCard.Banner.of([
            DeviceCard.Alarm.of(PairingSpike.RadioProblem.off),
            DeviceCard.Alarm.of(DuckBench.ReadError.notJSON),
            DeviceCard.Alarm.of(BenchPeer.Refusal.nothingHasHappenedYet),
        ])
        XCTAssertEqual(banner.alarms.count, 3)
    }

    /// AN ALARM'S IDENTITY IS ITS SOURCE AND ITS WORDS, so a `ForEach` over two
    /// different problems does not collapse them into one row.
    func testAlarmsFromDifferentSourcesHaveDifferentIdentities() {
        let a = DeviceCard.Alarm.of(DuckBench.ReadError.notJSON)
        let b = DeviceCard.Alarm.of(DuckBench.ReadError.empty)
        XCTAssertNotEqual(a.id, b.id)
    }

    // MARK: - the camera that is not there

    /// THE "NOT YET" IS A KIT STRING AND IT NAMES ITS EVIDENCE. It rests on the
    /// same fact `DuckLink.whatThisCanDo` states — payloads never cross BLE —
    /// and a video frame is the largest payload there is.
    func testTheCameraNotYetSaysWhy() {
        XCTAssertTrue(DeviceCard.noCameraYet.contains("too slow and too constrained"))
        XCTAssertTrue(DuckLink.whatThisCanDo.contains("too slow and too constrained"))
        XCTAssertFalse(DeviceCard.noCameraYet.isEmpty)
    }
}
