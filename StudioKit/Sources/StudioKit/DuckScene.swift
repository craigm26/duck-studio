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

// MARK: - the challenge's own room

extension DuckScene {

    /// THE STAIRS CHALLENGE'S FLIGHT, IN THE DRAFT'S OWN FRAME.
    ///
    /// WHY THIS IS NOT `staircase(count:rise:run:start:)`. That one draws a
    /// staircase somebody asked for. This one draws THE staircase — the blocks
    /// `climb_score.mjs` lays out and every published number was scored
    /// against — and the two differ in the only way that matters: where the
    /// duck is standing relative to them. The harness spawns the duck at
    /// `(0.12 − 0.07 − gap, 1.305 + side)` in the room's coordinates and the
    /// first riser at `x = 0.12`; a draft's coordinates are the SPAWN's, with
    /// the duck at the origin. So every number here is translated, not copied,
    /// and a scene built by handing `staircase` a start of 0.12 would put the
    /// first riser 50 mm further away than the one the score came from.
    ///
    /// THE WALL IS AT 1.50, NOT AT `STAIR_Y + 0.17`. `stairs.js` records the
    /// correction: `wall_n` is 50 mm half-thick, so its inner face is at
    /// y = 1.45 and the outer 25 mm of every tread sits INSIDE it. That is
    /// where the blocks actually are — they are compiled at that y with x and
    /// z slides only — so the scene draws them there. It is a stated fact
    /// about the harness, not a bug this app is entitled to fix.
    ///
    /// `halfHeight` IS THE WHOLE FLIGHT'S, NOT THE HARNESS'S 100 MM. The
    /// harness draws every block 200 mm tall because a step floating over the
    /// floor costs nothing in physics. It costs something here: `problems`
    /// reports a tread whose block does not reach the floor as BROKEN, and at
    /// the 180 mm rise the app offers, four of the harness's blocks would
    /// float. So each block is made deep enough to reach the floor, the way
    /// `staircase` already does.
    public static func stairsChallenge(rise: Double,
                                       count: Int = StairsChallenge.Harness.stepCount,
                                       gap: Double = 0,
                                       side: Double = 0,
                                       spawn: (x: Double, y: Double)? = nil) -> DuckScene {
        let harness = StairsChallenge.Harness.self
        // Where the harness puts the duck, in the room's coordinates. A move
        // that carries its own `spawn` object (the placed-duck controls) is
        // scored from THAT point and its gap and side are ignored by the
        // harness, so the room must start there too — otherwise the two rows
        // that begin ON the tread would open in a room that puts them on the
        // floor in front of it.
        let spawnX = spawn?.x ?? (harness.riserX - harness.spawnStandoff - gap)
        let spawnY = spawn?.y ?? (harness.stairY + side)

        let steps = (0..<max(count, 0)).map { i -> Step in
            Step(x: harness.stairStart + Double(i) * harness.stairRun
                    + harness.stepHalfDepth - spawnX,
                 y: harness.stairY - spawnY,
                 top: Double(i + 1) * rise,
                 halfDepth: harness.stepHalfDepth,
                 halfWidth: harness.stairHalfWidth,
                 halfHeight: max(harness.stepHalfHeight, Double(max(count, 1)) * rise))
        }
        // Long enough to run past the flight it is standing behind, rather
        // than the 1.5 m default, which would reach a metre behind the duck.
        let reach = steps.map { $0.x + $0.halfDepth }.max() ?? 0.5
        let wall = Wall(x: 0, y: harness.wallCentreY - spawnY,
                        halfThickness: harness.wallHalfThickness,
                        halfLength: max(0.5, reach))

        return DuckScene(name: "\(Challenge.stairs.name) challenge, "
                             + "\(StairsChallenge.riseSaid(rise))",
                         steps: steps, walls: [wall],
                         provenance: harness.provenanceSaid(count: count))
    }

    /// The scene a challenge row opens against, by identity rather than by a
    /// fresh UUID every time.
    ///
    /// WHY IT HAS TO BE DETERMINISTIC. Opening the same row twice must attach
    /// the SAME scene, not a second copy of it: a scene store keyed by id would
    /// otherwise grow a new "Stairs challenge, 60 mm" every time somebody
    /// tapped a row, and a draft saved last week would point at a scene this
    /// build no longer creates. Keyed by the challenge as well as the rise
    /// because the ball challenge's rooms are not the stairs challenge's.
    ///
    /// It is NOT `hashValue`: Swift's hasher is seeded per process, so an id
    /// built on it would change between launches, which is the exact bug this
    /// exists to prevent.
    /// ONE ROOM IS ONE ID. The room's geometry depends on the rise AND on
    /// where the duck stands in it — gap, side (or an explicit spawn) and the
    /// step count — so two rows at the same rise scored from different spots
    /// must not alias onto one scene and overwrite each other in the store.
    /// The offsets are quantised to a tenth of a millimetre so the id is the
    /// same across launches and across the float noise of a JSON round trip.
    public static func challengeSceneID(_ challenge: Challenge,
                                        riseMillimetres: Int,
                                        gap: Double = 0, side: Double = 0,
                                        spawn: (x: Double, y: Double)? = nil,
                                        stepCount: Int = StairsChallenge.Harness.stepCount) -> UUID {
        var bytes = challengeSceneNamespace
        let tenths = { (v: Double) -> Int in Int((v * 10_000).rounded()) }
        let where_ = spawn.map { "s\(tenths($0.x))/\(tenths($0.y))" } ?? "g\(tenths(gap))/\(tenths(side))"
        // FNV-1a, 64 bit — small, stable, and not the standard library's.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Array("\(challenge.rawValue)#\(riseMillimetres)mm#\(where_)#\(stepCount)".utf8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        for offset in 0..<8 {
            bytes[8 + offset] = UInt8(truncatingIfNeeded: hash >> (56 - 8 * offset))
        }
        // Keep it a well-formed variant-1 UUID so nothing downstream balks.
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// A fixed namespace, so the ids are this app's and not anybody else's.
    static let challengeSceneNamespace: [UInt8] = [
        0x6d, 0x69, 0x63, 0x72, 0x6f, 0x64, 0x75, 0x63,
        0x6b, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]
}

// MARK: - where to stand to look at it

extension DuckScene {

    /// Where the camera looks and from how far.
    ///
    /// FOUR NUMBERS, NOT A CAMERA. The kit has no RealityKit and no idea what
    /// an `ARView` is; what it can work out is which point on the floor is
    /// worth looking at and how far back you have to be for the two things
    /// that matter to be on screen at once. The view turns that into an orbit.
    public struct Framing: Equatable, Sendable {
        /// The point to look at, in the scene's frame — metres forward of the
        /// duck, and how high off the floor.
        public let targetX: Double
        public let targetZ: Double
        /// How far the camera sits from that point.
        public let distance: Double
        /// How far above the horizontal it looks down, in radians.
        public let elevation: Double

        public init(targetX: Double, targetZ: Double, distance: Double, elevation: Double) {
            self.targetX = targetX; self.targetZ = targetZ
            self.distance = distance; self.elevation = elevation
        }
    }

    /// The stage's own field of view, as an angle across the frame. The
    /// framing below is solved against the HALF of it.
    public static let authoringFieldOfView = 40.0 * .pi / 180

    /// Room left round the edges, so the thing you are aiming at is not
    /// touching the bezel.
    public static let authoringMargin = 1.15

    /// Looking slightly down, which is how somebody kneeling beside a staircase
    /// sees it.
    public static let authoringElevation = 0.12

    /// How tall the duck stands at home, and how far it reaches sideways —
    /// both derived from the robot's own chain rather than typed, so a
    /// different Microduck moves the camera instead of leaving it wrong.
    public static let duckStandingHeight: Double = duckExtent.height
    public static let duckHalfSpan: Double = duckExtent.halfSpan

    static let duckExtent: (height: Double, halfSpan: Double) = {
        let poses = DuckKinematics.bodyPoses(jointAngles: DuckModel.homePose)
        var height = 0.0
        var halfSpan = 0.0
        for body in DuckKinematics.bodies {
            guard let pose = poses[body.name] else { continue }
            var points = [pose.position]
            for site in body.sites {
                points.append(pose.position + pose.orientation.rotate(site.position))
            }
            for point in points {
                height = max(height, point.z)
                halfSpan = max(halfSpan, (point.x * point.x + point.y * point.y).squareRoot())
            }
        }
        return (height, halfSpan)
    }()

    /// Where to put the camera to AUTHOR against this scene — nil for a scene
    /// with nothing in it, where the stage's own default is already right.
    ///
    /// THE FRAME IS THE DUCK AND THE FIRST RISER, NOT THE WHOLE FLIGHT. The
    /// stage centres on everything it can see, and everything it can see at a
    /// 180 mm rise is a 720 mm staircase with a 250 mm duck at the bottom of
    /// it — which frames the staircase beautifully and makes the thing being
    /// authored about forty points tall. Nobody is authoring the fourth step.
    /// The move that matters is the first one: getting a beak, or a foot, over
    /// the first riser. So the camera holds the duck and that riser, and the
    /// rest of the flight runs out of frame, which is the honest picture of
    /// what a published entry actually does.
    /// The square, conservative bound — what every caller got before stages had
    /// a shape, and what a caller with nothing to measure still gets.
    ///
    /// KEPT AS A PROPERTY. `DuckWorld.swift` reads it and `ChallengeSceneTests`
    /// calls it four more times; a signature change here would drag a file this
    /// track may not open into the same commit.
    public var authoringFraming: Framing? { authoringFraming(aspect: 1) }

    /// Where to put the camera to author against this scene, ON A STAGE OF A
    /// GIVEN SHAPE. `aspect` is the viewport's width divided by its height.
    ///
    /// THE OLD PRECONDITION IS GONE AND IT WAS LOAD-BEARING. This was solved
    /// against the vertical field alone on the stated ground that "the stage is
    /// at least as wide as it is tall on every phone" — true of a 351 × 300
    /// stage and false the moment somebody can make the picture taller. On a
    /// tall portrait stage the horizontal half-extent the camera sees is a
    /// fraction of the vertical one, against `authoringMargin` of 1.15, so the
    /// first riser — the entire thing this framing exists to hold — goes off the
    /// SIDE. Fixed here and not in the renderer: the field stays 40° vertical
    /// and the distance is solved from whichever axis binds.
    public func authoringFraming(aspect: Double) -> Framing? {
        guard let first = steps.min(by: { $0.x < $1.x }) else { return nil }
        let face = first.x - first.halfDepth
        let targetX = face / 2
        let targetZ = (first.top + DuckKinematics.trunkOriginInModelFrame.z) / 2

        // Half the box that has to be on screen: across, the duck and the
        // riser face; up, the floor and the top of the duck's head.
        let across = max(abs(face - targetX), abs(targetX)) + DuckScene.duckHalfSpan
        // The camera looks down at `authoringElevation`: a vertical span
        // foreshortens by cos(elevation) and the duck's depth leans into the
        // vertical by sin(elevation).
        let elevation = DuckScene.authoringElevation
        let up = max(abs(DuckScene.duckStandingHeight - targetZ), abs(targetZ)) * cos(elevation)
               + DuckScene.duckHalfSpan * sin(elevation)

        // THE FIELD IS VERTICAL AND THE GLASS IS NOT ALWAYS SQUARE, so the two
        // axes are solved separately and the binding one wins. At `aspect == 1`
        // the horizontal half-angle equals the vertical one and this reduces
        // exactly to the shipped expression, `max(across, up) / tan(halfV)`.
        let halfV = DuckScene.authoringFieldOfView / 2
        let halfH = atan(tan(halfV) * max(aspect, 0.01))
        let distance = max(up / tan(halfV), across / tan(halfH)) * DuckScene.authoringMargin
        return Framing(targetX: targetX, targetZ: targetZ,
                       distance: distance, elevation: DuckScene.authoringElevation)
    }
}

// MARK: - recognising the room a score is scored in

extension DuckScene {

    /// A scene that IS the stairs challenge's room, with the harness numbers
    /// recovered from its geometry.
    ///
    /// WHY RECOVERY RATHER THAN A STORED FIELD. A scene is a drawing somebody
    /// can move. Storing "this is the 60 mm challenge room" on it would keep
    /// saying so after a step had been dragged 30 mm, and the whole value of
    /// this type is that it cannot: the numbers come out of the geometry, and
    /// the id has to agree with them.
    public struct ChallengeRoom: Equatable, Sendable {
        public let challenge: Challenge
        /// One riser, metres. `steps[0].top`.
        public let rise: Double
        public let stepCount: Int
        /// Where the duck stands, in the HARNESS'S ROOM coordinates.
        public let spawn: DuckWorld.Point
        public let gap: Double
        public let side: Double
        /// True when the id was built from an explicit `spawn:` rather than
        /// from gap/side. The two spellings hash differently, so a recogniser
        /// has to try both and remember which one answered.
        public let spawnWasPlaced: Bool

        public init(challenge: Challenge, rise: Double, stepCount: Int,
                    spawn: DuckWorld.Point, gap: Double, side: Double,
                    spawnWasPlaced: Bool) {
            self.challenge = challenge; self.rise = rise; self.stepCount = stepCount
            self.spawn = spawn; self.gap = gap; self.side = side
            self.spawnWasPlaced = spawnWasPlaced
        }
    }

    public enum RoomReading: Equatable, Sendable {
        case theScoredRoom(ChallengeRoom)
        /// The id says challenge and the geometry has moved. Playable, not
        /// scorable: a score is a score against the flight `climb_score.mjs`
        /// lays out, and these steps are no longer that flight.
        case editedSinceItWasOpened(ChallengeRoom)
        case notAChallengeRoom
    }

    /// Whether this scene is the room the stairs challenge is scored in, and
    /// whether it still is.
    ///
    /// THE ID AND THE GEOMETRY, BOTH, AND THEY DISAGREE LOUDLY. Moving a step
    /// in the editor changes the geometry and NOT the id, so an id-only test
    /// would send an edited room to the scoring route and publish a number
    /// against a flight nobody laid. A geometry-only test would call a
    /// hand-drawn look-alike the scored room, which is the same lie from the
    /// other side.
    public var roomReading: RoomReading {
        // 1. THE SHAPE GATE. The harness's room is a flight and one wall.
        guard (1...DuckWorld.Bank.pinned.count).contains(steps.count),
              walls.count == 1, props.isEmpty else { return .notAChallengeRoom }

        // 2. INVERT. Every one of these is exact affine arithmetic on
        //    `stairsChallenge`'s own construction.
        let harness = StairsChallenge.Harness.self
        let rise = steps[0].top
        guard rise > 0 else { return .notAChallengeRoom }
        for (i, step) in steps.enumerated() where
            abs(step.top - Double(i + 1) * rise) > 1e-9 {
            return .notAChallengeRoom
        }
        let spawnX = (harness.stairStart + harness.stepHalfDepth) - steps[0].x
        let spawnY = harness.stairY - steps[0].y
        let gap = (harness.riserX - harness.spawnStandoff) - spawnX
        let side = spawnY - harness.stairY
        let count = steps.count
        let riseMillimetres = Int((rise * 1000).rounded())

        // 3. REBUILD THE ID IN BOTH SPELLINGS. A room scored from an explicit
        //    spawn hashes differently from one scored from gap and side, and
        //    a recogniser that knew only one would call half the rooms
        //    hand-drawn.
        let fromGap = DuckScene.challengeSceneID(.stairs, riseMillimetres: riseMillimetres,
                                                 gap: gap, side: side, stepCount: count)
        let fromSpawn = DuckScene.challengeSceneID(.stairs, riseMillimetres: riseMillimetres,
                                                   spawn: (spawnX, spawnY), stepCount: count)
        let placed: Bool
        if id == fromSpawn { placed = true }
        else if id == fromGap { placed = false }
        else { return .notAChallengeRoom }

        let room = ChallengeRoom(challenge: .stairs, rise: rise, stepCount: count,
                                 spawn: DuckWorld.Point(x: spawnX, y: spawnY),
                                 gap: gap, side: side, spawnWasPlaced: placed)

        // 4. REBUILD THE ROOM AND COMPARE IT, at the tenth of a millimetre the
        //    id itself is quantised to — which is the tolerance a JSON round
        //    trip already survives.
        let rebuilt = placed
            ? DuckScene.stairsChallenge(rise: rise, count: count, spawn: (spawnX, spawnY))
            : DuckScene.stairsChallenge(rise: rise, count: count, gap: gap, side: side)
        guard rebuilt.steps.count == steps.count, rebuilt.walls.count == walls.count else {
            return .editedSinceItWasOpened(room)
        }
        for (drawn, wanted) in zip(steps, rebuilt.steps) {
            let same = DuckScene.sameToATenthOfAMillimetre
            guard same(drawn.x, wanted.x), same(drawn.y, wanted.y),
                  same(drawn.top, wanted.top),
                  same(drawn.halfDepth, wanted.halfDepth),
                  same(drawn.halfWidth, wanted.halfWidth),
                  same(drawn.halfHeight, wanted.halfHeight) else {
                return .editedSinceItWasOpened(room)
            }
        }
        for (drawn, wanted) in zip(walls, rebuilt.walls) {
            let same = DuckScene.sameToATenthOfAMillimetre
            guard same(drawn.x, wanted.x), same(drawn.y, wanted.y),
                  same(drawn.halfThickness, wanted.halfThickness),
                  same(drawn.height, wanted.height),
                  same(drawn.halfLength, wanted.halfLength) else {
                return .editedSinceItWasOpened(room)
            }
        }
        return .theScoredRoom(room)
    }

    /// The quantum the scene id is built on — a tenth of a millimetre, chosen
    /// there so an id survives a JSON round trip, and used here so the
    /// geometry check has exactly the same tolerance the id does.
    static let sameToATenthOfAMillimetre: (Double, Double) -> Bool = { a, b in
        Int((a * 10_000).rounded()) == Int((b * 10_000).rounded())
    }

    public var challengeRoom: ChallengeRoom? {
        if case .theScoredRoom(let room) = roomReading { return room }
        return nil
    }

    /// Every step, wall, prop and ball moved by (dx, dy).
    ///
    /// THE DUCK MOVES TO THE BANK, BECAUSE THE BANK CANNOT MOVE TO THE DUCK,
    /// and this is that move written down: a scene drawn in the duck's frame
    /// becomes the same scene in the room's. Ids are kept — these are the same
    /// objects somewhere else, not new ones.
    public func translated(by point: DuckWorld.Point) -> DuckScene {
        var moved = self
        moved.steps = steps.map {
            var step = $0; step.x += point.x; step.y += point.y; return step
        }
        moved.walls = walls.map {
            var wall = $0; wall.x += point.x; wall.y += point.y; return wall
        }
        moved.props = props.map {
            var prop = $0; prop.x += point.x; prop.y += point.y; return prop
        }
        return moved
    }
}
