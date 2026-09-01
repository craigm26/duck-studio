import XCTest
import DuckEvidence
@testable import StudioKit

/// A sim duck, pinned against the real duck it is described in the terms of.
///
/// THE TESTS THAT MATTER HERE ARE THE ONES THAT PROVE A NEGATIVE. Half of this
/// file checks that `robotdToml()` really does render `deploy/robotd.toml`'s
/// own keys, because the claim that customising a sim duck is customising a
/// real one is worthless the moment the rendering drifts. The other half checks
/// three things a simulation must never say — a battery percentage, a camera
/// frame, a number that could be mistaken for a hardware one — and each of
/// those is checked at the type rather than at a call site, because a rule that
/// only holds where somebody remembered to call the checker is not a rule.
final class SimDuckTests: XCTestCase {

    // MARK: - the config IS the robot's config

    /// The seven slots, each filled with the role filename `policies/` ships.
    ///
    /// THE FILENAMES ARE NOT TYPED FROM MEMORY ANYWHERE IN THE SOURCE — the
    /// preset is built from `DuckOfficialPolicies.releases` — so this test is
    /// what pins them, and it pins them literally on purpose. If Pollen rename
    /// a release, this test fails and somebody reads the rename rather than
    /// shipping a config naming a file that is not there.
    func testTheStockConfigRendersEverySlotWithItsRoleFilename() {
        let toml = SimDuckConfig.stock().robotdToml()
        XCTAssertTrue(toml.contains("walk = \"alpha_walking.onnx\""), toml)
        XCTAssertTrue(toml.contains("stand = \"alpha_stand.onnx\""), toml)
        XCTAssertTrue(toml.contains("sitstand = \"alpha_sitstand.onnx\""), toml)
        XCTAssertTrue(toml.contains("ground_pick = \"alpha_ground_pick.onnx\""), toml)
        XCTAssertTrue(toml.contains("kick_left = \"ball_kick_left.onnx\""), toml)
        XCTAssertTrue(toml.contains("kick_right = \"ball_kick_right.onnx\""), toml)
        XCTAssertTrue(toml.contains("roulade = \"roulade.onnx\""), toml)
    }

    /// The keys are the wire spellings, not the Swift ones. `ground_pick` is
    /// the key `robotd` reads; `groundPick` is a name only this app uses.
    func testTheSlotKeysAreSpelledTheWayRobotdSpellsThem() {
        let toml = SimDuckConfig.stock().robotdToml()
        XCTAssertFalse(toml.contains("groundPick"), toml)
        XCTAssertFalse(toml.contains("kickLeft"), toml)
        for slot in DuckOfficialPolicies.Slot.allCases {
            XCTAssertTrue(toml.contains("\n\(slot.rawValue) = "),
                          "\(slot.rawValue) is missing from the walking preset.\n\(toml)")
        }
    }

    /// `mode` is a key of the `[policy]` table, not a stray at the top of the
    /// file. A mode written above the header would be a different setting.
    func testModeIsTheFirstKeyInsideThePolicyTable() throws {
        let toml = SimDuckConfig.stock().robotdToml()
        let header = try XCTUnwrap(toml.range(of: "[policy]"))
        let mode = try XCTUnwrap(toml.range(of: "mode = \"walk\""))
        XCTAssertTrue(header.upperBound <= mode.lowerBound,
                      "mode must sit under [policy], not above it.\n\(toml)")
    }

    /// The roller preset's three documented facts, and only those three: the
    /// locomotion slot becomes `roller.onnx`, the ground-pick trigger becomes
    /// the crouch, and the standing network is left out — "standing transitions
    /// being skipped on wheels".
    func testRollerModeSwapsTwoSlotsAndDeliberatelyOmitsTheStandingNetwork() {
        let config = SimDuckConfig.stock(mode: .roller)
        XCTAssertEqual(config.slots[.walk], "roller.onnx")
        XCTAssertEqual(config.slots[.groundPick], "roller_crouch.onnx")
        XCTAssertNil(config.slots[.stand])

        let toml = config.robotdToml()
        XCTAssertTrue(toml.contains("mode = \"roller\""), toml)
        XCTAssertTrue(toml.contains("walk = \"roller.onnx\""), toml)
        XCTAssertTrue(toml.contains("ground_pick = \"roller_crouch.onnx\""), toml)
        XCTAssertFalse(toml.contains("\nstand = "),
                       "The roller preset must not name a standing network.\n\(toml)")
    }

    /// EVERY ROLLER RELEASE UPSTREAM SHIPS HAS A PLACEMENT, OR THE PRESET SAYS
    /// SO. What stood here was a `switch` on the filename with a `default:
    /// break`, so a third roller policy would have gone nowhere silently and
    /// left a roller duck holding the walking preset's file in that slot,
    /// looking entirely correct. No `switch` can be made to notice a new row in
    /// another package's table, so the discipline is a named refusal instead:
    /// this asserts the table is complete today, and the test below asserts
    /// that the day it is not, every roller duck says which policy it could not
    /// place.
    func testEveryRollerReleaseHasAPlacementThisAppHasActuallyRead() {
        XCTAssertEqual(SimDuckConfig.unplacedRollerPolicies, [],
                       "Upstream ships a roller policy this app has nowhere to put. Read the "
                     + "[policy] table for roller mode and add it to rollerPlacements — until "
                     + "somebody does, every roller duck carries an advisory saying so.")
        XCTAssertFalse(SimDuckConfig.stock(mode: .roller).advisories
                           .contains { $0.contains("roller policies go") },
                       "\(SimDuckConfig.stock(mode: .roller).advisories)")
    }

    /// The branch that fires on a day that has not come yet, read on a day that
    /// has: the sentence names the policy, says how many placements this build
    /// holds, and warns that the slot still has the walking preset's file in it
    /// — which is the thing somebody comparing two ducks needs to know.
    func testAnUnplacedRollerPolicyIsNamedRatherThanDroppedInSilence() throws {
        XCTAssertNil(SimDuckConfig.unplacedRollerSentence([], placed: 2))
        let one = try XCTUnwrap(
            SimDuckConfig.unplacedRollerSentence(["roller_hop.onnx"], placed: 2))
        XCTAssertTrue(one.contains("roller_hop.onnx"), one)
        XCTAssertTrue(one.contains("is not one of them"), one)
        XCTAssertTrue(one.contains("walking preset's file"), one)
        let two = try XCTUnwrap(
            SimDuckConfig.unplacedRollerSentence(["roller_hop.onnx", "roller_spin.onnx"],
                                                 placed: 2))
        XCTAssertTrue(two.contains("are not among them"), two)
    }

    /// A slot with nothing in it renders as no key at all. A key with an empty
    /// value would be a config telling the robot to load a file called "".
    func testAnEmptySlotIsAnAbsentKey() {
        var config = SimDuckConfig.stock()
        config.slots[.roulade] = nil
        let toml = config.robotdToml()
        XCTAssertFalse(toml.contains("roulade"), toml)
        XCTAssertTrue(toml.contains("kick_right = \"ball_kick_right.onnx\""), toml)
    }

    /// THE SPLIT IS THE HONESTY. Everything under `[policy]` is a key a robot
    /// really has; everything this app invented is under `[studio]`, below it,
    /// with a sentence saying a robot would ignore it. A friction coefficient
    /// sitting in `[policy]` would make the file look copyable onto a duck.
    func testTheSimulatorsOwnKeysAreQuarantinedBelowTheStudioHeader() throws {
        var config = SimDuckConfig.stock()
        config.floorFriction = 0.9
        config.payloadGrams = 40
        config.sceneName = "Kitchen"
        let toml = config.robotdToml()

        let policy = try XCTUnwrap(toml.range(of: "[policy]"))
        let studio = try XCTUnwrap(toml.range(of: "[studio]"))
        XCTAssertTrue(policy.upperBound < studio.lowerBound)

        for ours in ["floor_friction = 0.9", "payload_grams = 40",
                     "scene = \"Kitchen\"", "colourway = \"yellow\""] {
            let found = try XCTUnwrap(toml.range(of: ours), ours)
            XCTAssertTrue(found.lowerBound > studio.lowerBound,
                          "\(ours) is above [studio], where it reads as the robot's.\n\(toml)")
        }
        XCTAssertTrue(toml.contains("a robot would ignore it"), toml)
    }

    /// The two keys this app has read about and holds no value for are named in
    /// a comment rather than invented. A default written here would be this
    /// app's tuning wearing the robot's file format.
    func testTheTuningKeysThisAppHasNoValueForAreLeftOutInWriting() {
        let toml = SimDuckConfig.stock().robotdToml()
        XCTAssertTrue(toml.contains("# action_scale and the low-pass coefficients"), toml)
        XCTAssertFalse(toml.contains("\naction_scale = "),
                       "Writing a value for action_scale would be inventing the robot's tuning.")
    }

    /// Two renders of one config are the same bytes, so a config file can be
    /// diffed. Dictionary order is nobody's; `Slot.allCases` is upstream's.
    func testTheRenderIsStableAcrossRuns() {
        let config = SimDuckConfig.stock()
        XCTAssertEqual(config.robotdToml(), config.robotdToml())
        let keys = DuckOfficialPolicies.Slot.allCases.compactMap { slot -> Int? in
            config.robotdToml().range(of: "\n\(slot.rawValue) = ")
                .map { config.robotdToml().distance(from: config.robotdToml().startIndex,
                                                    to: $0.lowerBound) }
        }
        XCTAssertEqual(keys, keys.sorted(), "Slots must render in upstream's own order.")
    }

    // MARK: - rendering values without lying about them

    /// A name with a quote in it is a name somebody typed, and TOML has an
    /// escape for it. An unescaped one ends the string early and the rest of
    /// the scene name is parsed as syntax.
    func testStringsAreEscapedRatherThanTrusted() {
        var config = SimDuckConfig.stock()
        config.sceneName = "He said \"duck\"\\here"
        let toml = config.robotdToml()
        XCTAssertTrue(toml.contains("scene = \"He said \\\"duck\\\"\\\\here\""), toml)
    }

    /// A comment cannot be escaped, only ended — TOML gives comments no escape
    /// syntax at all — so a newline in the duck's name is folded to a space
    /// rather than allowed to start a line that would parse as a key.
    func testANewlineInTheNameCannotStartALineInTheComment() {
        var config = SimDuckConfig.stock()
        config.name = "Pip\nstand = \"mine.onnx\""
        let toml = config.robotdToml()
        XCTAssertFalse(toml.contains("\nstand = \"mine.onnx\""),
                       "A name broke out of its comment and became a key.\n\(toml)")
        XCTAssertTrue(toml.contains("# Pip stand"), toml)
    }

    /// `payload_grams = 40`, not `40.0000`. What somebody typed is what the
    /// file says.
    func testWholeNumbersRenderAsIntegers() {
        XCTAssertEqual(SimDuckConfig.number(40), "40")
        XCTAssertEqual(SimDuckConfig.number(0.9), "0.9")
        XCTAssertEqual(SimDuckConfig.number(1.25), "1.25")
        XCTAssertEqual(SimDuckConfig.number(-2), "-2")
    }

    /// TOML 1.0 has `nan` and `inf` as float literals, so an absurd value
    /// renders as an absurd value. Dropping the key would produce a file that
    /// reads as if the friction were the default.
    func testANonFiniteValueIsWrittenRatherThanQuietlyDropped() {
        var config = SimDuckConfig.stock()
        config.floorFriction = .nan
        XCTAssertTrue(config.robotdToml().contains("floor_friction = nan"),
                      config.robotdToml())
        config.floorFriction = .infinity
        XCTAssertTrue(config.robotdToml().contains("floor_friction = inf"),
                      config.robotdToml())
    }

    /// Nil and zero are the same physics and different sentences, so they must
    /// not render the same way.
    func testAnAbsentPayloadIsAbsentAndAZeroPayloadIsZero() {
        var config = SimDuckConfig.stock()
        XCTAssertFalse(config.robotdToml().contains("payload_grams"))
        config.payloadGrams = 0
        XCTAssertTrue(config.robotdToml().contains("payload_grams = 0"),
                      config.robotdToml())
    }

    // MARK: - advisories

    /// The range is `Retrieval.Drag.footFriction`, the one training randomises
    /// — `cfg.events["foot_friction"].params["ranges"] = (0.7, 1.3)` — and the
    /// sentence says so, because a duck falling over on a floor no policy has
    /// met is not a duck that found a bug.
    func testAFloorOutsideTheTrainingRangeIsCalledOut() {
        var config = SimDuckConfig.stock()
        config.floorFriction = 0.2
        let said = config.advisories.first ?? ""
        XCTAssertTrue(said.contains("0.7–1.3"), said)
        XCTAssertTrue(said.contains("has not necessarily found a fault"), said)

        config.floorFriction = 1.3
        XCTAssertTrue(config.advisories.isEmpty,
                      "The ends of the range are inside it: \(config.advisories)")
    }

    /// An empty slot is worth a sentence — except the one empty slot that is a
    /// decision, which the roller preset makes on purpose.
    func testTheOnlyUnflaggedEmptySlotIsTheOneTheRollerPresetMeansToLeaveEmpty() {
        // THIS ASSERTED `isEmpty` AND WAS WRONG TO. A roller table always has
        // one thing worth saying — it carries no `action_scale`, where the
        // robot's own preset sets 0.8 — so "no advisories" was a claim that the
        // transcription is complete when it is one field short.
        let rollerStock = SimDuckConfig.stock(mode: .roller).advisories
        XCTAssertEqual(rollerStock.count, 1, "\(rollerStock)")
        XCTAssertTrue(rollerStock[0].contains("action_scale"), rollerStock[0])

        var walking = SimDuckConfig.stock()
        walking.slots[.stand] = nil
        XCTAssertEqual(walking.advisories.count, 1)
        XCTAssertTrue(walking.advisories[0].contains("stand"), walking.advisories[0])

        var rolling = SimDuckConfig.stock(mode: .roller)
        rolling.slots[.roulade] = nil
        XCTAssertEqual(rolling.advisories.count, 2, "\(rolling.advisories)")
        XCTAssertTrue(rolling.advisories.contains { $0.contains("roulade") },
                      "\(rolling.advisories)")
    }

    /// A payload that is not a number gets the same sentence friction does.
    func testANonsensePayloadIsFlaggedTheWayNonsenseFrictionIs() {
        var config = SimDuckConfig.stock()
        config.payloadGrams = .nan
        XCTAssertTrue(config.advisories.contains { $0.contains("not a number of grams") },
                      "\(config.advisories)")
        config.payloadGrams = -5
        XCTAssertTrue(config.advisories.contains { $0.contains("negative mass") },
                      "\(config.advisories)")
    }

    /// A formatter must not put a minus sign on nothing, nor round a real value
    /// away to zero — the same failure `Choreography.ms` had.
    func testASmallNegativeIsNeitherMinusZeroNorZero() {
        XCTAssertEqual(SimDuckConfig.number(-0.00001), "-0.0001")
        XCTAssertEqual(SimDuckConfig.number(0.00001), "0.0001")
        XCTAssertEqual(SimDuckConfig.number(0), "0")
    }

    /// The duck's own mass is `Retrieval.Drag.duckMass`, summed from every
    /// `<inertial>` in `pollen_robot.xml`. A payload heavier than that is not
    /// refused — somebody may well want to see what happens — but nothing in
    /// this app has measured a duck carrying anything at all, and the sentence
    /// says that rather than implying a result.
    func testAPayloadHeavierThanTheDuckSaysSoAndCitesTheDucksOwnMass() {
        var config = SimDuckConfig.stock()
        config.payloadGrams = 900
        let said = try? XCTUnwrap(config.advisories.first)
        XCTAssertTrue(said?.contains("737.2 g") ?? false, "\(config.advisories)")

        config.payloadGrams = 40
        XCTAssertTrue(config.advisories.isEmpty, "\(config.advisories)")
    }

    // MARK: - persistence

    /// A config that has been saved and reopened is the same config, sparse
    /// slots and absent payload included.
    func testAConfigRoundTripsThroughItsSavedForm() throws {
        var config = SimDuckConfig.stock(mode: .roller)
        config.name = "Pip"
        config.colourway = .teal
        config.floorFriction = 0.85
        config.sceneName = "Kitchen"
        let data = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(SimDuckConfig.self, from: data), config)

        config.payloadGrams = 40
        let laden = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(SimDuckConfig.self, from: laden), config)
    }

    /// The saved slots are an object keyed by the same words the TOML uses, not
    /// the alternating array Swift emits for a dictionary whose key it cannot
    /// use as a string. Somebody who opens the file after reading the TOML
    /// should recognise it.
    func testTheSavedSlotsAreKeyedByTheSameWordsTheTOMLUses() throws {
        let data = try JSONEncoder().encode(SimDuckConfig.stock())
        let top = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let slots = try XCTUnwrap(top["slots"] as? [String: String])
        XCTAssertEqual(slots["ground_pick"], "alpha_ground_pick.onnx")
        XCTAssertEqual(slots["walk"], "alpha_walking.onnx")
        XCTAssertNotNil(top["floor_friction"])
    }

    /// A file from a newer build carrying a slot this one has never heard of
    /// still opens. Refusing it would strand somebody's config on the version
    /// of the app that wrote it.
    func testASlotThisBuildDoesNotKnowIsDroppedRatherThanRefused() throws {
        let json = """
        {"name":"Pip","slots":{"walk":"alpha_walking.onnx","backflip":"someday.onnx"}}
        """
        let config = try JSONDecoder().decode(SimDuckConfig.self,
                                              from: Data(json.utf8))
        XCTAssertEqual(config.name, "Pip")
        XCTAssertEqual(config.slots, [.walk: "alpha_walking.onnx"])
        // And everything the older file did not carry has its default.
        XCTAssertEqual(config.mode, .walk)
        XCTAssertEqual(config.colourway, .yellow)
        XCTAssertEqual(config.floorFriction, SimDuckConfig.defaultFriction)
        XCTAssertNil(config.sceneName)
    }

    // MARK: - the battery there is none of

    /// THE RULE IS THE TYPE'S, NOT THE CALLER'S. `DuckBattery` cannot be
    /// constructed for a duck that is not `.real`, so no amount of care or
    /// carelessness anywhere else in the app produces a percentage next to a
    /// simulated duck.
    func testABatteryCannotBeBuiltForASimulatedDuckAtAll() {
        let sim = DuckIdentity(name: "Pip", kind: .sim)
        let real = DuckIdentity(name: "Pip", kind: .real)
        XCTAssertNil(DuckBattery(percent: 100, of: sim))
        XCTAssertNil(DuckBattery(percent: 0, of: sim))
        XCTAssertNil(DuckBattery(percent: 47, of: sim))
        XCTAssertEqual(DuckBattery(percent: 47, of: real)?.percent, 47)
    }

    /// 104% is as invented as a simulator's battery, and it is refused rather
    /// than clamped: clamping turns a wrong number into a plausible one.
    func testAPercentageOutsideAPercentageIsRefusedRatherThanClamped() {
        let real = DuckIdentity(name: "Pip", kind: .real)
        XCTAssertNil(DuckBattery(percent: 101, of: real))
        XCTAssertNil(DuckBattery(percent: -1, of: real))
        XCTAssertEqual(DuckBattery(percent: 100, of: real)?.percent, 100)
    }

    /// The peer asks for the best possible reading and gets nothing back, so
    /// the nil is the type's answer rather than a `return nil` a later edit
    /// could replace with a number.
    func testASimDuckHasNoBatteryAndNoPlaceToPutOne() {
        let duck = SimDuck(config: .stock(), over: .bridge) { _ in nil }
        XCTAssertNil(duck.battery)
        XCTAssertEqual(duck.identity.kind, .sim)

        // Nothing stored on the peer could hold a percentage: the mirror can
        // see `config`, which proves it is looking, and sees no battery.
        let children = Mirror(reflecting: duck).children.compactMap(\.label)
        XCTAssertTrue(children.contains("config"), "\(children)")
        XCTAssertFalse(children.contains(where: { $0.lowercased().contains("battery") }),
                       "\(children)")
        XCTAssertFalse(children.contains(where: { $0.lowercased().contains("percent") }),
                       "\(children)")
    }

    /// The sentence a battery row shows instead is a sentence, not a dash: a
    /// dash reads as a reading that failed to arrive and invites a reconnect
    /// that would do nothing.
    func testTheNoBatterySentenceExplainsRatherThanShowingADash() {
        XCTAssertFalse(DuckBattery.noneToRead.contains("—"))
        XCTAssertTrue(DuckBattery.noneToRead.contains("physics on another machine"))
    }

    // MARK: - the camera it does not render

    /// One case, and it means "no image". There is no case that means "here is
    /// a picture", so a screen cannot be handed one.
    func testThereIsNoCaseThatMeansAFrameArrived() {
        XCTAssertEqual(SimVision.allCases, [.noImage])
        XCTAssertEqual(SimVision.allCases.count, 1,
                       "A case was added. That may be right — but every switch over SimVision "
                     + "was written while there was only one, and each needs reading again.")
        let duck = SimDuck(config: .stock(), over: .bridge) { _ in nil }
        XCTAssertEqual(duck.vision, .noImage)
    }

    /// And the sentence says what is actually true: there is nothing to show
    /// and nothing being waited for.
    func testTheNoCameraSentenceDoesNotSoundLikeALoadingState() {
        XCTAssertTrue(SimVision.noImage.says.contains("none is being waited for"),
                      SimVision.noImage.says)
    }

    // MARK: - numbers that cannot lose their provenance

    /// Every number a sim duck produces carries the configuration that produced
    /// it, because `measured` is the only way to get one out of a sim duck and
    /// it stamps every one.
    func testEveryNumberASimDuckProducesSaysItIsSimulated() {
        var config = SimDuckConfig.stock()
        config.name = "Pip"
        config.sceneName = "Kitchen"
        config.floorFriction = 0.9
        let duck = SimDuck(config: config, over: .bridge) { _ in nil }
        let walked = duck.measured("distance walked in six seconds", 0.681, in: .metres)

        XCTAssertEqual(walked.value, 0.681)
        XCTAssertTrue(walked.provenance.contains("not on a robot"), walked.provenance)
        XCTAssertTrue(walked.provenance.contains("Pip"), walked.provenance)
        XCTAssertTrue(walked.provenance.contains("floor friction 0.9"), walked.provenance)
        XCTAssertTrue(walked.provenance.contains("Kitchen"), walked.provenance)
        XCTAssertTrue(walked.says.contains("0.681 m"), walked.says)
        XCTAssertTrue(walked.says.contains(walked.provenance), walked.says)
    }

    /// A hardware number says which robot, so the two are never a matter of
    /// which panel they were drawn in.
    func testAHardwareNumberNamesTheRobot() throws {
        let measured = try XCTUnwrap(
            DuckMeasurement.hardware("distance walked in six seconds", 0.59, in: .metres,
                                     onboard: DuckIdentity(name: "Pip", kind: .real)))
        XCTAssertTrue(measured.provenance.contains("a real Microduck"), measured.provenance)
        XCTAssertTrue(measured.provenance.contains("Pip"), measured.provenance)
    }

    /// THE OTHER HALF OF THE PROVENANCE RULE, which used to be missing.
    /// `hardware(...)` took the robot's name as a string, so a view or a
    /// fixture holding a bench figure could stamp "a real Microduck" onto it
    /// and nothing downstream could tell. It now takes the identity of the duck
    /// the number came off, and refuses a simulated one — the same enforcement
    /// `DuckBattery` does from the other end, so both halves of the claim are
    /// now in the type rather than one of them in a habit.
    func testASimulatedIdentityCannotBeStampedOntoAHardwareNumber() {
        let sim = DuckIdentity(name: "Pip", kind: .sim)
        XCTAssertNil(DuckMeasurement.hardware("distance walked in six seconds", 0.59,
                                              in: .metres, onboard: sim))
        // And the peer this app can actually build is one of those, so there is
        // no sim duck anywhere whose numbers could be laundered this way.
        let duck = SimDuck(config: .stock(), over: .bridge) { _ in nil }
        XCTAssertNil(DuckMeasurement.hardware("distance", 0.59, in: .metres,
                                              onboard: duck.identity))
    }

    /// The check is in the payload the `Source` carries, not only in the
    /// factory, so `Source.hardware(...)` cannot be written with a name either:
    /// the only way to make its payload is to show a real duck's identity.
    func testTheHardwareSourceCannotBeBuiltWithoutARealIdentity() {
        XCTAssertNil(DuckMeasurement.Robot(DuckIdentity(name: "Pip", kind: .sim)))
        let robot = DuckMeasurement.Robot(DuckIdentity(name: "Pip", kind: .real))
        XCTAssertEqual(robot?.name, "Pip")
    }

    /// THE COMPARISON THIS FILE EXISTS TO REFUSE. Subtracting a robot's metre
    /// from a simulator's metre produces a number that reads as "the robot is
    /// worse" and actually measures the gap between a rigid-body approximation
    /// and a floor.
    func testASimulatedNumberAndAHardwareNumberAreNotComparable() throws {
        let sim = DuckMeasurement.simulated("distance walked in six seconds", 0.681,
                                            in: .metres, under: .stock())
        let real = try XCTUnwrap(
            DuckMeasurement.hardware("distance walked in six seconds", 0.59, in: .metres,
                                     onboard: DuckIdentity(name: "Pip", kind: .real)))
        for pair in [(sim, real), (real, sim)] {
            guard case .notComparable(let why) = DuckMeasurement.compare(pair.0, pair.1) else {
                return XCTFail("A sim number was compared with a hardware one.")
            }
            XCTAssertTrue(why.contains("physics on a machine and a duck on a floor"), why)
        }
    }

    /// The ordinary mistakes are refused in the same voice, so that no refusal
    /// here looks like a special case bolted on.
    func testDifferentUnitsAndDifferentQuantitiesAreAlsoRefused() {
        let metres = DuckMeasurement.simulated("distance", 0.681, in: .metres, under: .stock())
        let speed = DuckMeasurement.simulated("distance", 0.3, in: .metresPerSecond,
                                              under: .stock())
        guard case .notComparable(let units) = DuckMeasurement.compare(metres, speed) else {
            return XCTFail("Metres were compared with metres per second.")
        }
        XCTAssertTrue(units.contains("no units at all"), units)

        let other = DuckMeasurement.simulated("height reached", 0.184, in: .metres,
                                              under: .stock())
        guard case .notComparable(let quantity) = DuckMeasurement.compare(metres, other) else {
            return XCTFail("Two different quantities were compared.")
        }
        XCTAssertTrue(quantity.contains("not the same as measuring the same thing"), quantity)
    }

    /// Two numbers from the same world do compare, and the sentence is in the
    /// direction a person reads it.
    func testTwoSimulatedNumbersCompareAndSayWhichWayRound() {
        let before = DuckMeasurement.simulated("distance", 0.681, in: .metres, under: .stock())
        let after = DuckMeasurement.simulated("distance", 0.581, in: .metres, under: .stock())
        guard case .difference(let delta, let says) = DuckMeasurement.compare(before, after) else {
            return XCTFail("Two simulated metres should compare.")
        }
        XCTAssertEqual(delta, -0.1, accuracy: 1e-9)
        XCTAssertTrue(says.contains("less than before"), says)
        XCTAssertFalse(says.contains("not under the same configuration"), says)
    }

    /// Same world, different duck: the comparison still stands, and it says
    /// that the difference includes whatever was changed between the two runs.
    func testComparingTwoDifferentSimConfigurationsSaysTheConfigurationChanged() {
        var slippery = SimDuckConfig.stock()
        slippery.floorFriction = 0.7
        let grippy = DuckMeasurement.simulated("distance", 0.681, in: .metres, under: .stock())
        let slid = DuckMeasurement.simulated("distance", 0.4, in: .metres, under: slippery)
        guard case .difference(_, let says) = DuckMeasurement.compare(grippy, slid) else {
            return XCTFail("Two simulated metres should compare.")
        }
        XCTAssertTrue(says.contains("not under the same configuration"), says)
    }

    // MARK: - the peer

    /// A sim duck's reach is the transport's, exactly — never wider for being
    /// ours. `DuckPeer` says a peer may narrow and must not widen.
    func testTheReachIsTheTransportsAndNotAByteWider() {
        for line in SimDuck.LineTransport.allCases {
            let duck = SimDuck(config: .stock(), over: line) { _ in nil }
            XCTAssertEqual(duck.reach, DuckMethod.reach(for: line.kind), line.rawValue)
            XCTAssertTrue(duck.reach.allSatisfy { !$0.mutatesTheRecoveryPath },
                          "A simulator reached the pairing PIN or the updater over \(line).")
        }
    }

    // MARK: - the transport it cannot serve

    /// THE FINDING THIS SECTION EXISTS FOR. This peer writes
    /// `DuckCall.line(id:)` — an NDJSON JSON-RPC object — and `duckbench.mjs`
    /// reads `POST /intent {vx, vy, vyaw, hold}`. Handing one to the other
    /// yields a body with no velocities in it, which is a zero twist: a duck
    /// standing still while the app says it is walking, with nothing thrown.
    /// The transport parameter's type is what prevents it, so what this test
    /// can assert is that the type has no way to say "bench" — the wiring
    /// itself is a compile error and cannot be written here at all.
    func testABenchIsNotSomethingThisPeerCanBePutOn() {
        XCTAssertNil(SimDuck.LineTransport(.bench))
        XCTAssertFalse(SimDuck.LineTransport.allCases.contains { $0.kind == .bench })
        for line in SimDuck.LineTransport.allCases {
            XCTAssertEqual(SimDuck.LineTransport(line.kind), line)
        }
    }

    /// Every transport has been decided about, and every refusal comes with the
    /// sentence a screen has to show instead of a dead control.
    func testEveryTransportIsEitherCarriedOrRefusedInWords() {
        for kind in DuckTransportKind.allCases {
            if let line = SimDuck.LineTransport(kind) {
                XCTAssertNil(SimDuck.LineTransport.whyNot(kind), kind.rawValue)
                XCTAssertEqual(line.kind, kind)
            } else {
                XCTAssertNotNil(SimDuck.LineTransport.whyNot(kind),
                                "\(kind.rawValue) is refused with no reason given.")
            }
        }
        XCTAssertEqual(Set(DuckTransportKind.allCases.filter { SimDuck.LineTransport($0) != nil }),
                       [.webRTC, .bridge])
    }

    /// The bench refusal names the type that does speak to a bench, rather than
    /// leaving somebody to find `BenchPeer` themselves, and it names the
    /// failure the old wiring produced.
    func testTheBenchRefusalNamesTheAdapterAndTheFailureItPrevents() {
        let said = SimDuck.LineTransport.benchIsNotALine
        XCTAssertTrue(said.contains("BenchPeer"), said)
        XCTAssertTrue(said.contains("zero twist"), said)
    }

    /// Bluetooth is refused for the other reason: it carries these lines and
    /// carries them to something physical. Reach over BLE is `hello` plus the
    /// pairing PIN and the updater, so a sim duck there would advertise a way
    /// back into a duck that cannot be locked out of anything.
    func testBluetoothIsRefusedBecauseItsReachIsTheRecoveryPath() {
        XCTAssertNil(SimDuck.LineTransport(.ble))
        let said = SimDuck.LineTransport.bluetoothIsABondWithSomethingPhysical
        XCTAssertTrue(said.contains("recovery path"), said)
        XCTAssertTrue(DuckMethod.reach(for: .ble).contains { $0.mutatesTheRecoveryPath },
                      "The refusal's reason has stopped being true of the reach table.")
        for line in SimDuck.LineTransport.allCases {
            XCTAssertFalse(DuckMethod.reach(for: line.kind).contains { $0.mutatesTheRecoveryPath },
                           "A sim duck over \(line.rawValue) advertises the recovery path.")
        }
    }

    /// There is no initialiser parameter for the kind, so a sim duck cannot be
    /// introduced as a robot on any screen.
    func testASimDuckIsAlwaysIntroducedAsSimulated() {
        var config = SimDuckConfig.stock()
        config.name = "Pip"
        config.colourway = .coral
        let duck = SimDuck(config: config, over: .bridge)  { _ in nil }
        XCTAssertEqual(duck.identity.kind, .sim)
        XCTAssertEqual(duck.identity.name, "Pip")
        XCTAssertEqual(duck.identity.colourway, .coral)
        XCTAssertTrue(duck.identity.says.contains("simulated"), duck.identity.says)
    }

    /// A request goes out with an id, and the ids advance so two answers cannot
    /// be read as each other's.
    func testEachAnsweredCallTakesTheNextID() async throws {
        let sent = Recorder()
        let duck = SimDuck(config: .stock(), over: .bridge) { line in
            await sent.add(line)
            let id = (try? JSONSerialization.jsonObject(with: line) as? [String: Any])?["id"]
            return Data("{\"jsonrpc\":\"2.0\",\"id\":\(id as? Int ?? 0),\"result\":true}".utf8)
        }
        _ = try await duck.call(.stop)
        _ = try await duck.call(.stop)
        let ids = await sent.ids()
        XCTAssertEqual(ids, [1, 2])
    }

    /// A notification carries no id, which `DuckCall` enforces and this proves
    /// travels all the way out of the peer.
    func testANotificationGoesOutWithNoIDMember() async throws {
        let sent = Recorder()
        let duck = SimDuck(config: .stock(), over: .bridge) { line in
            await sent.add(line)
            return nil
        }
        try await duck.notify(.move(.still))
        let first = await sent.lines.first
        let body = try XCTUnwrap(first)
        let top = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(top["method"] as? String, "robot.move")
        XCTAssertNil(top["id"])
    }

    /// A notification carried no id, so nothing that comes back can be an
    /// answer to it. Bytes are therefore dropped rather than treated as a
    /// fault: a carrier that acknowledges every write is a carrier, not a duck
    /// breaking the contract.
    func testAReplyToANotificationIsDroppedRatherThanRefused() async throws {
        let duck = SimDuck(config: .stock(), over: .bridge) { _ in Data("{\"result\":true}".utf8) }
        try await duck.notify(.move(.still))
    }

    /// The reach check is inherited from `DuckPeer.vet`, so it is the same
    /// check every other transport gets, and it is the routing table that
    /// decides rather than this type's opinion of it. WebRTC does not carry
    /// `studio.state` — that method is ours and `robotd` never offered a way to
    /// ask — so a sim duck over WebRTC is refused it by name rather than left
    /// writing a line nothing answers.
    func testASimDuckIsHeldToItsTransportsTableRatherThanToItsOwnWishes() async {
        let duck = SimDuck(config: .stock(), over: .webRTC) { _ in nil }
        do {
            _ = try await duck.call(.state)
            XCTFail("WebRTC does not carry studio.state.")
        } catch {
            XCTAssertEqual(error as? DuckCall.Misuse, .outOfReach(.state, .webRTC))
        }
    }

    /// And the direction check too: a twist asked as a question is a caller
    /// waiting for a reply the contract says never comes.
    func testACallIsRefusedForAContinuousIntent() async {
        let duck = SimDuck(config: .stock(), over: .bridge) { _ in nil }
        do {
            _ = try await duck.call(.move(.still))
            XCTFail("robot.move is a notification.")
        } catch {
            XCTAssertEqual(error as? DuckCall.Misuse, .wrongDirection(.move))
        }
        do {
            try await duck.notify(.stop)
            XCTFail("robot.stop is answered.")
        } catch {
            XCTAssertEqual(error as? DuckCall.Misuse, .wrongDirection(.stop))
        }
    }

    /// Silence in answer to a question is the link failing, and it says so
    /// rather than looking like a duck that declined.
    func testAnAnsweredCallThatGetsNothingBackSaysTheLinkFailed() async {
        let duck = SimDuck(config: .stock(), over: .bridge) { _ in nil }
        do {
            _ = try await duck.call(.stop)
            XCTFail("Silence should not read as a reply.")
        } catch {
            XCTAssertEqual(error as? DuckLink.LinkError,
                           .unexpected("robot.stop was asked and nothing came back. It is a "
                                     + "call that is answered, so silence is the link failing "
                                     + "rather than the duck declining."))
        }
    }

    /// An answer to somebody else's question is worse than no answer, because
    /// it would be read as this one's.
    func testAnAnswerCarryingSomebodyElsesIDIsRefused() async {
        let duck = SimDuck(config: .stock(), over: .bridge) { _ in
            Data("{\"jsonrpc\":\"2.0\",\"id\":99,\"result\":true}".utf8)
        }
        do {
            _ = try await duck.call(.stop)
            XCTFail("An id mismatch must not pass.")
        } catch {
            guard case .unexpected(let why)? = error as? DuckLink.LinkError else {
                return XCTFail("\(error)")
            }
            XCTAssertTrue(why.contains("got the answer to 99"), why)
        }
    }

    /// A refusal from the far end is carried rather than thrown: "the duck
    /// refused" and "the link broke" are the whole diagnosis, and `DuckReply`
    /// keeps them apart.
    func testARefusalComesBackAsAnAnswerRatherThanAsAThrow() async throws {
        let duck = SimDuck(config: .stock(), over: .bridge) { _ in
            Data("""
            {"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"no such method"}}
            """.utf8)
        }
        let reply = try await duck.call(.stop)
        XCTAssertFalse(reply.succeeded)
        XCTAssertEqual(reply.failure?.code, -32601)
    }
}

/// What the wire was handed, gathered where a test can read it.
///
/// AN ACTOR BECAUSE THE CLOSURE IS `@Sendable` AND IS CALLED FROM THE PEER'S
/// OWN ISOLATION. An array captured directly would be a data race the compiler
/// is right to refuse, and a lock here would be more machinery than the two
/// lines it is guarding.
private actor Recorder {
    var lines: [Data] = []

    func add(_ line: Data) { lines.append(line) }

    func ids() -> [Int] {
        lines.compactMap {
            (try? JSONSerialization.jsonObject(with: $0) as? [String: Any])?["id"] as? Int
        }
    }
}
