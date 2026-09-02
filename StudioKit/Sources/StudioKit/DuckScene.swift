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
public struct DuckScene: Codable, Hashable, Identifiable, Sendable {

    public struct Step: Codable, Hashable, Identifiable, Sendable {
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

    public struct Wall: Codable, Hashable, Identifiable, Sendable {
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

    /// Something the duck could take hold of.
    ///
    /// A SCENE WAS A PLACE; NOW IT CAN HOLD THINGS. Steps and walls are what a
    /// motion is judged AGAINST — you fall off them. A prop is what a motion is
    /// FOR: the broom it drags, the stick it fetches. The difference matters
    /// because a prop has a mass and a grip, and those decide whether the job
    /// is possible at all, in a way the geometry of a wall never does.
    ///
    /// EVERY NUMBER HERE IS ABOUT YOUR OBJECT, NOT ABOUT THE ROBOT. The robot's
    /// numbers — what it can lift, how hard it can pull, how high the mouth
    /// reaches — are measured and live in `Retrieval`. These are descriptions
    /// of a thing in your room, so they are editable and the screen says they
    /// are estimates.
    public struct Prop: Codable, Hashable, Identifiable, Sendable {
        public enum Shape: String, Codable, Hashable, Sendable {
            /// Long and thin: a broom handle, a stick, a pencil.
            case rod
            /// Roughly round: a ball.
            case ball
            /// A box.
            case block
        }

        public var id: UUID
        public var name: String
        public var shape: Shape
        /// Where it is, metres, in the scene's frame.
        public var x: Double
        public var y: Double
        /// How heavy, grams.
        public var grams: Double
        /// Across the part the duck would bite, millimetres.
        public var thicknessMillimetres: Double
        /// End to end, metres. A ball's is its diameter.
        public var length: Double
        /// How high off the floor the graspable part sits, millimetres. Nil
        /// means it is lying down, and the mouth has to reach the floor.
        public var graspHeightMillimetres: Double?
        /// How well it slides on your floor. An estimate, and the reason a
        /// broom is draggable on boards and not on a rug.
        public var floorFriction: Double

        public init(id: UUID = UUID(), name: String, shape: Shape = .rod,
                    x: Double, y: Double, grams: Double,
                    thicknessMillimetres: Double, length: Double,
                    graspHeightMillimetres: Double? = nil,
                    floorFriction: Double = 0.4) {
            self.id = id; self.name = name; self.shape = shape
            self.x = x; self.y = y; self.grams = grams
            self.thicknessMillimetres = thicknessMillimetres
            self.length = length
            self.graspHeightMillimetres = graspHeightMillimetres
            self.floorFriction = floorFriction
        }

        /// How far the duck has to walk to reach it from the origin.
        public var metresAway: Double { (x * x + y * y).squareRoot() }

        /// Standing it up, or laying it down, without inventing a new prop.
        public func standing(_ height: Double?) -> Prop {
            var copy = self
            copy.graspHeightMillimetres = height
            return copy
        }
    }

    public var id: UUID
    public var name: String
    public var ground: Bool
    public var steps: [Step]
    public var walls: [Wall]
    /// Things in the scene the duck could pick up, drag, or trip over.
    /// Optional in the file so every scene saved before props existed still
    /// decodes.
    public var props: [Prop] = []
    /// Where this scene came from, in one line, for display. A scene lifted off
    /// a recording says so, because "the staircase step_up was recorded on" and
    /// "a staircase somebody drew" are different claims about the same boxes.
    public var provenance: String

    /// DECODED BY HAND, FOR ONE REASON: a synthesized `init(from:)` ignores a
    /// property's default value and demands the key. `props` arrived after
    /// people had already saved scenes, so the synthesized version threw
    /// `keyNotFound("props")` on every one of them — every scene in the app,
    /// unreadable, because a field was added. A test caught it; a user would
    /// have caught it by losing their work.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(UUID.self, forKey: .id)
        name = try box.decode(String.self, forKey: .name)
        ground = try box.decodeIfPresent(Bool.self, forKey: .ground) ?? true
        steps = try box.decodeIfPresent([Step].self, forKey: .steps) ?? []
        walls = try box.decodeIfPresent([Wall].self, forKey: .walls) ?? []
        props = try box.decodeIfPresent([Prop].self, forKey: .props) ?? []
        provenance = try box.decodeIfPresent(String.self, forKey: .provenance) ?? "Built here"
    }

    public init(id: UUID = UUID(), name: String, ground: Bool = true,
                steps: [Step] = [], walls: [Wall] = [], props: [Prop] = [],
                provenance: String = "Built here") {
        self.id = id; self.name = name; self.ground = ground
        self.steps = steps; self.walls = walls; self.props = props
        self.provenance = provenance
    }

    // MARK: - conversion

    /// Lift a scene out of a recording, so the world a motion was performed
    /// against becomes something you can pick up and change.
    ///
    /// THE CLIP'S NAME AND THE SCENE'S NAME ARE TWO NAMES. The signature this
    /// replaces took one string and wrote it into both, so the provenance line
    /// followed the SCENE's name — and the moment somebody renamed the scene,
    /// that line named a recording nothing was ever called. The scene is free
    /// to be renamed afterwards; the recording it was lifted off is not, and
    /// only `clipName` is allowed into the sentence about it.
    public init(name: String, liftedFrom clipName: String,
                recorded environment: DuckIntentClip.Environment) {
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
                  provenance: "Lifted from the recording of \(clipName)")
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
    /// default is `StepCeiling.current.editorRise` — 10 mm — which sits UNDER
    /// the floor the bench's check can resolve. It is not a rise the robot is
    /// known to clear; it is one nothing is known about either way, so the
    /// editor's flag is quiet there honestly. A generator that defaulted to
    /// 40 mm would produce a scene that looks right in the editor and, on the
    /// measurement `StepCeiling` carries, has no way up.
    public static func staircase(count: Int = 4, rise: Double = StepCeiling.current.editorRise,
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

    // MARK: - things worth having in a scene

    /// Everyday objects, at their real sizes.
    ///
    /// A BROOM IS ENORMOUS NEXT TO THIS ROBOT and the catalogue does not
    /// pretend otherwise: 1.2 m of handle against a duck 0.25 m tall. That is
    /// the point — the numbers decide what happens, and a toy-sized broom
    /// invented to make the demo work would be the app answering its own
    /// question. Masses and thicknesses are typical household ones, editable
    /// like everything else about your object.
    public static func broom(x: Double = 0.9, y: Double = 0.0,
                             standing: Bool = true) -> Prop {
        Prop(name: "Broom", shape: .rod, x: x, y: y,
             grams: 600, thicknessMillimetres: 25, length: 1.2,
             // Leaning on a wall, the handle crosses the mouth's arc about
             // 150 mm up; laid down it is on the floor like anything else.
             graspHeightMillimetres: standing ? 150 : nil,
             floorFriction: 0.4)
    }

    public static func dowel(x: Double = 0.6, y: Double = 0.2) -> Prop {
        Prop(name: "Dowel", shape: .rod, x: x, y: y,
             grams: 25, thicknessMillimetres: 20, length: 0.3,
             floorFriction: 0.4)
    }

    public static func pencil(x: Double = 0.5, y: Double = -0.25) -> Prop {
        Prop(name: "Pencil", shape: .rod, x: x, y: y,
             grams: 6, thicknessMillimetres: 7, length: 0.18,
             floorFriction: 0.35)
    }

    /// Pollen's own ball, as the physics scene has it: 50 mm radius, 30 g.
    public static func ball(x: Double = 0.55, y: Double = 0.10) -> Prop {
        Prop(name: "Ball", shape: .ball, x: x, y: y,
             grams: 30, thicknessMillimetres: 100, length: 0.1,
             floorFriction: 0.4)
    }

    /// The blocks already in the physics scene, at their declared masses.
    public static func block(x: Double = 0.30, y: Double = 0.40) -> Prop {
        Prop(name: "Block", shape: .block, x: x, y: y,
             grams: 30, thicknessMillimetres: 40, length: 0.04,
             floorFriction: 0.9)
    }

    public static let graspables: [(name: String, make: () -> Prop)] = [
        ("Broom, standing", { DuckScene.broom() }),
        ("Broom, laid down", { DuckScene.broom(standing: false) }),
        ("Dowel", { DuckScene.dowel() }),
        ("Pencil", { DuckScene.pencil() }),
        ("Ball", { DuckScene.ball() }),
        ("Block", { DuckScene.block() }),
    ]

    /// A floor with a broom on it — the scene the fetch and drag work is for.
    public static func broomCupboard() -> DuckScene {
        DuckScene(name: "Broom in the corner",
                  props: [broom(), dowel(), pencil()],
                  provenance: "A floor with things on it to pick up")
    }

    public static let starters: [DuckScene] = [
        bareFloor(), broomCupboard(), staircase(), wall(), corridor(),
    ]

    // MARK: - what is wrong with it

    /// The measured ceiling on how tall a step this robot gets up.
    ///
    /// The rise the editor starts at and steps by. NOT A MEASURED CEILING —
    /// the name is kept for its callers and the number is `StepCeiling`'s
    /// `editorRise`, which is under the floor the measurement can resolve.
    /// What the robot has actually been measured to clear, with its count,
    /// criterion, plant and date, is `StepCeiling.current`, and the sentence
    /// under an unreachable step comes from there. The old value here shipped
    /// as "the robot has been measured at 10 mm"; nothing has been measured to
    /// clear 10 mm, and the check cannot see a step that small.
    public static var measuredStepCeiling: Double { StepCeiling.current.editorRise }

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
            // THE SENTENCE IS THE MEASUREMENT'S, NOT A CONSTANT'S. A rise the
            // check can resolve gets the count, the plant and the date; a rise
            // it cannot resolve gets no verdict at all rather than a kind one.
            if StepCeiling.current.canResolve(rise: rise) {
                out.append(.init(severity: .unreachable,
                                 text: StepCeiling.current.verdict(rise: rise)))
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
    ///
    /// PROPS ARE PART OF THE ANSWER, and leaving them out made this line lie
    /// about the one starter scene that has nothing else in it: "Broom in the
    /// corner" holds a broom, a dowel and a pencil, no steps and no walls, and
    /// this said "Bare floor" directly under its name. `StageCaption.contents`
    /// is shared with the caption over the stage so the two cannot drift.
    public var summary: String {
        let parts = StageCaption.contents(stepCount: steps.count,
                                          tallestStepMetres: steps.map(\.top).max() ?? 0,
                                          wallCount: walls.count,
                                          propCount: props.count)
        if parts.isEmpty { return ground ? "Bare floor" : "No floor" }
        return parts.joined(separator: " · ")
    }
}

extension DuckScene.Prop {

    /// This prop as something `Retrieval` can plan against.
    ///
    /// THE POINT OF PUTTING OBJECTS IN A SCENE. Before this, asking the app
    /// whether the duck could fetch something meant describing the thing in a
    /// sentence and letting it guess — a pencil "about 6 g". A prop in a scene
    /// has been given its numbers once, by you, and every plan made against it
    /// uses those instead of an estimate.
    public var stick: Retrieval.Stick {
        Retrieval.Stick(grams: grams,
                        thicknessMillimetres: thicknessMillimetres,
                        metresAway: metresAway,
                        graspHeightMillimetres: graspHeightMillimetres,
                        floorFriction: floorFriction)
    }

    /// What would happen if the duck were asked to fetch it.
    public var plan: Retrieval.Plan { Retrieval.plan(for: stick) }
}

extension DuckScene {

    /// The prop a sentence is about, matched by name.
    ///
    /// Matching on the name is deliberate: somebody who wrote "Broom" on a
    /// prop and then typed "drag the broom" means THAT broom, with the mass
    /// and the grip height they gave it, not the catalogue's guess.
    public func prop(named text: String) -> Prop? {
        let lowered = text.lowercased()
        return props.first { lowered.contains($0.name.lowercased()) }
    }
}
