import XCTest
import DuckKit
@testable import StudioKit

/// The card, reading one state, with every absence given a sentence.
///
/// WHAT THESE TESTS ARE FOR. `DuckState` is built so that a field the daemon
/// stopped sending reads as nil rather than as zero — "a zero is a lie that
/// looks exactly like data" — and that discipline is worth nothing if the screen
/// above it draws a nil and a `false` the same way. So most of this file is
/// about nils: that a duck which did not say whether it is down is not reported
/// as standing, that a battery block which never arrived produces a sentence
/// rather than a bar, and that a percentage outside 0…100 is refused rather than
/// clamped into something plausible.
final class DeviceCardStateTests: XCTestCase {

    private static let robot = DuckIdentity(name: "Pip", colourway: .yellow, kind: .real)
    private static let bench = DuckIdentity(name: "10.0.0.5", colourway: .teal, kind: .sim)

    private static func state(fallen: Bool? = false,
                              limp: Bool? = false,
                              percent: Double? = nil,
                              volts: Double? = nil,
                              hasBattery: Bool = false,
                              policy: String? = "alpha_walking") -> DuckState {
        DuckState(
            policy: policy,
            safety: (fallen == nil && limp == nil)
                ? nil : DuckState.Safety(fallen: fallen, limp: limp),
            loop: DuckState.Loop(hz: 50, missed: 0),
            battery: hasBattery ? DuckState.Battery(volts: volts, percent: percent) : nil,
            odom: DuckState.Odometry(position: [0.1, 0.2], yaw: 0.3),
            move: DuckState.Move(requested: [0.3, 0, 0], applied: [0.3, 0, 0], limitedBy: []),
            receivedAt: Date(timeIntervalSince1970: 100))
    }

    // MARK: - the charge row

    /// A robot's own percentage, named as its own.
    func testARobotsOwnPercentageIsDrawnAndSaidToBeItsOwn() {
        let charge = DeviceCard.Charge.of(Self.state(percent: 62, volts: 11.4,
                                                     hasBattery: true), on: Self.robot)
        XCTAssertEqual(charge.percent, 62)
        XCTAssertTrue(charge.says.contains("62% charged"), charge.says)
        XCTAssertTrue(charge.says.contains(DeviceCard.Charge.reportedByTheRobot), charge.says)
    }

    /// A percentage worked out from the bus voltage says so, and says what a
    /// bus voltage does under load — the difference between a duck that is
    /// draining and a duck that is walking.
    func testAPercentageDerivedFromVoltageCarriesTheCaveat() {
        let charge = DeviceCard.Charge.of(Self.state(percent: nil, volts: 11.4,
                                                     hasBattery: true), on: Self.robot)
        XCTAssertNotNil(charge.percent)
        XCTAssertTrue(charge.says.contains(DeviceCard.Charge.derivedFromTheBusVoltage),
                      charge.says)
        XCTAssertTrue(charge.says.contains("sags under load"), charge.says)
    }

    /// A state with no battery in it produces a sentence and no number, and the
    /// sentence admits it cannot tell a renamed field from a robot that does not
    /// report charge.
    func testAStateWithNoBatteryDrawsNoNumber() {
        let charge = DeviceCard.Charge.of(Self.state(), on: Self.robot)
        XCTAssertNil(charge.percent)
        XCTAssertEqual(charge, .reportedNothing(DeviceCard.Charge.stateCarriedNoBattery))
        XCTAssertTrue(charge.says.contains("renamed field"), charge.says)
    }

    /// REFUSED RATHER THAN CLAMPED. 104% came from arithmetic and not from a
    /// cell, and clamping it to 100 turns a wrong number into a plausible one.
    func testAReadingOutsideAPercentageIsRefusedRatherThanClamped() {
        let charge = DeviceCard.Charge.of(Self.state(percent: 104, hasBattery: true),
                                          on: Self.robot)
        XCTAssertNil(charge.percent)
        XCTAssertEqual(charge, .reportedNothing(DeviceCard.Charge.readingWasNotAPercentage))
    }

    /// A SIMULATOR CANNOT REACH THE CHARGED CASE AT ALL, even carrying a battery
    /// block, because `DuckBattery` refuses to exist for anything but a real
    /// duck. The rule is in the type rather than in this function's care.
    func testASimulatorWithABatteryBlockStillHasNoCharge() {
        let charge = DeviceCard.Charge.of(Self.state(percent: 62, hasBattery: true),
                                          on: Self.bench)
        XCTAssertNil(charge.percent)
        XCTAssertEqual(charge, .noneToRead(DuckBattery.noneToRead))
    }

    /// The two absences that existed before the stream did are untouched: no
    /// cell at all, and a link with nothing that answers with a charge.
    func testTheTwoOlderAbsencesStillAnswerTheWayTheyDid() {
        XCTAssertEqual(DeviceCard.Charge.of(Self.bench), .noneToRead(DuckBattery.noneToRead))
        XCTAssertEqual(DeviceCard.Charge.of(Self.robot),
                       .notReported(DeviceCard.Charge.linkCarriesNoCharge))
    }

    // MARK: - the posture row

    /// The word on the card comes from the state's own fall reading, through
    /// `Doing.word` — one copy of those five strings, as ever.
    func testTheWordComesFromTheStateAndFromDoingsOwnStrings() {
        XCTAssertEqual(DeviceCard.Posture.of(Self.state(fallen: false), running: true).word,
                       DeviceCard.Doing.driving)
        XCTAssertEqual(DeviceCard.Posture.of(Self.state(fallen: false), running: false).word,
                       DeviceCard.Doing.upright)
        XCTAssertEqual(DeviceCard.Posture.of(Self.state(fallen: true), running: true).word,
                       DeviceCard.Doing.onItsSide)
    }

    /// NIL IS NOT `false`, AND THIS IS THE ASSERTION THAT SAYS SO. A duck that
    /// did not report its safety block is "waiting" or "not driving" — never
    /// "upright" — and the missing reading gets its own sentence.
    func testADuckThatDidNotSayWhetherItIsDownIsNotReportedAsStanding() {
        let posture = DeviceCard.Posture.of(Self.state(fallen: nil, limp: nil), running: true)
        XCTAssertNil(posture.fallen)
        XCTAssertEqual(posture.word, DeviceCard.Doing.waitingForTheBench)
        XCTAssertTrue(posture.missing.contains(DeviceCard.Posture.noFallReading))
        XCTAssertTrue(posture.missing.contains(DeviceCard.Posture.noLimpReading))
        XCTAssertNotEqual(posture.word, DeviceCard.Doing.upright)
    }

    /// A full state has nothing missing, which is what makes the missing list
    /// worth reading when it is not empty.
    func testAStateThatSaidEverythingHasNothingMissing() {
        XCTAssertEqual(DeviceCard.Posture.of(Self.state(), running: false).missing, [])
    }

    /// THE SCHEMA CANARY. A line that arrived, parsed, and contained not one
    /// field this build understands is the loudest possible signal that the
    /// daemon moved — and it is completely invisible if the card just draws
    /// blanks.
    func testAStateWithNothingInItSaysSoFirst() {
        let empty = DuckState(receivedAt: Date(timeIntervalSince1970: 1))
        let posture = DeviceCard.Posture.of(empty, running: false)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(posture.missing.first, DeviceCard.Posture.everyFieldWasEmpty)
        XCTAssertEqual(posture.word, DeviceCard.Doing.notDriving)
    }

    /// A BENCH'S SYNTHESISED STATE, READ BY THE CARD, IS MOSTLY ABSENCES — and
    /// that is the honest picture of driving a simulator through a robot's
    /// vocabulary. This is the end-to-end shape: a bench reply becomes a state
    /// becomes a card row.
    func testTheCardReadsABenchesSynthesisedStateAsMostlyAbsences() {
        let live = DuckDrive.Live(t: 2, stance: .home, height: 0.116, upright: true,
                                  policy: "alpha_walking", command: .still)
        let state = BenchPeer.synthesised(from: live, receivedAt: Date(timeIntervalSince1970: 2))
        let reading = DeviceCard.reading(state, from: Self.bench, running: false)
        XCTAssertEqual(reading.posture.word, DeviceCard.Doing.upright)
        XCTAssertEqual(reading.charge, .noneToRead(DuckBattery.noneToRead))
        XCTAssertTrue(reading.posture.missing.contains(DeviceCard.Posture.noLimpReading))
        XCTAssertTrue(reading.posture.missing.contains(DeviceCard.Posture.noLoopReading))
        XCTAssertTrue(reading.posture.missing.contains(DeviceCard.Posture.noOdometry))
        XCTAssertFalse(reading.posture.missing.contains(DeviceCard.Posture.noFallReading))
    }

    /// THE BATTERY IS SAID ONCE PER CARD, NOT TWICE. The charge row already has
    /// its own sentence for a missing battery, so the posture row does not
    /// repeat it in different words on the same screen.
    func testAMissingBatteryIsSaidByTheChargeRowAndNotAlsoByThePostureRow() {
        let reading = DeviceCard.reading(Self.state(), from: Self.robot, running: false)
        XCTAssertEqual(reading.charge, .reportedNothing(DeviceCard.Charge.stateCarriedNoBattery))
        for sentence in reading.posture.missing {
            XCTAssertFalse(sentence.lowercased().contains("battery"), sentence)
        }
    }

    /// Every sentence this file can produce is a distinct one. Two absences
    /// sharing a wording is two absences a person cannot tell apart.
    func testEveryAbsenceHasItsOwnWords() {
        let sentences = [
            DeviceCard.Posture.everyFieldWasEmpty,
            DeviceCard.Posture.noFallReading,
            DeviceCard.Posture.noLimpReading,
            DeviceCard.Posture.noLoopReading,
            DeviceCard.Posture.noOdometry,
            DeviceCard.Posture.noMoveReading,
            DeviceCard.Posture.noPolicyName,
            DeviceCard.Charge.stateCarriedNoBattery,
            DeviceCard.Charge.readingWasNotAPercentage,
            DeviceCard.Charge.linkCarriesNoCharge,
            DuckBattery.noneToRead,
        ]
        XCTAssertEqual(Set(sentences).count, sentences.count)
        for sentence in sentences {
            XCTAssertFalse(sentence.contains("unknown"), sentence)
            XCTAssertGreaterThan(sentence.count, 60, sentence)
        }
    }
}
