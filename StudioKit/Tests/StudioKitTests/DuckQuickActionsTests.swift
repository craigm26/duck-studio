import XCTest
import DuckEvidence
@testable import StudioKit

/// The four chips on the front door, and the two ways they can refuse.
///
/// WHAT THESE TESTS ARE ACTUALLY FOR. The match from a role to a file is the
/// part that used to live privately inside `DriveView`, and it has a fallback
/// in it that only a real bench explains: benches list their policies with and
/// without the `.onnx`, so a matcher that only did exact comparison would find
/// nothing on half the benches on the desk and the grid would be empty with no
/// explanation. The rest is about the refusals: a slot this bench does not
/// fill, and a link that cannot load a policy at all. Both have to produce a
/// chip that says something, because the alternative — omitting them — is the
/// empty card the house rule forbids.
final class DuckQuickActionsTests: XCTestCase {

    private static let benchReach = DuckMethod.reach(for: .bench)

    /// A bench that holds the whole official set, spelled the way `policies/`
    /// spells them.
    private static let everything = DuckOfficialPolicies.releases.map(\.filename)

    // MARK: - matching a role to a file

    func testEveryOfficialSlotIsFoundByItsFilename() {
        for slot in DuckOfficialPolicies.Slot.allCases {
            let wanted = DuckOfficialPolicies.releases.first { $0.slot == slot }?.filename
            XCTAssertEqual(DuckQuickActions.filename(filling: slot, among: Self.everything),
                           wanted, "\(slot) did not match its own release filename")
        }
    }

    /// THE FALLBACK IS THE REASON THIS FUNCTION IS NOT ONE LINE. A bench often
    /// lists its policies without the extension, and a matcher that missed
    /// those would report a fully stocked bench as holding nothing.
    func testAStemMatchesWhenTheExtensionIsMissing() {
        let stems = Self.everything.map { $0.replacingOccurrences(of: ".onnx", with: "") }
        XCTAssertEqual(DuckQuickActions.filename(filling: .walk, among: stems),
                       "alpha_walking")
        XCTAssertEqual(DuckQuickActions.filename(filling: .kickLeft, among: stems),
                       "ball_kick_left")
    }

    /// AN EXACT MATCH WINS OVER A STEM, so a bench holding both spellings loads
    /// the file it named rather than the one this app guessed at.
    func testTheExactSpellingWinsWhenBothArePresent() {
        XCTAssertEqual(
            DuckQuickActions.filename(filling: .walk,
                                      among: ["alpha_walking", "alpha_walking.onnx"]),
            "alpha_walking.onnx")
    }

    /// SOMEBODY ELSE'S NETWORKS FILL NO OFFICIAL SLOT, and saying so beats
    /// loading the wrong one.
    func testAnUnofficialBenchFillsNothing() {
        let mine = ["my_gait_v3.onnx", "experiment_44"]
        for slot in DuckOfficialPolicies.Slot.allCases {
            XCTAssertNil(DuckQuickActions.filename(filling: slot, among: mine))
        }
    }

    func testAnEmptyBenchFillsNothing() {
        XCTAssertNil(DuckQuickActions.filename(filling: .walk, among: []))
    }

    // MARK: - which slots a mode has

    func testWalkModeHasEverySlot() {
        XCTAssertEqual(DuckQuickActions.slots(in: .walk), DuckOfficialPolicies.Slot.allCases)
    }

    /// ROLLER LEAVES STANDING OUT, which is upstream's decision: the roller
    /// preset skips standing transitions on wheels, so a Stand chip would be
    /// offering a network that is not loaded.
    func testRollerModeLeavesStandingOut() {
        let slots = DuckQuickActions.slots(in: .roller)
        XCTAssertFalse(slots.contains(.stand))
        XCTAssertTrue(slots.contains(.walk))
        XCTAssertEqual(slots.count, DuckOfficialPolicies.Slot.allCases.count - 1)
    }

    // MARK: - what a link can do

    func testOnlyABenchCanLoadAPolicy() {
        for transport in DuckTransportKind.allCases {
            let carries = DuckQuickActions.carriesAPolicyLoad(
                transport: transport, reach: DuckMethod.reach(for: transport))
            XCTAssertEqual(carries, transport == .bench,
                           "\(transport) answered the wrong way about loading a policy")
        }
    }

    /// A PEER THAT CANNOT READ STATE CANNOT SHOW THE RESULT OF A SWAP, so it is
    /// not offered one. `DuckPeer` explicitly permits a peer to narrow its
    /// reach, and this is what narrowing costs.
    func testANarrowedBenchCannotLoadEither() {
        XCTAssertFalse(DuckQuickActions.carriesAPolicyLoad(transport: .bench,
                                                           reach: [.hello, .move, .stop]))
    }

    // MARK: - the chips

    func testAStockedBenchOffersTheFirstFourSlotsInOrder() {
        let actions = DuckQuickActions.installed(policies: Self.everything, mode: .walk,
                                                 reach: Self.benchReach, transport: .bench)
        XCTAssertEqual(actions.map(\.slot), [.walk, .stand, .sitstand, .groundPick])
        XCTAssertTrue(actions.allSatisfy(\.runs))
        XCTAssertEqual(actions.first?.effect, .loadsOnABench(filename: "alpha_walking.onnx"))
        XCTAssertEqual(actions.first?.policyFilename, "alpha_walking.onnx")
        XCTAssertNil(actions.first?.reason)
    }

    /// THE TITLE IS DUCKKIT'S WORD AND NOT A SECOND ONE. Two names for the same
    /// role is how a chip ends up saying something the robot's own config does
    /// not.
    func testTitlesAreTheSlotsOwnTitles() {
        let actions = DuckQuickActions.installed(policies: Self.everything, mode: .walk,
                                                 reach: Self.benchReach, transport: .bench)
        for action in actions {
            XCTAssertEqual(action.title, action.slot.title)
        }
    }

    /// A HALF-STOCKED BENCH OFFERS WHAT IT HAS AND NOT A ROW OF DEAD CHIPS.
    func testOnlyTheSlotsThisBenchFillsBecomeChips() {
        let held = ["alpha_walking.onnx", "roulade.onnx"]
        let actions = DuckQuickActions.installed(policies: held, mode: .walk,
                                                 reach: Self.benchReach, transport: .bench)
        XCTAssertEqual(actions.map(\.slot), [.walk, .roulade])
    }

    /// AN EMPTY GRID IS A REAL ANSWER, and the caller draws `noneInstalled` in
    /// its place rather than nothing at all.
    func testAnUnofficialBenchOffersNoChips() {
        let actions = DuckQuickActions.installed(policies: ["my_gait_v3.onnx"], mode: .walk,
                                                 reach: Self.benchReach, transport: .bench)
        XCTAssertTrue(actions.isEmpty)
        XCTAssertFalse(DuckQuickActions.noneInstalled.isEmpty)
    }

    func testTheLimitIsHonoured() {
        let two = DuckQuickActions.installed(policies: Self.everything, mode: .walk,
                                             reach: Self.benchReach, transport: .bench,
                                             limit: 2)
        XCTAssertEqual(two.map(\.slot), [.walk, .stand])
    }

    /// A LIMIT OF ZERO IS AN EMPTY GRID, NOT A CRASH — a caller sizing the grid
    /// from a screen width can reach zero.
    func testANonPositiveLimitIsEmpty() {
        XCTAssertTrue(DuckQuickActions.installed(policies: Self.everything, mode: .walk,
                                                 reach: Self.benchReach, transport: .bench,
                                                 limit: 0).isEmpty)
        XCTAssertTrue(DuckQuickActions.installed(policies: Self.everything, mode: .walk,
                                                 reach: Self.benchReach, transport: .bench,
                                                 limit: -1).isEmpty)
    }

    /// ROLLER MODE'S FIRST FOUR SKIP STANDING, so the fourth chip is one the
    /// walking preset would have had fifth.
    func testRollerModeShiftsTheFourChipsAlong() {
        let actions = DuckQuickActions.installed(policies: Self.everything, mode: .roller,
                                                 reach: Self.benchReach, transport: .bench)
        XCTAssertEqual(actions.map(\.slot), [.walk, .sitstand, .groundPick, .kickLeft])
    }

    // MARK: - the two refusals

    /// A LINK THAT CANNOT LOAD STILL DRAWS CHIPS, and every one of them says
    /// what is missing. Silence would leave somebody holding a paired robot
    /// wondering whether this app has quick actions at all.
    func testBluetoothChipsAreDrawnAndAllRefuse() {
        let actions = DuckQuickActions.installed(policies: Self.everything, mode: .walk,
                                                 reach: DuckMethod.reach(for: .ble),
                                                 transport: .ble)
        XCTAssertEqual(actions.count, 4)
        XCTAssertTrue(actions.allSatisfy { !$0.runs })
        XCTAssertTrue(actions.allSatisfy { $0.policyFilename == nil })
        for action in actions {
            XCTAssertEqual(action.effect,
                           .notCarried(reason: DuckQuickActions.cannotLoadHere(.ble)))
        }
    }

    /// THE REFUSAL NAMES THE LINK, because "this does not work" is a sentence
    /// about the app and "Bluetooth cannot load a policy" is one about the
    /// world.
    func testTheCannotLoadSentenceNamesTheLink() {
        for transport in DuckTransportKind.allCases {
            XCTAssertTrue(DuckQuickActions.cannotLoadHere(transport)
                .contains(transport.label))
        }
    }

    /// `.notOnThisBench` IS REACHABLE, which is the whole reason `action(
    /// filling:)` is public: a case nothing can produce is a sentence nothing
    /// tests.
    func testASlotThisBenchDoesNotHoldRefusesByName() {
        let action = DuckQuickActions.action(filling: .roulade,
                                             among: ["alpha_walking.onnx"],
                                             reach: Self.benchReach, transport: .bench)
        XCTAssertFalse(action.runs)
        XCTAssertNil(action.policyFilename)
        XCTAssertEqual(action.effect,
                       .notOnThisBench(reason: DuckQuickActions.notHeldHere(.roulade)))
        XCTAssertEqual(action.reason, DuckQuickActions.notHeldHere(.roulade))
        XCTAssertTrue(action.reason?.contains("roulade") == true, action.reason ?? "")
    }

    /// NOT AN ACCUSATION. A bench carrying somebody's own networks is a
    /// legitimate bench, and the sentence says so.
    func testTheNotHeldSentenceIsNotAnAccusation() {
        XCTAssertTrue(DuckQuickActions.notHeldHere(.walk).contains("not a fault"))
    }

    /// EVERY SLOT HAS A SENTENCE, so a slot added upstream cannot arrive with
    /// an empty chip.
    func testEverySlotCanRefuseInWords() {
        for slot in DuckOfficialPolicies.Slot.allCases {
            XCTAssertFalse(DuckQuickActions.notHeldHere(slot).isEmpty)
            XCTAssertFalse(slot.title.isEmpty)
        }
    }

    /// AN ACTION'S IDENTITY IS ITS SLOT, so a grid never draws one role twice.
    func testChipIdentitiesAreUnique() {
        let actions = DuckQuickActions.installed(policies: Self.everything, mode: .walk,
                                                 reach: Self.benchReach, transport: .bench)
        XCTAssertEqual(Set(actions.map(\.id)).count, actions.count)
    }
}
