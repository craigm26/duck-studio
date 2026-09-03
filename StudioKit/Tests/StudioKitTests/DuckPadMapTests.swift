import XCTest
import DuckKit
import DuckEvidence
@testable import StudioKit

/// The pad as a map rather than a gate.
///
/// THE ASSERTIONS THAT MATTER ARE THE ONES ABOUT WHAT IS NOT SENT. A map
/// settles against a bench in memory and posts nothing; the one name it ever
/// offers up comes out of `toPost`, and `toPost` withholds it when the store
/// already says that network is loaded — which is the connect-undoes-a-quick-
/// action bug, testable on Linux for the first time because the decision left
/// the picker's `onChange`.
final class DuckPadMapTests: XCTestCase {

    private let benchWithWalk = ["alpha_walking.onnx", "alpha_ground_pick.onnx"]
    private let benchWithoutWalk = ["mine.onnx"]

    // MARK: - the sticks are never a blocked surface

    func testAFreshMapDrivesTheWalkSlotSoDriveNeverWaitsForAPick() {
        let map = DuckPadMap.defaults(in: .walk)
        XCTAssertEqual(map.locomotion, .slot(.walk))
        XCTAssertEqual(map.locomotionFilename(among: benchWithWalk), "alpha_walking.onnx")
    }

    /// A bench often lists its policies without the extension, and
    /// `DuckQuickActions.filename(filling:among:)` is the one matcher that
    /// knows it.
    func testTheWithoutExtensionBenchStillResolves() {
        let map = DuckPadMap.defaults(in: .walk)
        XCTAssertEqual(map.locomotionFilename(among: ["alpha_walking"]), "alpha_walking")
    }

    func testABenchWithNoWalkNetworkPostsNothingAndDrivesAnyway() {
        let map = DuckPadMap.defaults(in: .walk)
        XCTAssertNil(map.toPost(among: benchWithoutWalk, lastLoaded: nil))
        // STRING IDENTITY, NOT SIMILARITY. The front door says this about the
        // same missing file; a second wording would be two answers to one
        // question.
        XCTAssertEqual(map.locomotionRefusal(among: benchWithoutWalk),
                       DuckQuickActions.notHeldHere(.walk))
    }

    func testNothingIsPostedForAPolicyTheStoreSaysIsAlreadyLoaded() {
        let map = DuckPadMap.defaults(in: .walk)
        XCTAssertNil(map.toPost(among: benchWithWalk, lastLoaded: "alpha_walking.onnx"))
        XCTAssertEqual(map.toPost(among: benchWithWalk, lastLoaded: "something_else.onnx"),
                       "alpha_walking.onnx")
    }

    // MARK: - settling against a bench

    func testAMappedNetworkThisBenchDoesNotHoldDegradesAndSaysSo() {
        var map = DuckPadMap.defaults(in: .walk)
        map.steer(.named("gone.onnx"))
        let said = map.settle(against: ["a.onnx"])
        XCTAssertEqual(said, [DuckPadMap.staleNetwork("gone.onnx")])
        XCTAssertEqual(map.locomotion, .whateverIsLoaded)
        XCTAssertNil(map.toPost(among: ["a.onnx"], lastLoaded: nil),
                     "and a degraded map asks for nothing at all")
    }

    func testSettlingIsIdempotentAndSendsNothing() {
        var map = DuckPadMap.defaults(in: .walk)
        map.steer(.named("gone.onnx"))
        map.bind(.stop, to: .y)
        _ = map.settle(against: ["a.onnx"])
        let before = map
        XCTAssertEqual(map.settle(against: ["a.onnx"]), [])
        XCTAssertEqual(map, before, "settling a settled map changes nothing")
        XCTAssertEqual(map.buttons[.y], .stop, "and never touches the buttons")
    }

    func testARollerBenchGetsTheWalkingMapAndTheAssumptionIsWrittenDown() {
        XCTAssertEqual(DuckPadMap.defaults(in: .roller).buttons[.dpadDown],
                       .loadSlot(.sitstand))
        XCTAssertTrue(DuckPadMap.modeIsAnAssumption.contains("/health"),
                      "the assumption names the endpoint that would settle it")
    }

    // MARK: - the readout

    func testTheReadoutPrefersTheBenchsWordOverTheMapping() {
        let line = DuckPadMap.drivingLine(mapped: "a.onnx", benchSaid: "b.onnx")
        XCTAssertTrue(line.contains("b.onnx"))
        XCTAssertFalse(line.contains("a.onnx"), "a measurement beats a mapping: \(line)")
    }

    func testTheReadoutNeverSaysNoPolicyLoaded() {
        for line in [DuckPadMap.drivingLine(mapped: nil, benchSaid: nil),
                     DuckPadMap.drivingLine(mapped: "a.onnx", benchSaid: nil),
                     DuckPadMap.drivingLine(mapped: "a.onnx", benchSaid: "b.onnx")] {
            XCTAssertFalse(line.contains("no policy loaded"), line)
            XCTAssertFalse(line.isEmpty)
        }
    }

    // MARK: - the shipped table is the default, not a rival

    /// EXHAUSTIVE, NOT SUBSTRING. The switch below has to cover every case of
    /// `DuckPad.Effect`, so a sixth case added upstream fails here rather than
    /// falling quietly into a default.
    func testAnUnmappedControlKeepsTheShippedBinding() throws {
        let bare = DuckPadMap(locomotion: .whateverIsLoaded, buttons: [:])
        for control in DuckPad.Control.allCases {
            let shipped = try XCTUnwrap(DuckPad.binding(for: control)).here
            switch shipped {
            case .loadSlot(let slot):
                XCTAssertEqual(bare.effect(for: control), .loadSlot(slot), "\(control)")
            case .drive:
                XCTAssertEqual(bare.effect(for: control), .drive, "\(control)")
            case .stop:
                XCTAssertEqual(bare.effect(for: control), .stop, "\(control)")
            case .reset:
                XCTAssertEqual(bare.effect(for: control), .reset, "\(control)")
            case .unsupported(let why):
                XCTAssertEqual(bare.effect(for: control), .notYet(why), "\(control)")
            }
        }
    }

    func testEveryControlResolvesToSomethingWithASentence() {
        let map = DuckPadMap.defaults(in: .walk)
        XCTAssertEqual(DuckPad.Control.allCases.count, 16)
        for control in DuckPad.Control.allCases {
            let shown = map.shown(for: control, naming: { _ in nil })
            XCTAssertFalse(shown.onTheRobot.isEmpty, "\(control) has no robot words")
            XCTAssertFalse(shown.caption.isEmpty, "\(control) has no caption")
            XCTAssertFalse(shown.detail.isEmpty, "\(control) has no detail")
        }
    }

    func testAMappedControlKeepsPaddsWordsForWhatTheRobotDoes() throws {
        var map = DuckPadMap.defaults(in: .walk)
        map.bind(.stop, to: .a)
        let shown = map.shown(for: .a, naming: { _ in nil })
        XCTAssertEqual(shown.onTheRobot, try XCTUnwrap(DuckPad.binding(for: .a)).onTheRobot)
        XCTAssertEqual(shown.caption, "Stop")
        XCTAssertTrue(shown.isCustom, "and it is marked as the person's choice")
    }

    func testFourteenControlsAreRemappableAndTheSticksAreNot() {
        XCTAssertEqual(DuckPadMap.remappable.count, 14)
        XCTAssertFalse(DuckPadMap.remappable.contains(.leftStick))
        XCTAssertFalse(DuckPadMap.remappable.contains(.rightStick))
        // The seven `padd` binds that a bench cannot do are still buttons a
        // person may put a sequence on: binding one asks nothing of the bench.
        for control in [DuckPad.Control.y, .b, .leftTrigger, .rightTrigger,
                        .start, .dpadUp, .select] {
            XCTAssertTrue(DuckPadMap.remappable.contains(control), "\(control)")
        }
        var map = DuckPadMap.defaults(in: .walk)
        map.bind(.stop, to: .leftStick)
        XCTAssertNil(map.buttons[.leftStick], "a stick cannot be remapped")
    }

    // MARK: - a dead binding says so

    func testABoundSequenceThatIsGoneSaysSoRatherThanVanishing() {
        var map = DuckPadMap.defaults(in: .walk)
        map.bind(.play(sequence: UUID(), thenLoading: nil), to: .a)
        let gone: (UUID) -> String? = { _ in nil }
        XCTAssertEqual(map.effect(for: .a, naming: gone),
                       .notYet(DuckPadMap.sequenceIsGone(.a)))
        XCTAssertFalse(map.shown(for: .a, naming: gone).isLive)
        XCTAssertTrue(DuckPadMap.sequenceIsGone(.a).hasPrefix("A "),
                      "and it names which button it was")
    }

    func testABoundSequenceThatStillExistsIsLiveAndNamed() {
        var map = DuckPadMap.defaults(in: .walk)
        let id = UUID()
        map.bind(.play(sequence: id, thenLoading: .roulade), to: .y)
        let shown = map.shown(for: .y, naming: { $0 == id ? "Fast turn" : nil })
        XCTAssertTrue(shown.isLive)
        XCTAssertTrue(shown.caption.contains("Fast turn"), shown.caption)
        XCTAssertTrue(shown.detail.contains("roulade"), shown.detail)
    }

    /// A MOTION GOES ON A BUTTON. It could not until there was a door that
    /// stops the drive loop, runs the track and hands the sticks back; there
    /// is one now, so the binding is real rather than a named not-yet.
    func testAMotionCanBeBoundToAButtonAndSaysWhatItWillDo() {
        var map = DuckPadMap.defaults(in: .walk)
        let motion = UUID()
        map.bind(.run(motion: motion), to: .b)
        XCTAssertEqual(map.effect(for: .b), .run(motion: motion))
        let shown = map.shown(for: .b, naming: { _ in nil }, namingMotion: { _ in "lever_up" })
        XCTAssertTrue(shown.isLive)
        XCTAssertEqual(shown.caption, "Run lever_up")
        XCTAssertTrue(shown.detail.contains("once on the bench"), shown.detail)
        XCTAssertTrue(shown.detail.contains("sticks come back"), shown.detail)
    }

    /// And a motion deleted in Studio becomes a named not-yet on the way out,
    /// exactly as a deleted sequence does — never a button that does nothing.
    func testAMotionDeletedInStudioBecomesANamedNotYet() {
        var map = DuckPadMap.defaults(in: .walk)
        map.bind(.run(motion: UUID()), to: .b)
        let shown = map.shown(for: .b, naming: { _ in nil }, namingMotion: { _ in nil })
        XCTAssertFalse(shown.isLive)
        XCTAssertTrue(shown.detail.hasPrefix(DuckPadMap.motionIsGone(.b)), shown.detail)
        XCTAssertTrue(DuckPadMap.motionIsGone(.b).contains("deleted in"))
    }

    /// The binding survives the round trip through the file, so a button keeps
    /// its motion across a relaunch.
    func testAMotionBindingSurvivesTheFile() throws {
        var map = DuckPadMap.defaults(in: .walk)
        let motion = UUID()
        map.bind(.run(motion: motion), to: .y)
        let read = try DuckPadMap.decode(try map.encoded())
        XCTAssertEqual(read.effect(for: .y), .run(motion: motion))
    }

    // MARK: - the file

    func testAMapSurvivesARoundTrip() throws {
        var remapped = DuckPadMap.defaults(in: .walk)
        remapped.steer(.named("mine.onnx"))
        remapped.bind(.play(sequence: UUID(), thenLoading: .walk), to: .y)
        remapped.bind(.stop, to: .start)
        remapped.bind(.notYet("because"), to: .select)
        remapped.bind(.reset, to: .leftTrigger)
        for map in [DuckPadMap.defaults(in: .walk), remapped,
                    DuckPadMap(locomotion: .whateverIsLoaded, buttons: [:])] {
            XCTAssertEqual(try DuckPadMap.decode(try map.encoded()), map)
        }
    }

    func testAMapFromAnUnknownFormatIsRefusedByName() {
        let message = DuckPadMap.ReadError.wrongFormat("duck-padmap/9").message
        XCTAssertTrue(message.contains("duck-padmap/9"))
        XCTAssertTrue(message.contains(DuckPadMap.format), message)
    }

    func testAnUnknownControlNameInAFileIsDroppedRatherThanFatal() throws {
        let json = """
        {"format":"duck-padmap/1","locomotion":{"kind":"slot","slot":"walk"},
         "buttons":{"triangle":{"effect":"stop"},"a":{"effect":"reset"}}}
        """
        let map = try DuckPadMap.decode(XCTUnwrap(json.data(using: .utf8)))
        XCTAssertEqual(map.buttons.count, 1)
        XCTAssertEqual(map.buttons[.a], .reset)
    }

    func testAFileThatIsNotAMapIsRefusedByName() throws {
        XCTAssertThrowsError(try DuckPadMap.decode(XCTUnwrap("nonsense".data(using: .utf8)))) {
            XCTAssertEqual($0 as? DuckPadMap.ReadError, .notJSON)
        }
        let noFormat = try XCTUnwrap("{\"buttons\":{}}".data(using: .utf8))
        XCTAssertThrowsError(try DuckPadMap.decode(noFormat)) {
            XCTAssertEqual($0 as? DuckPadMap.ReadError, .missing("a format"))
        }
    }

    // MARK: - the footnotes

    /// A sequence started from the list was not pressed on anything, and the
    /// merge seam passes an empty face for exactly that. The kit says the
    /// sentence rather than leaving a view to ship " → play x".
    func testASequenceStartedWithoutAButtonStillGetsASentence() {
        XCTAssertEqual(DuckPadMap.pressedToPlay(face: "A", named: "Fast turn"),
                       "A → play Fast turn")
        XCTAssertEqual(DuckPadMap.pressedToPlay(face: "", named: "Fast turn"),
                       "Playing Fast turn")
        XCTAssertFalse(DuckPadMap.sequenceIsGone(face: "").hasPrefix(" "),
                       "and a missing sequence with no button does not start with a space")
    }

    /// Remapping a control on this phone does not change what that button does
    /// on a duck, and the sentence saying so is the kit's rather than a view's.
    func testRemappingIsSaidNotToChangeWhatTheRobotDoes() {
        let said = DuckPadMap.onTheRobotSurvivesARemap("Ground pick")
        XCTAssertTrue(said.contains("Ground pick"), said)
        XCTAssertTrue(said.contains("does not change"), said)
        // Stop and Reset are the bench's own and `padd` has no counterpart, so
        // "On the robot this button is: —" is never printed.
        XCTAssertEqual(DuckPadMap.onTheRobotSurvivesARemap("—"),
                       DuckPadMap.mapLivesOnThisPhone)
    }

    func testTheTwoWaysASequenceGoesOnAButtonAreBothNamed() {
        XCTAssertEqual(DuckPadMap.playIt, "Play it")
        XCTAssertEqual(DuckPadMap.playThenLoad(.groundPick), "Play it, then load ground pick")
    }

    func testTheFootnotesSayWhereTheMapLivesAndWhyTheSticksAlwaysWork() {
        XCTAssertTrue(DuckPadMap.sticksAreAlwaysMapped.contains("Drive works without picking"))
        XCTAssertTrue(DuckPadMap.mapLivesOnThisPhone.contains("not on the bench"))
    }
}
