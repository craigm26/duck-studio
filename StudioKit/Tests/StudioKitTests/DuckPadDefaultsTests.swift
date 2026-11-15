import XCTest
import DuckKit
import DuckEvidence
@testable import StudioKit

/// EVERY PAD DEFAULT, PINNED TO POLLEN'S. One row per control and per number,
/// each with the file and line it was read from in pollen-robotics/microduck at
/// 094d4bb4 (release 0.21.1, 2026-11-13). When Pollen moves a default, the row
/// that cites it is the one to change, and the comment says where to look.
///
/// Studio-only controls are pinned too, with the reason they do not shadow a
/// Pollen binding: each sits on a control Pollen leaves empty.
final class DuckPadDefaultsTests: XCTestCase {

    // MARK: - buttons

    func testEveryButtonDefaultIsPollens() throws {
        let rows: [(DuckPad.Control, DuckPad.Effect, String)] = [
            // robotd-params/src/lib.rs:455  a: "sit_toggle"
            (.a, .loadSlot(.sitstand), "sit_toggle"),
            // robotd-params/src/lib.rs:456  b: "ground_pick"
            (.b, .loadSlot(.groundPick), "ground_pick"),
            // robotd-params/src/lib.rs:458  y: "excited"
            (.y, .skill("excited"), "excited"),
            // robotd-params/src/lib.rs:459  lb: "yes"
            (.leftBumper, .skill("yes"), "yes"),
            // robotd-params/src/lib.rs:460  rb: "no"
            (.rightBumper, .skill("no"), "no"),
        ]
        for (control, effect, robotdName) in rows {
            let binding = try XCTUnwrap(DuckPad.binding(for: control))
            XCTAssertEqual(binding.here, effect, "\(control)")
            // And a real duck is sent Pollen's name for it.
            let order = DuckPadMap.shipped(for: control).realDuckOrder
            XCTAssertEqual(order, .skill(robotdName), "\(control)")
        }
    }

    /// robotd-params/src/lib.rs:457  x: String::new(), nothing by default. Pollen
    /// re-sends X while held "because it is the button the prototype held the
    /// roulade on" (pad-map/src/mapper.rs:452-454), so Studio's roulade sits
    /// on the one face button Pollen leaves empty and shadows nothing.
    func testXIsPollensEmptyButtonAndCarriesStudiosRoulade() throws {
        let x = try XCTUnwrap(DuckPad.binding(for: .x))
        XCTAssertEqual(x.here, .loadSlot(.roulade))
        XCTAssertTrue(x.onTheRobot.hasPrefix("Nothing"), x.onTheRobot)
    }

    /// pad-map/src/mapper.rs:14-19, `ARROWS`: up Head, right HeadDrive, left
    /// Drive, down BodyPose.
    func testTheArrowsSelectPollensModes() throws {
        XCTAssertEqual(DuckPad.binding(for: .dpadUp)?.here, .selectMode(.head))
        XCTAssertEqual(DuckPad.binding(for: .dpadLeft)?.here, .selectMode(.move))
        // Head + move and body + head have no counterpart here; each says so.
        for control in [DuckPad.Control.dpadRight, .dpadDown] {
            guard case .unsupported = try XCTUnwrap(DuckPad.binding(for: control)).here else {
                return XCTFail("\(control) should name what it cannot do")
            }
        }
        XCTAssertTrue(try XCTUnwrap(DuckPad.binding(for: .dpadRight)).onTheRobot.hasPrefix("Head and move"))
        XCTAssertTrue(try XCTUnwrap(DuckPad.binding(for: .dpadDown)).onTheRobot.hasPrefix("Body and head"))
    }

    /// padd/src/main.rs:36 (triggers), :42-45 (Start, Select). None of them is a
    /// `robot.do`, and none has a bench counterpart.
    func testTheTriggersStartAndSelectSayWhatPollensPadDoes() throws {
        let words: [(DuckPad.Control, String)] = [
            (.rightTrigger, "quack"), (.leftTrigger, "wheee"),
            (.start, "toggle the policy"), (.select, "power off"),
        ]
        for (control, said) in words {
            let b = try XCTUnwrap(DuckPad.binding(for: control))
            XCTAssertTrue(b.onTheRobot.contains(said), "\(control): \(b.onTheRobot)")
            XCTAssertFalse(b.isLive, "\(control)")
        }
    }

    /// pad-map/src/buttons.rs:11-26: A B X Y LB RB Start Select, the arrows and
    /// Home. No stick click, so Pollen's pad never reads one, and the bench's own
    /// Stop and Reset there shadow nothing.
    func testStopAndResetSitOnClicksPollenDoesNotRead() {
        XCTAssertEqual(DuckPad.binding(for: .leftStickClick)?.here, .stop)
        XCTAssertEqual(DuckPad.binding(for: .rightStickClick)?.here, .reset)
    }

    /// pad-map/src/mapper.rs:141-143, `ROLLER_UNBOUND = ["a", "x"]` (Pollen #576).
    func testOnWheelsAAndXRunNothing() {
        XCTAssertEqual(DuckPad.rollerRunsNothing, [.a, .x])
    }

    // MARK: - the envelope and the curves

    func testTheStickEnvelopeIsPollens() {
        let rows: [(String, Double, Double)] = [
            // robotd-params/src/lib.rs:291  vx_max: 0.4
            ("forward", DuckDrive.Pad.forward, 0.4),
            // robotd-params/src/lib.rs:292  vx_min: -0.3
            ("backward", DuckDrive.Pad.backward, 0.3),
            // robotd-params/src/lib.rs:293-294  vy_max: 0.3, vy_min: -0.3
            ("sideways", DuckDrive.Pad.sideways, 0.3),
            // robotd-params/src/lib.rs:295-296  vyaw_max: 1.0, vyaw_min: -1.0
            ("turn", DuckDrive.Pad.turn, 1.0),
            // robotd-params/src/pad_axes.rs:220  deadzone: 0.1
            ("deadzone", DuckDrive.Pad.deadzone, 0.1),
            // robotd-params/src/pad_axes.rs:266  PadHeadParams::all(2.5)
            ("head travel", DuckDrive.Pad.headTravel, 2.5),
            // robotd-params/src/pad_axes.rs:271  DEFAULT_EXPO: 0.6
            ("head expo", DuckDrive.Pad.headExpo, 0.6),
            // robotd-params/src/pad_axes.rs:272  DEFAULT_MAX_SPEED: 10.0
            ("head max speed", DuckDrive.Pad.headMaxSpeed, 10.0),
            // pad-map/src/mapper.rs:557  HEAD_SLEW_MAX_DT: 0.1
            ("head max step", DuckDrive.Pad.headMaxStep, 0.1),
            // robotd-params/src/pad_axes.rs:333-338  [pad_roller]
            ("roller forward", DuckDrive.Pad.rollerForward, 0.6),
            ("roller backward", DuckDrive.Pad.rollerBackward, 0.5),
            ("roller sideways", DuckDrive.Pad.rollerSideways, 0.0),
            ("roller turn", DuckDrive.Pad.rollerTurn, 0.3),
        ]
        for (name, ours, pollens) in rows {
            XCTAssertEqual(ours, pollens, name)
        }
    }

    /// pad_axes.rs:153-157 (DriveAxes: vx LeftY, vy LeftX inverted, vyaw RightX
    /// inverted) and lib.rs:313-319 (`scale`: linear on each side of centre).
    func testFullDeflectionReachesEachLimitWithPollensSigns() {
        func twist(_ lx: Double, _ ly: Double, _ rx: Double) -> DuckDrive.Twist {
            DuckDrive.twist(for: .init(left: .init(x: lx, y: ly), right: .init(x: rx, y: 0)))
        }
        XCTAssertEqual(twist(0, 1, 0).vx, 0.4, accuracy: 1e-12)
        XCTAssertEqual(twist(0, -1, 0).vx, -0.3, accuracy: 1e-12)
        XCTAssertEqual(twist(-1, 0, 0).vy, 0.3, accuracy: 1e-12)
        XCTAssertEqual(twist(0, 0, 1).vyaw, -1.0, accuracy: 1e-12)
        // Linear: half a stick is half the limit. No rescale past the deadzone (pad_axes.rs:56).
        XCTAssertEqual(twist(0, 0.5, 0).vx, 0.2, accuracy: 1e-12)
        XCTAssertEqual(twist(0, 0.09, 0).vx, 0)
    }

    /// pad_axes.rs:287-290 `shape`, applied to the head sticks in `stick_frame`:
    /// "At 0.6, half a stick is 28 % of the travel" (pad_axes.rs:255).
    func testTheHeadSticksUsePollensExpo() {
        XCTAssertEqual(DuckDrive.Pad.shape(0.5), 0.275, accuracy: 1e-12)
        XCTAssertEqual(DuckDrive.Pad.shape(1), 1, accuracy: 1e-12)
        XCTAssertEqual(DuckDrive.Pad.shape(-1), -1, accuracy: 1e-12)
        let half = DuckDrive.head(for: .init(left: .centred, right: .init(x: 0, y: 0.5)))
        XCTAssertEqual(half.neckPitch, 0.275 * 2.5, accuracy: 1e-12)
    }

    /// pad-map/src/mapper.rs:559-614 `HeadSlew`: a snap glides at max_speed, a
    /// late frame counts as at most 0.1 s, and the first pose goes out as asked.
    func testAHeadSnapGlidesAtPollensCap() {
        var glide = DuckDrive.HeadGlide()
        let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(glide.next(.level, at: t0), .level)
        let full = DuckHead(neckPitch: 2.5, headPitch: 0, headYaw: 0, headRoll: 0)
        let after = glide.next(full, at: t0.addingTimeInterval(0.02))
        XCTAssertEqual(after.neckPitch, 10.0 * 0.02, accuracy: 1e-5)   // Date keeps ~µs
        // A second late is a tenth of a second's worth.
        let late = glide.next(full, at: t0.addingTimeInterval(1.02))
        XCTAssertEqual(late.neckPitch, 0.2 + 1.0, accuracy: 1e-5)
        // A small move stays under the cap and is untouched.
        glide.reset()
        _ = glide.next(.level, at: t0)
        let small = DuckHead(neckPitch: 0.05, headPitch: 0, headYaw: 0, headRoll: 0)
        XCTAssertEqual(glide.next(small, at: t0.addingTimeInterval(0.02)), small)
    }

    /// Planned moves keep their own, lower ceiling: Pollen publishes a pad
    /// default and nothing for a client that is not a pad.
    func testPlansStayUnderThePad() {
        XCTAssertEqual(DuckDrive.maxForward, 0.3)
        XCTAssertLessThan(DuckDrive.maxForward, DuckDrive.Pad.forward)
        XCTAssertEqual(DuckDrive.maxBackward, DuckDrive.Pad.backward)
        XCTAssertEqual(DuckDrive.maxTurn, DuckDrive.Pad.turn)
    }
}
