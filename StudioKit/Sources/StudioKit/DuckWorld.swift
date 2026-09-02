import Foundation
import DuckKit

/// The world the bench is standing in, as something you can change from the
/// phone — and, in the same value, everything it refused to change.
///
/// WHY A WORLD IS NOT JUST A SCENE. `DuckScene` is a drawing: any number of
/// boxes, at any size, anywhere. The bench's world is a FIXED BANK of bodies
/// compiled into `sim/scene_physics.xml` — fourteen step blocks on an x and a z
/// slide each, four static walls with no joints at all, one ball on a freejoint,
/// five small graspables — and the only thing a request can do is write those
/// joints. So a scene sent to a bench is a request that is partly granted, and
/// the interesting half of this type is `unexpressed`: every clause of the
/// drawing that the bank could not say, named, with the reason.
///
/// THE STAGE DRAWS THE READBACK, NEVER THE REQUEST. `asEnvironment` and
/// `asProps` are built from what the bench answered with — that is the whole
/// point of them being on this type rather than on `DuckScene`. A screen that
/// drew the scene it had just sent would show a 250 mm step the bench flattened
/// to 200 mm, a staircase at y = 0 that is really 1.305 m to the left, and a
/// broom that does not exist in that world. Every one of those is a picture of
/// a run that did not happen.
///
/// THE BANK HAS NEVER BEEN PARKED IN THE LIVE WORLD, and that is why "Bare
/// floor" is a choice here rather than the default. `sim/duckbench-core.mjs`
/// imports the stairs only through the climb harness, which builds its own
/// `MjData`; nothing in the live lane has ever called `clearStairs`. So the
/// world a person drives in boots with all fourteen 200 kg blocks stacked at
/// their compiled `qpos0` — (0, 1.305, 0), tops 100 mm up, colliding on every
/// tick. Parking them is a real change to the physics that every published
/// number was NOT measured under, which is what `bareFloorIsAChange` says out
/// loud.
public struct DuckWorld: Equatable, Sendable {

    // MARK: - the bank, transcribed

    /// What the plant actually contains, with the file and line every number
    /// came off.
    ///
    /// IT IS A VALUE AND NOT A WALL OF `static let`s BECAUSE THE BENCH ANSWERS
    /// ONE TOO. `GET /world` reports the bank it is holding, and a bench built
    /// against a recompiled scene would report a different `y`. Keeping the
    /// transcription and the readback in the same type is what lets a screen
    /// print the bench's own numbers while `WorldConstantsFixtureTests` pins
    /// `pinned` against `duck-sounds/site/stairs.js` — the two are allowed to
    /// disagree, and when they do, the bench's is the one that decides what
    /// happens.
    public struct Bank: Equatable, Sendable {

        /// `site/stairs.js:11` — `export const STAIR_COUNT = 14`.
        public let count: Int
        /// `site/stairs.js:26` — `STAIR_Y = 1.5 - 0.025 - STAIR_HALF_WIDTH`,
        /// which is 1.305. COMPILED, NOT A JOINT: the step bodies carry an x
        /// and a z slide and nothing else, so no request can move them across
        /// the room.
        public let y: Double
        /// `site/stairs.js:29` — `STEP_HALF_DEPTH = 0.17`.
        public let halfDepth: Double
        /// `site/stairs.js:25` — `STAIR_HALF_WIDTH = 0.17`.
        public let halfWidth: Double
        /// `site/stairs.js:47` — `STEP_HALF_HEIGHT = 0.10`.
        public let halfHeight: Double
        /// The inner face of the arena, metres from the middle in x and in y.
        /// `sim/scene_physics.xml:184-195`: four `wall_*` box geoms of half
        /// size 0.05 at ±1.5, so the face a body meets is at ±1.45.
        public let arenaInner: Double
        /// How tall those walls stand, metres. Same four geoms: half height
        /// 0.125 at z = 0.125, so the top is 0.25.
        public let wallHeight: Double

        public init(count: Int, y: Double, halfDepth: Double, halfWidth: Double,
                    halfHeight: Double, arenaInner: Double, wallHeight: Double) {
            self.count = count; self.y = y
            self.halfDepth = halfDepth; self.halfWidth = halfWidth
            self.halfHeight = halfHeight
            self.arenaInner = arenaInner; self.wallHeight = wallHeight
        }

        /// The bank in `scene.mjb`, the plant every published number on this
        /// bench was measured in.
        public static let pinned = Bank(count: 14, y: 1.305,
                                        halfDepth: 0.17, halfWidth: 0.17,
                                        halfHeight: 0.10,
                                        arenaInner: 1.45, wallHeight: 0.25)

        /// A run longer than this leaves daylight between the treads, because
        /// two blocks only overlap while the run is under twice the half depth.
        public var solidRunCeiling: Double { 2 * halfDepth }

        /// Why every step comes back at the same `y`, whatever was asked for.
        public var yWhy: String {
            String(format: "The step blocks are compiled at y = %.3f m with an x and a z slide "
                         + "and no y joint, so a staircase always stands that far to the duck's "
                         + "left. Moving it means recompiling the scene, which changes the "
                         + "plant's digest and detaches every published number from it.", y)
        }

        /// Why every step comes back the same size.
        public var sizeWhy: String {
            String(format: "Every block in the bank is %.0f × %.0f × %.0f mm and there is no "
                         + "joint that resizes one. A step of another size is a different "
                         + "scene file, not a different request.",
                   halfDepth * 2000, halfWidth * 2000, halfHeight * 2000)
        }

        /// The outer edge of a tread, in y, against the wall it is nearest.
        /// Positive means the tread is buried in `wall_n` by that much.
        public var treadInsideTheWall: Double { (y + halfWidth) - arenaInner }
    }

    /// The ball's radius, metres. `sim/scene_physics.xml:200` — `ball_geom`,
    /// a sphere of size 0.05, 30 g, `condim` 6 so a rolling ball decelerates.
    ///
    /// IT IS HERE BECAUSE THE ARENA REFUSAL NEEDS IT. The bench checks
    /// `|x| + BALL_RADIUS > inner`, not the centre: a ball at 1.43 m has 30 mm
    /// of itself inside `wall_e`. A kit that checked the centre would send a
    /// request the bench refuses, which is the round trip `plan` exists to
    /// avoid.
    public static let ballRadius = 0.05

    // MARK: - the four walls, which are not drawn

    /// One of the arena's four static walls, as the bench reports it.
    ///
    /// THEY HAVE NO JOINTS AND NO REQUEST TOUCHES THEM. They are here so a
    /// screen can say what is around the duck, and `arenaIsNotDrawn` is the
    /// sentence that admits the stage does not show them.
    public struct Wall: Equatable, Sendable, Identifiable {
        public let name: String
        public let x: Double
        public let y: Double
        public let halfThickness: Double
        public let height: Double
        public let halfLength: Double
        /// The axis the wall runs along, as the bench says it: "x" or "y".
        public let along: String
        public var id: String { name }

        public init(name: String, x: Double, y: Double, halfThickness: Double,
                    height: Double, halfLength: Double, along: String) {
            self.name = name; self.x = x; self.y = y
            self.halfThickness = halfThickness; self.height = height
            self.halfLength = halfLength; self.along = along
        }
    }

    /// The room the world is in.
    public struct Arena: Equatable, Sendable {
        public let walls: [Wall]
        public let innerX: Double
        public let innerY: Double
        /// The bench's own sentence about why the box is this size, when it
        /// sends one.
        public let why: String?

        public init(walls: [Wall], innerX: Double, innerY: Double, why: String? = nil) {
            self.walls = walls; self.innerX = innerX; self.innerY = innerY; self.why = why
        }

        /// The arena the pinned bank stands in.
        public static let pinned = Arena(
            walls: [
                Wall(name: "wall_n", x: 0, y: 1.5, halfThickness: 0.05,
                     height: 0.25, halfLength: 1.55, along: "x"),
                Wall(name: "wall_s", x: 0, y: -1.5, halfThickness: 0.05,
                     height: 0.25, halfLength: 1.55, along: "x"),
                Wall(name: "wall_e", x: 1.5, y: 0, halfThickness: 0.05,
                     height: 0.25, halfLength: 1.55, along: "y"),
                Wall(name: "wall_w", x: -1.5, y: 0, halfThickness: 0.05,
                     height: 0.25, halfLength: 1.55, along: "y"),
            ],
            innerX: 1.45, innerY: 1.45)

        /// Which wall a footprint at this x would cross, by the bench's own
        /// name for it. Nil when it crosses nothing.
        public func wallCrossed(byX x: Double) -> String {
            x > 0 ? "wall_e" : "wall_w"
        }
    }

    // MARK: - what a request could not say

    /// One clause of a scene the bank could not express, with the reason.
    ///
    /// EVERY FIELD IS OPTIONAL EXCEPT THE TWO THAT MAKE IT A FACT. A note about
    /// the whole flight has no index; a note about a step's height has all
    /// five. The alternative — one sentence per case, written where it is
    /// produced — is exactly the shape that let a caption claim "bare floor"
    /// over a scene full of props, so the sentence is composed here and asserted
    /// by `swift test`.
    public struct Unexpressed: Equatable, Sendable, Identifiable {
        /// The bench's own word for what this is about: "step", "wall", "prop",
        /// "ball", "flight". A word this app has never heard of still prints,
        /// because a bench is allowed to know something this build does not.
        public let what: String
        /// Which one, counting from zero in the order they were asked for.
        public let index: Int?
        /// Which part of it — "y", "size", "halfHeight".
        public let field: String?
        /// What the scene said, already written for a reader.
        public let asked: String?
        /// What the world has instead.
        public let got: String?
        public let why: String

        public var id: String {
            "\(what)|\(index.map(String.init) ?? "-")|\(field ?? "-")|\(why)"
        }

        public init(what: String, index: Int? = nil, field: String? = nil,
                    asked: String? = nil, got: String? = nil, why: String) {
            self.what = what; self.index = index; self.field = field
            self.asked = asked; self.got = got; self.why = why
        }

        /// The line under the picker.
        ///
        /// ONE-BASED IN THE SENTENCE, ZERO-BASED IN THE FIELD. The index is the
        /// request's own array position because that is what a bench can send
        /// back without agreeing on a convention; a person counting steps on a
        /// screen starts at one.
        ///
        /// THE FIELD IS NOT REPEATED WHEN THE BENCH ALREADY SAID IT. The live
        /// bench spells these as `what: "step y", field: "y"` and
        /// `what: "step size", field: "halfHeight"` — a two-word subject that
        /// has already named the part. Appending the field to that produces
        /// "Step 1 y's y", which reads as two different things going wrong.
        /// So a multi-word `what` keeps its own words and a single-word one
        /// takes the field: "Step 1 y" and "Prop 2's name" both come out of
        /// this, and both are sentences.
        ///
        /// The index goes after the FIRST word, because "Step 1 y" is a step
        /// and "Step y 1" is nothing.
        public var subject: String {
            let words = what.split(separator: " ")
            var subject: String
            if let first = words.first {
                subject = first.prefix(1).uppercased() + first.dropFirst()
                if let index { subject += " \(index + 1)" }
                if words.count > 1 {
                    subject += " " + words.dropFirst().joined(separator: " ")
                } else if let field {
                    subject += "'s \(field)"
                }
            } else {
                subject = "Something"
            }
            return subject
        }

        /// Whether this note carries numbers of its own. One that does is said
        /// on its own line; one that does not can share a line with the
        /// others that were turned away for the same reason.
        public var hasNumbers: Bool { asked != nil || got != nil }

        public var says: String {
            var head = subject
            if let asked, let got {
                head += ": asked for \(asked), got \(got)."
            } else if let got {
                head += ": \(got)."
            } else if let asked {
                head += ": asked for \(asked)."
            } else {
                head += "."
            }
            return why.isEmpty ? head : head + " " + why
        }
    }

    // MARK: - a prop, seated on a body that exists

    /// A graspable the bench moved, by the LITERAL body name it has in the
    /// plant.
    ///
    /// THE NAME IS THE MODEL'S, NOT THE SCENE'S. A scene calls it "Block"; the
    /// world calls it `block_a`, and the mass that decides whether it can be
    /// dragged is the model's. Printing the scene's word over the model's mass
    /// would be two different objects in one row.
    public struct Seated: Equatable, Sendable, Identifiable {
        public let name: String
        public let x: Double
        public let y: Double
        /// What the model says it weighs. Nil when the bench did not say.
        public let kilograms: Double?
        public var id: String { name }

        public init(name: String, x: Double, y: Double, kilograms: Double? = nil) {
            self.name = name; self.x = x; self.y = y; self.kilograms = kilograms
        }
    }

    /// Somewhere on the floor, metres, in the duck's frame.
    public struct Point: Equatable, Sendable {
        public let x: Double
        public let y: Double
        /// Metres up. A request never carries one — the bench puts the ball on
        /// the floor at its own radius — and a readback always does.
        public let z: Double

        public init(x: Double, y: Double, z: Double = 0) {
            self.x = x; self.y = y; self.z = z
        }
    }

    // MARK: - the world itself

    /// False when the bench is standing in the world it booted in — the one
    /// every published number was measured in. NOT the same as "empty": an
    /// unset world has fourteen blocks stacked at (0, 1.305) in it.
    public let isSet: Bool
    /// What the person called it, when they set one.
    public let name: String?
    /// The steps as the bench actually laid them, in the drawing frame.
    public let steps: [DuckIntentClip.Environment.Step]
    /// Where the ball is now. Never nil on a bench that has one, because the
    /// ball is a permanent body and no request can remove it.
    public let ball: Point?
    public let ballRadius: Double?
    public let props: [Seated]
    public let unexpressed: [Unexpressed]
    public let bank: Bank
    public let arena: Arena
    public let plantName: String?
    public let plantDigest: String?

    public init(isSet: Bool, name: String?,
                steps: [DuckIntentClip.Environment.Step],
                ball: Point?, ballRadius: Double? = nil,
                props: [Seated] = [], unexpressed: [Unexpressed] = [],
                bank: Bank = .pinned, arena: Arena = .pinned,
                plantName: String? = nil, plantDigest: String? = nil) {
        self.isSet = isSet; self.name = name; self.steps = steps
        self.ball = ball; self.ballRadius = ballRadius
        self.props = props; self.unexpressed = unexpressed
        self.bank = bank; self.arena = arena
        self.plantName = plantName; self.plantDigest = plantDigest
    }

    // MARK: - what the stage draws

    /// The readback as a renderer's world.
    ///
    /// NO WALLS, AND THAT IS DELIBERATE RATHER THAN MISSING.
    /// `DuckIntentClip.Environment.Wall` has no orientation and the one stage
    /// that draws walls runs them along x only, so the arena's four walls would
    /// come out as four bars across the room in the wrong two places. A picture
    /// that is wrong is worse than a picture that is absent, so the arena is
    /// left out and `arenaIsNotDrawn` says so under the stage.
    public var asEnvironment: DuckIntentClip.Environment {
        DuckIntentClip.Environment(ground: true, yaw: 0, steps: steps, walls: [])
    }

    /// The readback's movable bodies, as the props a stage already knows how to
    /// draw.
    ///
    /// THE MASS IS THE MODEL'S AND THE SIZE IS THIS APP'S. `GET /world` reports
    /// a name, a place and a mass; it does not report a shape, because the
    /// shape is in the MJCF and nothing needs it to run. So the drawing picks
    /// one from the body's name and the caption never claims it measured it.
    /// What a camera has to hold to drive in this world: the duck and the
    /// first riser, by the same solve the editor frames a challenge scene
    /// with. Nil for a world nobody set, and nil for one with no step
    /// standing above the floor, which the stage frames as it always has.
    ///
    /// THE BENCH'S OWN WORLD IS NOT A FLIGHT. Its fourteen blocks boot
    /// stacked inside each other and read back scattered from eleven metres
    /// under the floor to a metre and a half above it (measured on the Pi
    /// bench, 2026-09-02). Framing those put the camera nineteen metres from
    /// a point six metres underground and the Control tab went black. A
    /// world somebody asked for has its steps where it laid them; only those
    /// are worth pointing a camera at, and only the ones above the floor.
    public var framing: DuckScene.Framing? {
        guard isSet else { return nil }
        let standing = steps.filter { $0.top > 0 }
        guard !standing.isEmpty else { return nil }
        let scene = DuckScene(name: name ?? "world",
                              steps: standing.map { DuckScene.Step(x: $0.x, y: $0.y, top: $0.top,
                                                                   halfDepth: $0.halfDepth,
                                                                   halfWidth: $0.halfWidth,
                                                                   halfHeight: $0.halfHeight) },
                              walls: [], provenance: "")
        return scene.authoringFraming
    }

    public var asProps: [DuckScene.Prop] {
        var drawn: [DuckScene.Prop] = []
        if let ball {
            drawn.append(DuckScene.ball(x: ball.x, y: ball.y))
        }
        for seated in props {
            drawn.append(DuckWorld.drawn(seated))
        }
        return drawn
    }

    /// One seated body, as something to draw.
    static func drawn(_ seated: Seated) -> DuckScene.Prop {
        let grams = (seated.kilograms ?? 0) * 1000
        let lower = seated.name.lowercased()
        if lower.hasPrefix("ball") {
            return DuckScene.Prop(name: seated.name, shape: .ball,
                                  x: seated.x, y: seated.y, grams: grams,
                                  thicknessMillimetres: 100, length: 0.1,
                                  floorFriction: 0.4)
        }
        if lower.hasPrefix("cone") {
            // A capsule in the plant. There is no capsule in the drawing
            // vocabulary, and a rod is the nearer of the two shapes there are.
            return DuckScene.Prop(name: seated.name, shape: .rod,
                                  x: seated.x, y: seated.y, grams: grams,
                                  thicknessMillimetres: 32, length: 0.076,
                                  floorFriction: 0.8)
        }
        return DuckScene.Prop(name: seated.name, shape: .block,
                              x: seated.x, y: seated.y, grams: grams,
                              thicknessMillimetres: 40, length: 0.04,
                              floorFriction: 0.9)
    }

    // MARK: - seating a scene's prop on a body the world has

    /// Which body in the plant a scene's prop should be moved onto, or nil when
    /// this world has nothing that could be it.
    ///
    /// A PREFIX MATCH, CASE-INSENSITIVE, AND NOTHING CLEVERER. "Block" seats on
    /// `block_a`; "Broom" seats on nothing, because `scene.mjb` has no broom and
    /// pretending a 600 g broom is a 30 g cube would be the app answering its
    /// own question. Fuzzier matching is the failure this refuses: a "Pencil"
    /// quietly landing on `cone_b` produces a run whose whole subject is the
    /// wrong object.
    public static func seat(_ prop: DuckScene.Prop,
                            among graspables: [DuckBench.Health.Graspable]) -> String? {
        let wanted = prop.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !wanted.isEmpty else { return nil }
        return graspables.first { $0.name.lowercased().hasPrefix(wanted) }?.name
    }

    // MARK: - what cannot be sent at all

    /// A scene the bank cannot be asked for, whatever it does with the rest.
    ///
    /// THESE ARE REFUSALS AND NOT NOTES, and the line between the two is
    /// whether the world would end up wrong or merely smaller. A 250 mm step
    /// arrives as a 200 mm step and the person can see that it did; a step
    /// pushed through `wall_e` arrives as a 200 kg block interpenetrating a
    /// static wall, which is a physics engine being asked a question with no
    /// answer.
    public enum Refusal: Error, Equatable, Sendable {
        case tooManySteps(asked: Int, bank: Int)
        case stepCrossesTheArena(index: Int, face: Double, wall: String, inner: Double)
        case ballOutsideTheArena(x: Double, y: Double, inner: Double, radius: Double)

        public var message: String {
            switch self {
            case .tooManySteps(let asked, let bank):
                return "That scene has \(asked) steps and this world has \(bank) blocks. "
                     + "The bank is compiled into the plant; there is no fifteenth block to "
                     + "lay, and laying fourteen of fifteen would be a flight with its top "
                     + "step missing and nothing saying so."
            case .stepCrossesTheArena(let index, let face, let wall, let inner):
                return String(format: "Step %d reaches %.0f mm along x, past the %@ face at "
                                    + "%.0f mm. A 200 kg block pushed into a static wall is a "
                                    + "contact the solver has no answer for, so the flight is "
                                    + "refused rather than laid.",
                              index + 1, face * 1000, wall, inner * 1000)
            case .ballOutsideTheArena(let x, let y, let inner, let radius):
                return String(format: "The ball would be at (%.2f, %.2f) m, and with a %.0f mm "
                                    + "radius that puts some of it past the arena's inner faces "
                                    + "at ±%.2f m. It would be placed on the far side of a wall "
                                    + "the duck cannot get through.",
                              x, y, radius * 1000, inner)
            }
        }
    }

    // MARK: - the pre-flight prediction

    /// One block, as the request writes it: the centre in x and the height of
    /// its upper face.
    public struct Placed: Equatable, Sendable {
        public let x: Double
        public let top: Double
        public init(x: Double, top: Double) { self.x = x; self.top = top }
    }

    /// One prop move, by the literal body name the bench walked.
    public struct Requested: Equatable, Sendable {
        public let name: String
        public let x: Double
        public let y: Double
        public init(name: String, x: Double, y: Double) {
            self.name = name; self.x = x; self.y = y
        }
    }

    /// A scene, turned into the request the bench takes and the warnings that
    /// go with it.
    ///
    /// THE BENCH'S ANSWER ALWAYS WINS. This is here so a picker can say "that
    /// staircase will come back 200 mm tall and 1.3 m to your left" BEFORE the
    /// round trip, not so a screen can skip reading the readback. `predicted`
    /// and the `unexpressed` that comes back are the same shape on purpose:
    /// when they differ, the bench is right and this file is out of date.
    public struct Plan: Equatable, Sendable {
        public let name: String?
        /// `clear: true` PARKS THE BANK AND IS MUTUALLY EXCLUSIVE WITH `steps`.
        /// The bench refuses a body carrying both — "say one or the other" —
        /// because a request that clears and lays is two intentions with no
        /// order between them.
        public let clear: Bool
        /// The blocks to lay, or nil for "do not mention the bank".
        ///
        /// THREE STATES, BECAUSE THE BENCH HAS THREE. `[]` is a bare floor said
        /// with the steps key; `clear: true` is a bare floor said with the
        /// clear key; and ABSENT means leave the bank exactly where it is,
        /// which is the only way to move the ball without changing the flight.
        /// A bench with no world standing yet refuses the absent form in its
        /// own words — it boots with fourteen blocks stacked and will not
        /// silently park or silently pin them — and that refusal is the right
        /// answer rather than something to work around.
        public let steps: [Placed]?
        public let ball: Point?
        public let props: [Requested]
        /// The walls the scene drew, described for a reader.
        ///
        /// SENT TO BE REFUSED, ON PURPOSE. This world has exactly four static
        /// walls and cannot be given a fifth, and the bench answers a `walls`
        /// entry with an `unexpressed` row naming the four it has. Sending them
        /// is what puts that row in the READBACK — the list the screen draws —
        /// rather than only in this plan's prediction, which a screen may not
        /// be showing by the time the answer arrives.
        public let walls: [String]
        public let predicted: [Unexpressed]
        public let refusals: [Refusal]

        public var isSendable: Bool { refusals.isEmpty }

        public init(name: String?, clear: Bool = false, steps: [Placed]? = nil,
                    ball: Point? = nil, props: [Requested] = [], walls: [String] = [],
                    predicted: [Unexpressed] = [], refusals: [Refusal] = []) {
            self.name = name; self.clear = clear; self.steps = steps
            self.ball = ball; self.props = props; self.walls = walls
            self.predicted = predicted; self.refusals = refusals
        }

        /// Park the whole bank and leave everything else where it is.
        public static func bareFloor(named name: String = "Bare floor") -> Plan {
            Plan(name: name, clear: true)
        }

        /// Put the ball somewhere and touch nothing else.
        ///
        /// THE ONE REQUEST THAT SAYS NOTHING ABOUT THE BANK. A plan built from
        /// a scene always names its steps, which means a scene with none parks
        /// them; this is the picker entry that moves the ball in whatever world
        /// is already standing. On a bench with no world set the bench refuses
        /// it and says why, which is the honest answer — the bank is stacked
        /// there and both parking it and pinning it are decisions.
        public static func moveTheBall(to place: Point,
                                       named name: String? = nil) -> Plan {
            Plan(name: name, ball: place,
                 refusals: abs(place.x) + DuckWorld.ballRadius > Bank.pinned.arenaInner
                        || abs(place.y) + DuckWorld.ballRadius > Bank.pinned.arenaInner
                     ? [.ballOutsideTheArena(x: place.x, y: place.y,
                                             inner: Bank.pinned.arenaInner,
                                             radius: DuckWorld.ballRadius)]
                     : [])
        }
    }

    /// What this scene would become on that bank.
    ///
    /// `graspables` DEFAULTS TO EMPTY AND THAT MEANS "NOT KNOWN", NOT "NONE".
    /// With no list from `/health` this predicts nothing about props at all,
    /// because the alternative is telling somebody their broom will not fit in
    /// a world nobody has asked what it contains.
    public static func plan(for scene: DuckScene, on bank: Bank,
                            graspables: [DuckBench.Health.Graspable] = []) -> Plan {
        var placed: [Placed] = []
        var notes: [Unexpressed] = []
        var refusals: [Refusal] = []

        if scene.steps.count > bank.count {
            refusals.append(.tooManySteps(asked: scene.steps.count, bank: bank.count))
        }

        for (i, step) in scene.steps.enumerated() {
            placed.append(Placed(x: step.x, top: step.top))

            let far = step.x + bank.halfDepth
            let near = step.x - bank.halfDepth
            if far > bank.arenaInner {
                refusals.append(.stepCrossesTheArena(index: i, face: far,
                                                     wall: "wall_e", inner: bank.arenaInner))
            } else if near < -bank.arenaInner {
                refusals.append(.stepCrossesTheArena(index: i, face: near,
                                                     wall: "wall_w", inner: -bank.arenaInner))
            }

            if step.y != bank.y {
                notes.append(Unexpressed(
                    what: "step", index: i, field: "y",
                    asked: metres(step.y), got: metres(bank.y),
                    why: bank.yWhy))
            }
            if step.halfDepth != bank.halfDepth || step.halfWidth != bank.halfWidth {
                notes.append(Unexpressed(
                    what: "step", index: i, field: "size",
                    asked: String(format: "%.0f × %.0f mm",
                                  step.halfDepth * 2000, step.halfWidth * 2000),
                    got: String(format: "%.0f × %.0f mm",
                                bank.halfDepth * 2000, bank.halfWidth * 2000),
                    why: bank.sizeWhy))
            }
            if step.halfHeight != bank.halfHeight {
                notes.append(Unexpressed(
                    what: "step", index: i, field: "halfHeight",
                    asked: millimetres(step.halfHeight), got: millimetres(bank.halfHeight),
                    why: bank.sizeWhy))
            }
        }

        // A FLIGHT WITH DAYLIGHT IN IT IS STILL LAID. The blocks go exactly
        // where they were asked for; they simply stop overlapping, and a duck
        // meets separate boxes rather than one staircase. That is a fact about
        // the drawing rather than a fault in the bank, so it is a note.
        //
        // ONE PER GAP, IN REQUEST ORDER, WHICH IS THE BENCH'S OWN SHAPE — same
        // `what`, same `field`, same index — so a prediction and the readback
        // that follows it can be read side by side.
        for i in 1..<max(scene.steps.count, 1) {
            let run = abs(scene.steps[i].x - scene.steps[i - 1].x)
            let gap = run - bank.solidRunCeiling
            guard gap > 1e-9 else { continue }
            notes.append(Unexpressed(
                what: "gap between steps", index: i, field: "x",
                asked: metres(run), got: metres(gap),   // the DAYLIGHT, not a substituted run
                why: String(format: "Blocks %.2f m deep laid %.2f m apart leave %.0f mm of "
                                  + "daylight: this is not a solid flight, and a foot that lands "
                                  + "in the gap falls to the floor.",
                            bank.solidRunCeiling, run, gap * 1000)))
        }

        var walls: [String] = []
        for wall in scene.walls {
            let described = String(format: "a wall at (%.2f, %.2f) m", wall.x, wall.y)
            walls.append(described)
            notes.append(Unexpressed(
                what: "wall",
                asked: described,
                got: "the arena's four, where they are",
                why: "The only walls in this world are wall_n, wall_s, wall_e and wall_w. They "
                   + "are static geoms with no joints, so nothing can move them and nothing can "
                   + "add a fifth."))
        }

        // A PROP THAT SEATS IS SENT AS THE BODY'S OWN NAME, AND ONE THAT DOES
        // NOT IS SENT ANYWAY, UNDER THE NAME THE SCENE GAVE IT. The bench
        // matches `props[].name` against the bodies it walked and answers an
        // unknown one with an `unexpressed` row listing the five it has —
        // which is a better sentence than this file could write, and it lands
        // in the readback where the screen is already looking. Dropping it here
        // would make the broom vanish silently, which is the failure this whole
        // type exists against.
        var requested: [Requested] = []
        for prop in scene.props where !prop.name.lowercased().hasPrefix("ball") {
            let body = graspables.isEmpty ? nil : seat(prop, among: graspables)
            requested.append(Requested(name: body ?? prop.name, x: prop.x, y: prop.y))
            if body == nil && !graspables.isEmpty {
                notes.append(Unexpressed(
                    what: "prop",
                    asked: prop.name,
                    got: "nothing in this world",
                    why: "This plant's movable bodies are "
                       + graspables.map(\.name).joined(separator: ", ")
                       + ". A prop is seated onto one of those, not built."))
            }
        }

        // THE BALL IS PERMANENT. There is no request that removes it, so a
        // scene with no ball in it still gets one, and the person is told
        // rather than left to wonder where it came from.
        let ballProp = scene.props.first { $0.name.lowercased().hasPrefix("ball") }
        var ball: Point? = nil
        if let ballProp {
            ball = Point(x: ballProp.x, y: ballProp.y)
            // THE FOOTPRINT, NOT THE CENTRE — the bench's own rule, and the
            // reason a ball at 1.43 m is refused rather than laid 30 mm inside
            // a wall.
            if abs(ballProp.x) + DuckWorld.ballRadius > bank.arenaInner
                || abs(ballProp.y) + DuckWorld.ballRadius > bank.arenaInner {
                refusals.append(.ballOutsideTheArena(x: ballProp.x, y: ballProp.y,
                                                     inner: bank.arenaInner,
                                                     radius: DuckWorld.ballRadius))
            }
        } else {
            notes.append(Unexpressed(
                what: "ball",
                got: "still where it was",
                why: "The ball is a permanent body on a freejoint. A request can move it and "
                   + "nothing can take it out, so this scene has one whether or not it drew one."))
        }

        // `clear` STAYS FALSE AND AN EMPTY SCENE SENDS `steps: []`, WHICH IS
        // THE OTHER LEGAL SPELLING OF A BARE FLOOR. The bench refuses a body
        // carrying both, and a scene is always saying what its steps are — even
        // when the answer is none. `Plan.bareFloor` is the spelling for the
        // picker entry that is only about parking the bank.
        return Plan(name: scene.name, clear: false,
                    steps: placed, ball: ball, props: requested, walls: walls,
                    predicted: notes, refusals: refusals)
    }

    static func metres(_ v: Double) -> String { String(format: "%.3f m", v) }
    static func millimetres(_ v: Double) -> String {
        String(format: "%.0f mm", v * 1000)
    }

    // MARK: - the sentences

    /// The first entry in the picker, and the only one that sends nothing.
    public static let benchOwnWorld =
        "The bench's own world, exactly as it booted. Every number this app has ever published "
      + "from a bench — a success rate, a climb, a chase — was measured in this one, so leaving "
      + "it alone is what makes a run here comparable with a run there."

    /// What choosing an empty floor actually does, which is not nothing.
    ///
    /// THIS IS THE SENTENCE THE WHOLE FEATURE OWES SOMEBODY. Nothing in the
    /// live lane has ever parked the bank, so the world a person drives in has
    /// fourteen 200 kg blocks stacked on top of each other at (0, 1.305) from
    /// the moment it boots — hundreds of contacts a tick that every live
    /// trajectory has always had in it. Parking them removes those contacts.
    /// It invalidates nothing published, because nothing published was measured
    /// in the live world; it does mean two drives in "the same" world are not
    /// the same world.
    public static let bareFloorIsAChange =
        "Bare floor is a change, not a reset. The fourteen step blocks boot stacked on top of "
      + "each other beside the duck and have never been parked in the live world, so they have "
      + "been colliding under every drive this app has ever done. Parking them takes those "
      + "contacts out. Nothing published moves — the recordings and the challenge runs each "
      + "build their own world — but a drive before and a drive after are not the same physics."

    /// A bench that does not have the route.
    /// The picture on a bench without /world is not a readback: say so.
    public static let floorIsNotAReadback =
        "This floor is not a readback. The bench's own fourteen blocks stand stacked where it "
      + "booted them, and nothing here can show that."

    public static let noWorldRoute =
        "This bench cannot change its world. It is running a build without a /world route, so "
      + "everything here stands in whatever it booted in — which is the bench's own world, and "
      + "is what every published number ran in anyway."

    /// Why the four walls are not on the stage.
    public static let arenaIsNotDrawn =
        "The arena is not drawn. There are four walls around this world, 1.45 m out and 250 mm "
      + "tall, and the duck will hit them; the stage draws walls along one axis only, so drawing "
      + "these would put two of them in the wrong place. They are real and they are not in the "
      + "picture."

    /// The heading over the list of things the bank could not say, or nil when
    /// it said all of them.
    public static func couldNotExpress(_ items: [Unexpressed]) -> String? {
        guard !items.isEmpty else { return nil }
        if items.count == 1 {
            return "One thing in that scene this world cannot say:"
        }
        return "\(items.count) things in that scene this world cannot say:"
    }

    /// What `/reset` does to a world somebody built.
    ///
    /// IT HAD TO BE MADE TRUE FIRST. `/reset` is `mj_resetData`, which puts
    /// every slide back to its compiled `qpos0` — so a reset used to lose the
    /// whole layout and drop the bank back into its stack, silently. The bench
    /// re-lays the standing world after the reset; this is the sentence that
    /// tells somebody so before they press it.
    /// The notes as footnote lines, ONE LINE PER REASON where the reason is
    /// shared. Fourteen steps refused for the same bank produce "Step 5, step 6
    /// and step 7. <why>" once, not fourteen sentences that differ by a digit;
    /// a note with numbers of its own (asked for X, got Y) keeps its own line
    /// because the numbers are the point of it. Order is the order given.
    public static func groupedSayings(_ items: [Unexpressed]) -> [String] {
        var lines: [String] = []
        var sharedOrder: [String] = []
        var shared: [String: [Unexpressed]] = [:]
        for item in items {
            if item.hasNumbers {
                lines.append(item.says)
                continue
            }
            if shared[item.why] == nil { sharedOrder.append(item.why) }
            shared[item.why, default: []].append(item)
        }
        for why in sharedOrder {
            guard let group = shared[why], !group.isEmpty else { continue }
            if group.count == 1 {
                lines.append(group[0].says)
                continue
            }
            let subjects = group.map(\.subject)
            let lowered = subjects.dropFirst().map { $0.prefix(1).lowercased() + $0.dropFirst() }
            let head = ([subjects[0]] + lowered.dropLast()).joined(separator: ", ")
                     + " and " + lowered.last! + "."
            lines.append(why.isEmpty ? head : head + " " + why)
        }
        return lines
    }

    public static let resetKeepsTheWorld =
        "Reset puts the duck back on its feet and leaves this world standing. The reset itself "
      + "wipes the whole scene — it is the physics engine's own, and it returns every block to "
      + "where the file compiled it — so the bench lays your steps and your ball again "
      + "immediately afterwards."

    /// THE CHANGE IS ONE-WAY. Nothing can put back the stacked bank the bench
    /// booted with: the blocks are 200 kg bodies on frictionless slides and
    /// the only thing that knows where they stood is the compiled file.
    public static let oneWayUntilRestart =
        "Changing the world is one-way until the bench restarts. Nothing can put the fourteen "
      + "blocks back where the bench booted them; the bench's own world is the one every live "
      + "number was measured in, and it is gone the moment a world is set."

    /// The ball row's rule, said before the wire refuses it: a first world has
    /// to say what the bank should do, so the ball cannot be the first thing
    /// asked for.
    public static let ballNeedsAWorld =
        "Pick a floor or a flight first. The bench refuses a first world that says nothing about "
      + "its step bank, so the ball can be moved once a world is standing and not before."
}
