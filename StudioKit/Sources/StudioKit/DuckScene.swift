import Foundation
import DuckKit

/// A place to put the robot: the floor, and whatever is standing on it.
///
/// WHY THIS EXISTS SEPARATELY FROM `DuckIntentClip.Environment`. The clip's
/// environment is a RECORD — what a motion was actually performed against,
/// decoded from the recording and immutable, because changing it would make the
/// clip describe a run that never happened. This is the EDITABLE thing: a scene
/// somebody builds, saves, and then plays clips against to ask "what would this
/// motion look like here?". The two convert both ways, and the direction of
/// travel matters — a recorded environment is the honest starting point for a
/// scene, and a scene is never allowed to overwrite a recording.
///
/// COORDINATES ARE THE CLIP'S, IN METRES. x is forward from where the robot
/// starts, y is to its left, z is up — MuJoCo's convention, which is the
/// robot's, which is the recording's. Every renderer converts once at the
/// boundary rather than storing a second frame here.
public struct DuckScene: Codable, Equatable, Identifiable, Sendable {

    public struct Step: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        /// The centre of the block in plan.
        public var x: Double
        public var y: Double
        /// The height of the UPPER FACE. The block extends `halfHeight` below
        /// it, which is what keeps a 10 mm step a solid body rather than a
        /// floating slab.
        public var top: Double
        public var halfDepth: Double
        public var halfWidth: Double
        public var halfHeight: Double

        public init(id: UUID = UUID(), x: Double, y: Double, top: Double,
                    halfDepth: Double = 0.17, halfWidth: Double = 0.17,
                    halfHeight: Double = 0.10) {
            self.id = id; self.x = x; self.y = y; self.top = top
            self.halfDepth = halfDepth; self.halfWidth = halfWidth
            self.halfHeight = halfHeight
        }
    }

    public struct Wall: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var x: Double
        public var y: Double
        public var halfThickness: Double
        public var height: Double
        public var halfLength: Double

        public init(id: UUID = UUID(), x: Double, y: Double,
                    halfThickness: Double = 0.025, height: Double = 0.6,
                    halfLength: Double = 1.5) {
            self.id = id; self.x = x; self.y = y
            self.halfThickness = halfThickness; self.height = height
            self.halfLength = halfLength
        }
    }

    public var id: UUID
    public var name: String
    public var ground: Bool
    public var steps: [Step]
    public var walls: [Wall]
    /// Where this scene came from, in one line, for display. A scene lifted off
    /// a recording says so, because "the staircase step_up was recorded on" and
    /// "a staircase somebody drew" are different claims about the same boxes.
    public var provenance: String

    public init(id: UUID = UUID(), name: String, ground: Bool = true,
                steps: [Step] = [], walls: [Wall] = [],
                provenance: String = "Built here") {
        self.id = id; self.name = name; self.ground = ground
        self.steps = steps; self.walls = walls; self.provenance = provenance
    }

    // MARK: - conversion

    /// Lift a scene out of a recording, so the world a motion was performed
    /// against becomes something you can pick up and change.
    public init(name: String, recorded environment: DuckIntentClip.Environment) {
        self.init(name: name,
                  ground: environment.ground,
                  steps: environment.steps.map {
                      Step(x: $0.x, y: $0.y, top: $0.top, halfDepth: $0.halfDepth,
                           halfWidth: $0.halfWidth, halfHeight: $0.halfHeight)
                  },
                  walls: environment.walls.map {
                      Wall(x: $0.x, y: $0.y, halfThickness: $0.halfThickness,
                           height: $0.height, halfLength: $0.halfLength)
                  },
                  provenance: "Lifted from the recording of \(name)")
    }

    /// The form a renderer draws. `yaw` is zero because a scene is authored in
    /// the robot's own frame — the rotation in a recorded environment exists
    /// only to undo the heading the duck happened to be facing in MuJoCo, and
    /// carrying that into a hand-built scene would tilt the room for no reason.
    public var environment: DuckIntentClip.Environment {
        DuckIntentClip.Environment(
            ground: ground, yaw: 0,
            steps: steps.map {
                .init(x: $0.x, y: $0.y, top: $0.top, halfDepth: $0.halfDepth,
                      halfWidth: $0.halfWidth, halfHeight: $0.halfHeight)
            },
            walls: walls.map {
                .init(x: $0.x, y: $0.y, halfThickness: $0.halfThickness,
                      height: $0.height, halfLength: $0.halfLength)
            })
    }

    // MARK: - starting points

    public static func bareFloor() -> DuckScene {
        DuckScene(name: "Bare floor", provenance: "Nothing but the ground")
    }

    /// A flight of steps.
    ///
    /// `rise` IS THE NUMBER THAT DECIDES WHETHER THIS IS USABLE, and the
    /// default is 10 mm rather than anything that looks like a staircase,
    /// because 10 mm is what the robot has been measured to clear. A generator
    /// that defaulted to 40 mm would produce a scene that looks right in the
    /// editor and faceplants every time.
    public static func staircase(count: Int = 4, rise: Double = 0.010,
                                 run: Double = 0.28, start: Double = 0.30,
                                 halfDepth: Double = 0.17,
                                 halfWidth: Double = 0.17) -> DuckScene {
        var steps: [Step] = []
        for i in 0..<max(count, 0) {
            steps.append(Step(x: start + Double(i) * run + halfDepth, y: 0,
                              top: Double(i + 1) * rise,
                              halfDepth: halfDepth, halfWidth: halfWidth,
                              // Deep enough that even the lowest step has a
                              // body under it rather than hovering.
                              halfHeight: max(0.10, Double(i + 1) * rise)))
        }
        return DuckScene(name: "\(count) steps at \(Int((rise * 1000).rounded())) mm",
                         steps: steps,
                         provenance: "Generated: \(count) × \(Int((rise * 1000).rounded())) mm rise, "
                                   + "\(Int((run * 1000).rounded())) mm run")
    }

    /// A single wall to push off, at the distance `wall_flip` was searched at.
    public static func wall(distance: Double = 1.5) -> DuckScene {
        DuckScene(name: "Wall at \(Int((distance * 1000).rounded())) mm",
                  walls: [Wall(x: 0, y: distance)],
                  provenance: "Generated: one wall, \(Int((distance * 1000).rounded())) mm to the left")
    }

    /// Two walls facing each other — the shape a ToF-driven automation is
    /// actually tested in, because a corridor is where "which way is clearer?"
    /// has an answer.
    public static func corridor(width: Double = 0.9) -> DuckScene {
        DuckScene(name: "Corridor, \(Int((width * 1000).rounded())) mm wide",
                  walls: [Wall(x: 0, y: width / 2), Wall(x: 0, y: -width / 2)],
                  provenance: "Generated: two walls \(Int((width * 1000).rounded())) mm apart")
    }

    public static let starters: [DuckScene] = [
        bareFloor(), staircase(), wall(), corridor(),
    ]

    // MARK: - what is wrong with it

    /// The measured ceiling on how tall a step this robot gets up.
    ///
    /// NOT A SPEC FIGURE AND NOT A GUESS. A search over authored moves against
    /// staged steps topped out here; earlier runs that reported far more were
    /// scoring against a lone block the duck stepped beside rather than a
    /// flight it had to climb, and every one of those numbers was withdrawn.
    /// A scene editor that lets somebody draw a 40 mm staircase without saying
    /// this is an editor that produces confident failures.
    public static let measuredStepCeiling = 0.010

    public struct Problem: Equatable, Sendable {
        public enum Severity: String, Equatable, Sendable {
            /// The scene cannot be drawn or played as written.
            case broken
            /// It will draw, and the robot will not manage it.
            case unreachable
        }
        public let severity: Severity
        public let text: String
    }

    /// Everything wrong with this scene, in the order somebody would fix it.
    ///
    /// Steps are checked as a FLIGHT, sorted along x, because the number that
    /// matters is each one's rise above the one before it — not its absolute
    /// height. A staircase of ten 10 mm steps is climbable and 100 mm tall; a
    /// single 100 mm block is not, and an absolute-height check calls them the
    /// same thing.
    public var problems: [Problem] {
        var out: [Problem] = []

        if !ground && !steps.isEmpty {
            out.append(.init(severity: .broken,
                             text: "There is no floor, so the steps have nothing to stand on and the robot has nothing to fall to."))
        }
        for step in steps where step.top - step.halfHeight * 2 > 0.0005 {
            out.append(.init(severity: .broken,
                             text: String(format: "A step whose top is at %.0f mm is only %.0f mm thick, so it floats above the floor.",
                                          step.top * 1000, step.halfHeight * 2000)))
        }
        for step in steps where step.halfDepth <= 0 || step.halfWidth <= 0 || step.halfHeight <= 0 {
            out.append(.init(severity: .broken, text: "A step has no size in one direction."))
        }

        let flight = steps.sorted { $0.x < $1.x }
        var previousTop = 0.0
        for step in flight {
            let rise = step.top - previousTop
            if rise > Self.measuredStepCeiling + 1e-9 {
                out.append(.init(
                    severity: .unreachable,
                    text: String(format: "A %.0f mm rise. The robot has been measured at %.0f mm, so it will not get up this one.",
                                 rise * 1000, Self.measuredStepCeiling * 1000)))
            }
            previousTop = max(previousTop, step.top)
        }

        for wall in walls where wall.height <= 0 || wall.halfThickness <= 0 || wall.halfLength <= 0 {
            out.append(.init(severity: .broken, text: "A wall has no size in one direction."))
        }
        // A wall through the origin is a wall through the robot: every clip
        // starts there, de-origined, so this is not a hypothetical.
        for wall in walls where abs(wall.y) < wall.halfThickness + 0.06
                             && abs(wall.x) < wall.halfLength {
            out.append(.init(severity: .broken,
                             text: "A wall passes through where the robot starts."))
        }
        return out
    }

    /// The one line to show beside the scene's name.
    public var summary: String {
        var parts: [String] = []
        if !steps.isEmpty {
            let tallest = steps.map(\.top).max() ?? 0
            parts.append("\(steps.count) step\(steps.count == 1 ? "" : "s") to \(Int((tallest * 1000).rounded())) mm")
        }
        if !walls.isEmpty { parts.append("\(walls.count) wall\(walls.count == 1 ? "" : "s")") }
        if parts.isEmpty { parts.append(ground ? "Bare floor" : "No floor") }
        return parts.joined(separator: " · ")
    }
}
