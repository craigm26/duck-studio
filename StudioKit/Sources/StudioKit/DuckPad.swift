import Foundation
import DuckKit
import DuckEvidence

/// The gamepad layout a Microduck is actually driven with.
///
/// TRANSCRIBED FROM `padd`, WHICH IS THE POINT. `padd/src/main.rs` in
/// `pollen-robotics/microduck` reads a Bluetooth pad and turns it into intents,
/// and its header says why the bindings are what they are: "Muscle memory
/// carries over from `microduck_runtime`." Somebody who has driven this robot
/// already has these in their thumbs. An app that invented its own arrangement
/// would be asking them to learn a second one for the same duck.
///
/// SO THE SCREEN IS LAID OUT LIKE THE PAD, AND A REAL PAD DRIVES IT. Both
/// halves matter: a Pollen tester with a controller paired to their phone
/// should be able to pick it up and drive, and a tester without one should see
/// the same arrangement under their thumbs.
///
/// WHAT IS HONEST ABOUT THE DIFFERENCE. This app drives a BENCH, not a robot.
/// Some of `padd`'s bindings have no meaning against a physics server — there
/// is no power to cut and no motor bus to enable — and the ones that do land
/// differently: on the robot B triggers the ground-pick skill through
/// `robotd`'s slot machinery, and here it hot-swaps the loaded policy to the
/// one filling that slot. `Binding.here` says which is which, and the screen
/// prints it, because a control that looks live and does nothing is the thing
/// this app is built not to ship.
///
/// THIS TABLE IS NOW THE DEFAULT A MAP DEPARTS FROM, NOT THE ONLY ANSWER.
/// `DuckPadMap` lays a person's own arrangement over it — a recorded sequence
/// on Y, a slot on Start, a sequence-then-slot chain on B — and it is SPARSE: a
/// control nobody has remapped falls straight through to
/// `binding(for:)!.here`, so what ships is what happens until somebody decides
/// otherwise, and "put the pad back" is a return to exactly these rows.
/// Nothing here moved to make that work, which is why every assertion in
/// `DuckPadTests` still passes untouched.
///
/// AND `onTheRobot` SURVIVES EVERY REMAP, WHICH IS THE HALF THAT MATTERS.
/// `Binding.here` is what a control does against a bench and a person may
/// change it; `onTheRobot` is `padd`'s own words for what the ROBOT does with
/// that button, and it is not this app's to reassign — the muscle memory this
/// whole file exists to respect belongs to the pad, not to the mapping. So a Y
/// carrying somebody's own recorded sequence still reads "Head mode — the
/// sticks pose the head" beside it, and a tester who knows the robot still
/// knows which button they are looking at.
public enum DuckPad {

    /// A control on the pad, named as the pad's own face prints it.
    public enum Control: String, CaseIterable, Sendable {
        case a, b, x, y
        case leftBumper, rightBumper
        case leftTrigger, rightTrigger
        case dpadUp, dpadDown, dpadLeft, dpadRight
        case start, select
        case leftStick, rightStick
        /// The sticks pressed in. Pollen's pad reads no stick click at all (`Buttons` has no bit
        /// for one, pad-map/src/buttons.rs:11-26), so the bench's own Stop and Reset live here
        /// rather than on a control Pollen binds.
        case leftStickClick, rightStickClick

        /// What is written on the button. `padd` uses gilrs' compass names
        /// (`South`, `East`, `North`, `West`); every pad a person will actually
        /// hold prints letters, and its own doc comment translates them.
        public var face: String {
            switch self {
            case .a: return "A"
            case .b: return "B"
            case .x: return "X"
            case .y: return "Y"
            case .leftBumper: return "LB"
            case .rightBumper: return "RB"
            case .leftTrigger: return "LT"
            case .rightTrigger: return "RT"
            case .dpadUp: return "▲"
            case .dpadDown: return "▼"
            case .dpadLeft: return "◀"
            case .dpadRight: return "▶"
            case .start: return "Start"
            case .select: return "Select"
            case .leftStick: return "L stick"
            case .rightStick: return "R stick"
            case .leftStickClick: return "L3"
            case .rightStickClick: return "R3"
            }
        }
    }

    /// What a control does here, as opposed to on the robot.
    public enum Effect: Equatable, Sendable {
        /// Loads the policy filling a `robotd` slot. The bench hot-swaps
        /// without restarting the world, which is what makes this meaningful:
        /// every Microduck policy reads the same 61 numbers.
        case loadSlot(DuckOfficialPolicies.Slot)
        /// Feeds the velocity twist.
        case drive
        /// Stops — zeroes the command and lets the duck settle under it.
        case stop
        /// Puts the duck back on its feet. Not something a robot can do for
        /// itself, and not something `padd` has: it is the bench's own.
        case reset
        /// One of the duck's own skills, by `robotd`'s name: Pollen's `[pad]`
        /// emotions (`excited`, `yes`, `no`). A real duck runs it with
        /// `robot.do`; the practice duck has no emotions and says so.
        case skill(String)
        /// What the sticks mean: Pollen's D-pad selects a mode
        /// (pad-map/src/mapper.rs:14-19).
        case selectMode(StickMode)
        /// Nothing here. The robot binding has no counterpart on a physics
        /// server, and the screen says so rather than showing a dead control.
        case unsupported(String)
    }

    /// The two stick modes this app can draw. Pollen has four (head, head + move, move,
    /// body + head); the other two are named on their arrows and do nothing here.
    public enum StickMode: String, Equatable, Sendable {
        /// D-pad left: the sticks walk, strafe and turn.
        case move
        /// D-pad up: both sticks pose the head and the body holds still. A real duck only.
        case head
    }

    /// One row of the mapping.
    public struct Binding: Equatable, Sendable, Identifiable {
        public let control: Control
        public var id: String { control.rawValue }
        /// What it does on a real Microduck, in `padd`'s own words.
        public let onTheRobot: String
        /// What it does against a bench.
        public let here: Effect

        public init(control: Control, onTheRobot: String, here: Effect) {
            self.control = control
            self.onTheRobot = onTheRobot
            self.here = here
        }

        /// Whether pressing it will do anything on this screen.
        /// On the practice duck, which is what this table describes: a robot
        /// skill and the head mode are a real duck's, so they read as dead here.
        public var isLive: Bool {
            switch here {
            case .unsupported, .skill, .selectMode(.head): return false
            default: return true
            }
        }
    }

    /// The mapping: Pollen's shipped defaults, control by control.
    ///
    /// EVERY ROW IS POLLEN'S DEFAULT AT pollen-robotics/microduck 094d4bb4
    /// (release 0.21.1), and `DuckPadDefaultsTests` pins each one to its source
    /// line: `PadParams::default()` for the six skill buttons
    /// (robotd-params/src/lib.rs:452-463), `ARROWS` for the D-pad
    /// (pad-map/src/mapper.rs:14-19) and `padd`'s mapping table for the rest
    /// (padd/src/main.rs:30-46).
    ///
    /// WHERE THIS APP HAS A CONTROL POLLEN DOES NOT, IT SITS WHERE POLLEN HAS
    /// NOTHING. The roulade is on X, which Pollen ships empty and re-sends
    /// while held "because it is the button the prototype held the roulade on"
    /// (pad-map/src/mapper.rs:452-454). Stop and Reset are on the stick clicks,
    /// which Pollen does not read. The two kicks are in Pollen's set and on no
    /// Pollen button ("the kicks are still in the set, unbound",
    /// robotd-params/src/lib.rs:425), so they ship on none here either and
    /// are a remap or a Moves tile away.
    public static let bindings: [Binding] = [
        Binding(control: .leftStick,
                onTheRobot: "Walk: forward on y, strafe on x",
                here: .drive),
        Binding(control: .rightStick,
                onTheRobot: "Turn on x; in head mode it poses the head",
                here: .drive),
        Binding(control: .a, onTheRobot: "Sit and stand", here: .loadSlot(.sitstand)),
        Binding(control: .b, onTheRobot: "Ground pick", here: .loadSlot(.groundPick)),
        Binding(control: .x, onTheRobot: "Nothing until a skill is bound there; held, it repeats",
                here: .loadSlot(.roulade)),
        Binding(control: .y, onTheRobot: "Excited (an emotion)", here: .skill("excited")),
        Binding(control: .leftBumper, onTheRobot: "Yes (an emotion)", here: .skill("yes")),
        Binding(control: .rightBumper, onTheRobot: "No (an emotion)", here: .skill("no")),
        Binding(control: .rightTrigger, onTheRobot: "Mouth, and a quack",
                here: .unsupported("The mouth is servo 9 and no network drives it. Nothing on a "
                                 + "bench opens it.")),
        Binding(control: .leftTrigger, onTheRobot: "Mouth, and the wheee",
                here: .unsupported("Same servo, same absence.")),
        Binding(control: .dpadUp, onTheRobot: "Head mode: the sticks pose the head",
                here: .selectMode(.head)),
        Binding(control: .dpadRight, onTheRobot: "Head and move: left stick walks, right stick looks",
                here: .unsupported("This app does not drive and look at once yet. Use head mode "
                                 + "on the arrow up, then move mode on the arrow left.")),
        Binding(control: .dpadLeft, onTheRobot: "Move mode: the sticks walk, strafe and turn",
                here: .selectMode(.move)),
        Binding(control: .dpadDown, onTheRobot: "Body and head: crouch and lean, right stick looks",
                here: .unsupported("Body pose rides in the command block the bench does not "
                                 + "accept, so this does nothing here.")),
        Binding(control: .start,
                onTheRobot: "Stand up, then toggle the policy; held 1.5 s, home pose",
                here: .unsupported("There is no motor bus to enable. The bench is always running "
                                 + "whatever is loaded.")),
        Binding(control: .select,
                onTheRobot: "Held 2 s, sit and rest with torque off; held 4 s, power off",
                here: .unsupported("Nothing here has power to cut.")),
        // NOT POLLEN'S: the bench's own, on the clicks Pollen's pad never reads.
        // A robot cannot put itself back on its feet, which is exactly why the
        // physics server has a control the pad does not.
        Binding(control: .leftStickClick, onTheRobot: "—", here: .stop),
        Binding(control: .rightStickClick, onTheRobot: "—", here: .reset),
    ]

    /// The buttons a roller duck leaves unbound whatever `[pad]` says:
    /// `Config::ROLLER_UNBOUND` (pad-map/src/mapper.rs:141-143, Pollen #576).
    public static let rollerRunsNothing: [Control] = [.a, .x]

    /// What A and X say on a duck on wheels.
    public static let onWheelsNothing =
        "On wheels this button runs nothing, as on Pollen's pad: sit and stand has no meaning there."

    /// What a robot-only skill says on the practice duck.
    public static func onlyOnARealDuck(_ skill: String) -> String {
        "\(skill.capitalized) is one of the duck's own emotions and the practice duck has none. "
      + "On a real duck this button plays it."
    }

    /// What the arrows say when they change what the sticks mean.
    public static func modeSaid(_ mode: StickMode) -> String {
        switch mode {
        case .move: return "Move mode: the sticks walk, strafe and turn."
        case .head: return "Head mode: the sticks pose the head and the body holds still."
        }
    }

    /// Head mode on the practice duck.
    public static let noHeadOnTheBench =
        "The bench takes a velocity twist and no head pose, so there is no head to put the "
      + "sticks on. On a real duck this arrow is head mode."

    public static func binding(for control: Control) -> Binding? {
        bindings.first { $0.control == control }
    }

    /// The bindings that do something here, for a layout that leads with them.
    public static var live: [Binding] { bindings.filter(\.isLive) }

    /// What the screen says about a pad it can see.
    public static func connected(_ name: String) -> String {
        "\(name) is driving. The sticks and buttons are mapped the way padd maps them on the "
      + "robot, so what you already know carries over — except where a bench cannot do it, "
      + "which each control says for itself."
    }

    /// And when there is none.
    public static let noPad =
        "No controller paired. The on-screen pads below are laid out the way a real one is, and "
      + "pairing a Bluetooth controller to this phone in Settings will drive the same things "
      + "without changing anything here."

    // MARK: - the layers

    /// One overlay of information the driver can switch on or off.
    ///
    /// A DRIVER AND A TESTER WANT DIFFERENT SCREENS, and the difference is not
    /// a mode — it is how much is on top of the picture. Somebody steering
    /// wants the duck and nothing else; somebody deciding whether a policy is
    /// worth putting on hardware wants the command that went out, what came
    /// back, and which joints are near their stops. Both are the same session,
    /// so they are layers rather than screens.
    public enum Layer: String, CaseIterable, Sendable, Identifiable {
        case command, telemetry, joints, limits, policy, link
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .command: return "Command"
            case .telemetry: return "Telemetry"
            case .joints: return "Joints"
            case .limits: return "Near limits"
            case .policy: return "Policy"
            case .link: return "Link"
            }
        }

        public var detail: String {
            switch self {
            case .command:
                return "The twist going out, in the robot's own units — and whether it is under "
                     + "the threshold where the gait just stands."
            case .telemetry:
                return "Trunk height, upright or not, and the sim clock."
            case .joints:
                return "All fourteen driven joints, live."
            case .limits:
                return "Only the joints within ten degrees of a stop — the ones about to clip."
            case .policy:
                return "Which network is loaded and what scale it runs at."
            case .link:
                return "Round trips and how fast they are coming back. A bench on a slow link "
                     + "makes a good policy look like it lurches."
            }
        }

        /// What a driver sees before touching anything.
        ///
        /// TELEMETRY ONLY. The other five are for somebody asking a question
        /// about a policy; leading with all six is a windscreen covered in
        /// instruments.
        // NOTHING ON BY DEFAULT, BECAUSE THE DUCK COMES FIRST. Telemetry was on
        // by default and the HUD that carries it covered about half of a
        // 300-point stage on the one screen that moves a robot — the same
        // occlusion build 42 fixed on the legend. The chips are one tap away.
        public static let defaults: Set<Layer> = []
    }

    /// Joints within this angle of a stop count as "near a limit".
    ///
    /// TEN DEGREES, AND THE REASON IT IS SHOWN AT ALL: a policy that looks fine
    /// while quietly holding a joint against its stop is a policy that will
    /// behave differently on hardware, where the stop is a physical object and
    /// not a clamp. The last-mile work found exactly this — a clone driving the
    /// neck to the −1.920 rad stop in 0.4 s and staying there.
    public static let nearLimitRadians = 10.0 * .pi / 180.0

    /// Which of the fourteen driven joints are within `nearLimitRadians` of a
    /// stop, given all fifteen joint angles.
    public static func nearLimits(_ angles: [Double]) -> [(name: String, angle: Double,
                                                           limit: Double)] {
        guard angles.count == DuckModel.jointNames.count else { return [] }
        var out: [(String, Double, Double)] = []
        for slot in 0..<DuckModel.policyJointCount {
            let joint = DuckModel.jointOfPolicySlot(slot)
            let range = DuckModel.jointRanges[joint]
            let angle = angles[joint]
            if angle - range.lower <= nearLimitRadians {
                out.append((DuckModel.jointNames[joint], angle, range.lower))
            } else if range.upper - angle <= nearLimitRadians {
                out.append((DuckModel.jointNames[joint], angle, range.upper))
            }
        }
        return out
    }
}
