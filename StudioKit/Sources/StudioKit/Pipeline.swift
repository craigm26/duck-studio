import Foundation
import DuckKit

/// What actually happened to a motion on its way from a sentence to a robot.
///
/// THE STAGES EXIST WHETHER OR NOT ANYTHING SHOWS THEM, and until now nothing
/// did: a draft could be written, previewed on a phone that has no physics, run
/// on a real engine across the room, and end up carrying no memory of any of it.
/// Somebody opening it a week later saw keyframes and a name. This is the
/// memory — every stage says what it is, whether it happened, and what happens
/// next.
///
/// IT ALSO REFUSES TO FLATTER. A preview on the phone is NOT a simulation: an
/// iPhone has no MuJoCo, so what it draws is what you asked for, not what the
/// robot would do. The pipeline keeps those two apart because collapsing them
/// is how an app ends up implying a motion works when nothing has run it.
public struct Pipeline: Equatable, Sendable {

    /// One real physics run, kept with the draft that caused it.
    public struct BenchOutcome: Codable, Equatable, Sendable {
        /// Wall-clock, when it ran.
        public var when: Date
        /// What answered — the bench's own version string.
        public var bench: String
        /// Which plant it ran against, as the bench named it — a filename like
        /// `scene.mjb`. The rollers scene and the legs scene are different
        /// robots and a result from one is not a result for the other.
        ///
        /// OPTIONAL, AND ITS ABSENCE IS THE HONEST STATE. This field replaces a
        /// non-Optional `plant` that every stored outcome carried and no bench
        /// ever filled: `/perform` did not report a plant, so the app wrote the
        /// literal string "the bench's own plant" at the call site and the
        /// screen printed it as though it were a fact about a world. Dropping
        /// the old key rather than migrating it is deliberate — there is
        /// nothing in it to migrate, and a fabricated value carried forward is
        /// still fabricated.
        ///
        /// IT MUST STAY OPTIONAL WITH NO DEFAULT. A non-Optional stored
        /// property with a default does NOT decode when its key is missing;
        /// synthesised `Decodable` throws `keyNotFound` regardless of the
        /// default, and `DraftStore.reload` decodes each file inside
        /// `compactMap { try? … }` — so a throw here is not an error message,
        /// it is every older draft silently vanishing from the list.
        public var plantName: String?
        /// sha256 of the plant file's bytes, hex, as the bench reported it.
        ///
        /// THE NAME ALONE WILL NOT DO. Two files called `scene.mjb` exist in
        /// the duck-sounds tree with the same size and different bytes, and one
        /// of them is four times stiffer in the solver than the other — so
        /// "ran on scene.mjb" does not identify a world. Also Optional: a bench
        /// old enough not to send it is not lying, it is silent, and the
        /// difference is a sentence rather than a crash.
        public var plantDigest: String?
        /// The policy the motion rode on.
        public var policy: String
        /// How many rollouts stood up, out of how many.
        public var achieves: Int
        public var rollouts: Int
        /// The bench's own words for what counts as success. Kept verbatim
        /// rather than reduced to a number, because "16 of 16" means nothing
        /// without it.
        public var criterion: String
        /// Median trunk height at the end, metres, if the bench reported one.
        public var medianHeight: Double?
        /// The fastest any joint was actually driven, rad/s.
        public var peakJointRate: Double?

        /// The world the bench READ BACK OUT OF ITS OWN JOINTS for this run,
        /// narrowed to the shape a draft can hold. Nil when the answer carried
        /// no `stood` block.
        ///
        /// OPTIONAL WITH NO DEFAULT, for the reason `plantName` states above:
        /// a non-Optional stored property with a default throws `keyNotFound`
        /// on every older draft, and `DraftStore.reload` decodes inside
        /// `compactMap { try? … }`, so a throw is not a message — it is every
        /// draft written before this build silently vanishing from the list.
        public var laid: Pipeline.LaidWorld?
        /// Whether this app ASKED for a world. Set by the caller.
        ///
        /// THERE IS NO FIELD ON THE WIRE FOR THIS, DELIBERATELY. A `/perform`
        /// answer with no world in the request is byte-identical to the one
        /// that route has always given — that is what keeps the bench's parity
        /// fixture frozen — so "nothing was asked" and "a bench too old to
        /// answer" arrive here as the same bytes. Only the caller knows which,
        /// and `worldStanding` is where the two are kept apart.
        public var askedForWorld: Bool?
        /// Why this run is not a score, when it is not: the route's own kit
        /// sentence, stored with the numbers it qualifies rather than derived
        /// at draw time. Optional with no default, like the two above, so a
        /// build-46 outcome decodes with nothing to say.
        public var routeNote: String?

        public init(when: Date, bench: String, plantName: String? = nil,
                    plantDigest: String? = nil, policy: String,
                    achieves: Int, rollouts: Int, criterion: String,
                    medianHeight: Double? = nil, peakJointRate: Double? = nil,
                    laid: Pipeline.LaidWorld? = nil, askedForWorld: Bool? = nil,
                    routeNote: String? = nil) {
            self.when = when; self.bench = bench
            self.plantName = plantName; self.plantDigest = plantDigest
            self.policy = policy; self.achieves = achieves; self.rollouts = rollouts
            self.criterion = criterion; self.medianHeight = medianHeight
            self.peakJointRate = peakJointRate
            self.laid = laid; self.askedForWorld = askedForWorld
            self.routeNote = routeNote
        }

        /// FOUR STATES, BECAUSE THERE ARE FOUR. Collapsing any two prints a
        /// sentence that is true of one and false of another: "the bench ran
        /// its own world" is a fact about a run nobody sent a world with, and
        /// a lie about one whose world the bench was too old to answer.
        public enum WorldStanding: Equatable, Sendable {
            /// Asked, and the bench read one back.
            case laid(Pipeline.LaidWorld)
            /// Did not ask: the plant as it booted.
            case benchsOwn
            /// Asked, and the answer carried no `stood`.
            case askedAndTheBenchDidNotSay
            /// Stored before the app kept this.
            case notRecorded
        }

        public var worldStanding: WorldStanding {
            switch (askedForWorld, laid) {
            case (_, .some(let world)):  return .laid(world)
            case (.some(true), .none):   return .askedAndTheBenchDidNotSay
            case (.some(false), .none):  return .benchsOwn
            case (.none, .none):         return .notRecorded
            }
        }

        /// Which world this ran in, in one sentence. See `DuckWorld.worldSaid`.
        public var worldSentence: String { DuckWorld.worldSaid(worldStanding) }

        /// Every rollout stood up.
        public var isClean: Bool { rollouts > 0 && achieves == rollouts }

        /// STAYING UP IS NOT THE SAME AS STANDING UP, and this is the
        /// difference. An authored bow measured on the bench keeps every one
        /// of eight rollouts upright and finishes at 0.091 m — twenty-five
        /// millimetres below the 0.116 m the standing policy holds on the same
        /// plant, and it does not recover in the half-second after the track
        /// returns home. The preview shows a clean return to standing, because
        /// a preview draws the request. A motion that ends in a crouch is not
        /// a failure, but nobody should find out from a robot.
        public var endedLow: Bool {
            guard let height = medianHeight else { return false }
            return height < Pipeline.standingHeight - 0.015
        }

        public var summary: String {
            var text = "\(achieves) of \(rollouts) — \(criterion)"
            if endedLow, let height = medianHeight {
                text += String(format: ". It ends %.0f mm below standing height.",
                               (Pipeline.standingHeight - height) * 1000)
            }
            return text
        }

        /// Which world this ran in, in one sentence, or that nothing recorded
        /// it. See `DuckBench.plantSaid` for why this is never a placeholder.
        public var plantSentence: String {
            DuckBench.plantSaid(name: plantName, digest: plantDigest)
        }

        /// The whole result in words: what happened, then which world it
        /// happened in. Composed here rather than in the view because all
        /// three halves make a claim, and the join between them is where a
        /// screen would otherwise stitch a measured number to an unmeasured
        /// world.
        public var told: String {
            let head = summary.hasSuffix(".") ? summary : summary + "."
            return head + " " + plantSentence + " " + worldSentence
        }
    }

    public enum State: Equatable, Sendable {
        /// Done, and nothing is wrong with it.
        case done
        /// Done, with something worth reading first.
        case attention
        /// Not done yet, and it can be.
        case waiting
        /// Cannot be done, for a reason that is not the person's fault.
        case blocked

        /// The state in words, for a screen reader.
        ///
        /// IT LIVES HERE BECAUSE THE SCREEN SAYS IT IN COLOUR. `PipelineView`
        /// draws a state as an SF Symbol tinted green, orange or grey, and
        /// colour and shape are exactly what a screen reader does not get — so
        /// the only place this stage's standing is stated for that person is a
        /// string, and a string that makes a claim about a stage belongs where
        /// a test can assert it rather than in a view.
        public var spoken: String {
            switch self {
            case .done:      return "done"
            case .attention: return "done, worth reading"
            case .waiting:   return "not done yet"
            case .blocked:   return "blocked"
            }
        }
    }

    public struct Stage: Equatable, Sendable, Identifiable {
        public let name: String
        public let state: State
        /// One line saying where this stands. Never "pending" — a stage that
        /// cannot explain itself is a progress bar.
        public let detail: String
        public var id: String { name }
    }

    /// What the trunk sits at when the standing policy is simply left alone,
    /// metres. MEASURED on the canon plant: `alpha_stand.onnx` over three
    /// seconds holds 0.1162 m from the first frame to the last. The model's
    /// nominal rest height is 0.12; this is what the policy actually does.
    public static let standingHeight = 0.116

    /// That baseline in words, to sit beside any result compared against it.
    ///
    /// IT NAMES THE PLANT IT WAS MEASURED ON INSTEAD OF SAYING "this plant".
    /// The screen used to say the latter, directly under a run whose world the
    /// app had never recorded — so "this plant" pointed at nothing, and the
    /// sentence read as a measurement of the world the motion had just run in.
    /// It is a measurement of the canon plant, and of no other.
    public static var standingHeightSaid: String {
        String(format: "Standing height is %.3f m — what the standing policy holds on "
                     + "scene.mjb, the canon plant, when it is simply left alone. A motion "
                     + "that ends much below that stayed up without standing up.",
               standingHeight)
    }

    /// Why the editor's Run asks for eight rollouts rather than one.
    ///
    /// LIFTED OUT OF A `Text(...)` LITERAL so a test can read it. It was the
    /// footnote under the Run button, which is exactly where a claim goes
    /// unasserted — and it carries a measured number.
    public static let eightRolloutsSaid =
        "Eight rollouts at different drop heights, because one that stays up proves very "
      + "little — the four authored stair motions in this app get up their flight 0 times in 16."

    public let stages: [Stage]

    /// The first stage that is not finished, which is what a screen should
    /// point at. Nil when everything possible has been done.
    public var next: Stage? {
        stages.first { $0.state == .waiting }
    }

    /// How far along, counting only stages that CAN be finished. A blocked
    /// stage is not progress withheld; it is a stage that does not exist yet,
    /// and counting it would leave every motion permanently at four fifths.
    public var fractionDone: Double {
        let countable = stages.filter { $0.state != .blocked }
        guard !countable.isEmpty else { return 0 }
        let done = countable.filter { $0.state == .done || $0.state == .attention }.count
        return Double(done) / Double(countable.count)
    }

    /// Work out where a draft stands.
    ///
    /// `hasBench` is whether a physics machine is configured at all — without
    /// one the simulate stage is waiting on the person, not on the draft.
    public static func of(_ draft: IntentDraft, bench: BenchOutcome? = nil,
                          hasBench: Bool = false,
                          isAttested: Bool = false) -> Pipeline {
        var stages: [Stage] = []

        stages.append(Stage(
            name: "Written",
            state: .done,
            detail: draft.provenance))

        let broken = draft.problems.filter { $0.severity == .broken }
        let impossible = draft.problems.filter { $0.severity == .impossible }
        let cautions = draft.problems.filter { $0.severity == .caution }
        if let first = broken.first {
            stages.append(Stage(name: "Checked", state: .waiting, detail: first.text))
        } else if let first = impossible.first {
            stages.append(Stage(name: "Checked", state: .attention, detail: first.text))
        } else if let first = cautions.first {
            stages.append(Stage(name: "Checked", state: .attention,
                                detail: cautions.count == 1 ? first.text
                                    : "\(cautions.count) things worth reading. \(first.text)"))
        } else {
            stages.append(Stage(name: "Checked", state: .done,
                                detail: "Every joint exists and every angle is inside its travel."))
        }

        // THE PREVIEW IS NOT THIS STAGE. A phone has no physics engine, so
        // what it drew was the request, not the outcome.
        if broken.isEmpty == false {
            stages.append(Stage(name: "Run in physics", state: .waiting,
                                detail: "Fix the draft first — a bench will not make a broken one work."))
        } else if let bench {
            stages.append(Stage(
                name: "Run in physics",
                state: bench.isClean && !bench.endedLow ? .done : .attention,
                detail: bench.told))
        } else if hasBench {
            stages.append(Stage(name: "Run in physics", state: .waiting,
                                detail: "Never run. The preview on this phone is what you asked "
                                      + "for, not what the robot would do — there is no physics "
                                      + "engine on an iPhone."))
        } else {
            stages.append(Stage(name: "Run in physics", state: .waiting,
                                detail: "No bench configured. Point the app at a machine on your "
                                      + "network running duckbench, and this becomes a real result."))
        }

        stages.append(Stage(
            name: "Attested",
            state: isAttested ? .done : (bench == nil ? .waiting : .waiting),
            detail: isAttested
                ? "Signed and chained, with the policy's fingerprint."
                : (bench == nil
                   ? "Nothing to attest yet. A signature over a motion nobody ran would certify "
                   + "the drawing, not the robot."
                   : "Ready to sign: there is a real run to attest.")))

        stages.append(Stage(
            name: "On the robot",
            state: .blocked,
            detail: "No hardware yet. The Microduck ships around Christmas 2026, and nothing in "
                  + "this app reaches a robot — there is no output channel, and saying otherwise "
                  + "would be the one lie this app cannot afford."))

        return Pipeline(stages: stages)
    }
}

extension IntentDraft {

    /// This draft as a track the bench can run.
    ///
    /// THE MOUTH COMES OUT, and that is the whole reason this is a tested
    /// function rather than a line in a view. A draft holds fifteen joints
    /// because the mouth is the one thing an author can drive and no policy
    /// can; the bench runs the fourteen the network commands. Sending fifteen
    /// shifts every joint after the mouth by one — the right leg would be
    /// driven by the left leg's neighbours — and the result would look like
    /// bad physics rather than bad indexing.
    public var benchTrack: [(at: Double, pose: [Double])] {
        keys.sorted { $0.time < $1.time }.compactMap { key in
            guard key.pose.count == DuckModel.jointCount else { return nil }
            var pose = key.pose
            pose.remove(at: DuckModel.mouthIndex)
            return (at: key.time, pose: pose)
        }
    }
}

// MARK: - the world a run actually stood in, as something a draft can hold

/// `DuckWorld` NEVER BECOMES `Codable`, and this is why there is a second type
/// at all.
///
/// A readback is a rich value: `Bank`, `Arena`, `Wall`, `Seated`, `Point` and
/// `Unexpressed`, every one of them a description of a bench that is free to
/// change. Dragging those into the on-disk draft format makes all six a
/// migration surface forever — a renamed field in a wall is a draft that no
/// longer decodes, and `DraftStore.reload` decodes inside
/// `compactMap { try? … }`, so that is a draft list that silently shortens.
/// So the stored shape is a NARROW PROJECTION whose nested types are all its
/// own, and `PipelineTests.testTheStoredWorldIsNarrowerThanTheReadback` pins
/// its coding keys against anybody quietly widening it back.
extension Pipeline {

    public struct LaidWorld: Codable, Equatable, Sendable {

        public struct Step: Codable, Equatable, Sendable {
            public var x, y, top, halfDepth, halfWidth, halfHeight: Double
            public init(x: Double, y: Double, top: Double,
                        halfDepth: Double, halfWidth: Double, halfHeight: Double) {
                self.x = x; self.y = y; self.top = top
                self.halfDepth = halfDepth; self.halfWidth = halfWidth
                self.halfHeight = halfHeight
            }
        }

        public struct Point: Codable, Equatable, Sendable {
            public var x, y, z: Double
            public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }
        }

        public struct Seated: Codable, Equatable, Sendable {
            public var name: String
            public var x, y: Double
            public var kilograms: Double?
            public init(name: String, x: Double, y: Double, kilograms: Double? = nil) {
                self.name = name; self.x = x; self.y = y; self.kilograms = kilograms
            }
        }

        /// One `unexpressed` row, flattened to strings — the shape the bench
        /// sends and a person reads, not a re-parse of it.
        public struct Note: Codable, Equatable, Sendable {
            public var what: String
            public var index: Int?
            public var field: String?
            public var asked: String?
            public var got: String?
            public var why: String
            public init(what: String, index: Int? = nil, field: String? = nil,
                        asked: String? = nil, got: String? = nil, why: String) {
                self.what = what; self.index = index; self.field = field
                self.asked = asked; self.got = got; self.why = why
            }
        }

        public var name: String?
        public var steps: [Step]
        public var ball: Point?
        public var props: [Seated]
        public var notes: [Note]
        public var bankCount: Int
        public var parked: Int
        public var spawn: Point?
        public var sagMillimetres: Double?
        public var plantName: String?
        public var plantDigest: String?

        /// EXACTLY THE ELEVEN STORED FIELDS. Everything below this line is
        /// computed from them, so nothing derived is ever written to disk and
        /// then trusted after the derivation changed.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case name, steps, ball, props, notes, bankCount, parked, spawn
            case sagMillimetres, plantName, plantDigest
        }

        public init(name: String?, steps: [Step], ball: Point?, props: [Seated],
                    notes: [Note], bankCount: Int, parked: Int, spawn: Point?,
                    sagMillimetres: Double?, plantName: String?, plantDigest: String?) {
            self.name = name; self.steps = steps; self.ball = ball
            self.props = props; self.notes = notes
            self.bankCount = bankCount; self.parked = parked
            self.spawn = spawn; self.sagMillimetres = sagMillimetres
            self.plantName = plantName; self.plantDigest = plantDigest
        }

        /// What a stage draws. Walls are left out for the reason
        /// `DuckWorld.asEnvironment` already states: the one stage that draws
        /// walls runs them along x only, and a picture that is wrong is worse
        /// than a picture that is absent.
        public var asEnvironment: DuckIntentClip.Environment {
            DuckIntentClip.Environment(
                ground: true, yaw: 0,
                steps: steps.map {
                    .init(x: $0.x, y: $0.y, top: $0.top, halfDepth: $0.halfDepth,
                          halfWidth: $0.halfWidth, halfHeight: $0.halfHeight)
                },
                walls: [])
        }

        /// The movable bodies, drawn by the one function that already knows
        /// which shape a body's name means.
        ///
        /// STABLE IDS, FOR THE REASON `DuckWorld.asProps` GIVES AT LENGTH. This
        /// is a reading of a world that was laid, not a set of objects anybody
        /// owns: laid twice, it has to come out the same, or a renderer that
        /// rebuilds only what changed rebuilds all of it on every frame. The
        /// seed is distinct from `DuckWorld`'s so a laid world and a read-back
        /// world are never mistaken for each other.
        public var asProps: [DuckScene.Prop] {
            var drawn: [DuckScene.Prop] = []
            if let ball {
                drawn.append(DuckScene.ball(x: ball.x, y: ball.y,
                                            id: DuckScene.Prop.derivedID("laid.ball")))
            }
            for (index, seated) in props.enumerated() {
                drawn.append(DuckWorld.drawn(DuckWorld.Seated(name: seated.name,
                                                              x: seated.x, y: seated.y,
                                                              kilograms: seated.kilograms),
                                             at: index, seed: "laid"))
            }
            return drawn
        }

        /// The notes as `DuckWorld.Unexpressed`, so `couldNotExpress` and
        /// `groupedSayings` are reused verbatim rather than reimplemented.
        public var unexpressed: [DuckWorld.Unexpressed] {
            notes.map {
                DuckWorld.Unexpressed(what: $0.what, index: $0.index, field: $0.field,
                                      asked: $0.asked, got: $0.got, why: $0.why)
            }
        }

        /// The `what == "spawn"` row, when a FLIGHT was laid and nothing said
        /// where the duck should stand. A cleared world with nothing standing
        /// has nothing to be beside, so its spawn row is not this note.
        public var noSpawnNote: DuckWorld.Unexpressed? {
            steps.isEmpty ? nil : unexpressed.first { $0.what == "spawn" }
        }

        /// True when any drawn tread's top exceeds twice its halfHeight — the
        /// harness's blocks are 200 mm and a higher tread really does float.
        /// The same test `DuckScene.problems` calls BROKEN, which is why
        /// `DuckWorld.blocksAreTwoHundredMillimetresTall` has to be printed
        /// beside the picture rather than the picture quietly thickened.
        public var aTreadFloats: Bool {
            steps.contains { $0.top - $0.halfHeight * 2 > 0.0005 }
        }

        /// Every block in the bank is parked below the floor for this run.
        public var wholeBankWasParked: Bool { bankCount > 0 && parked == bankCount }
    }

    /// A ONE-CELL `/climb` ANSWER, STORED BESIDE `bench` AND NEVER INSIDE IT.
    ///
    /// `BenchOutcome.summary` is "\(achieves) of \(rollouts) — \(criterion)".
    /// A climb cell has no rollouts, and coercing one into that type fabricates
    /// "1 of 1" — a number that reads like a score and is not one. Two answers,
    /// two types, and `told` on each says which run it is.
    public struct CellOutcome: Codable, Equatable, Sendable {
        public var when: Date
        /// `intentHash` — the identity the leaderboard is keyed by. Nil from a
        /// row this app built rather than received.
        public var hash: String?
        public var rise: Double
        public var cell: DuckBench.Cell
        public var honest, stable, reachedFlight, invalid: Bool
        public var uprightTailTicks, tailTicks: Int
        public var aboveMillimetres, peakAboveTreadMillimetres: Double
        public var why: String?
        public var criterion: String
        public var plantName: String?
        public var plantDigest: String?
        /// The world this cell's episode actually stood in, when a clip was
        /// asked for. Nil when it was not: `/climb` answers no `stood` without
        /// one, and inventing a flight from the request would be the whole bug
        /// this build exists to fix.
        public var laid: LaidWorld?

        public init(when: Date, hash: String? = nil, rise: Double, cell: DuckBench.Cell,
                    honest: Bool, stable: Bool, reachedFlight: Bool, invalid: Bool,
                    uprightTailTicks: Int, tailTicks: Int,
                    aboveMillimetres: Double, peakAboveTreadMillimetres: Double,
                    why: String? = nil, criterion: String,
                    plantName: String? = nil, plantDigest: String? = nil,
                    laid: LaidWorld? = nil) {
            self.when = when; self.hash = hash; self.rise = rise; self.cell = cell
            self.honest = honest; self.stable = stable
            self.reachedFlight = reachedFlight; self.invalid = invalid
            self.uprightTailTicks = uprightTailTicks; self.tailTicks = tailTicks
            self.aboveMillimetres = aboveMillimetres
            self.peakAboveTreadMillimetres = peakAboveTreadMillimetres
            self.why = why; self.criterion = criterion
            self.plantName = plantName; self.plantDigest = plantDigest
            self.laid = laid
        }

        /// One scored cell as the bench answered it, with the world its
        /// episode stood in when it sent one.
        public init(_ climbed: DuckBench.Climbed, when: Date) {
            self.init(when: when,
                      hash: climbed.hash.isEmpty ? nil : climbed.hash,
                      rise: climbed.rise, cell: climbed.cell,
                      honest: climbed.honest, stable: climbed.stable,
                      reachedFlight: climbed.reachedFlight, invalid: climbed.invalid,
                      uprightTailTicks: climbed.uprightTailTicks,
                      tailTicks: climbed.tailTicks,
                      aboveMillimetres: climbed.aboveMillimetres,
                      peakAboveTreadMillimetres: climbed.peakAboveTreadMillimetres,
                      why: climbed.why, criterion: climbed.criterion,
                      plantName: climbed.plantName, plantDigest: climbed.plantDigest,
                      laid: climbed.stood?.laid(spawn: nil, sagMillimetres: nil))
        }

        /// The whole cell in words: what it did, that one cell is not a score,
        /// and which plant it happened on.
        public var told: String {
            StairsChallenge.oneCellSaid(self) + " "
              + StairsChallenge.oneCellIsNotAScore + " "
              + DuckBench.plantSaid(name: plantName, digest: plantDigest)
        }
    }
}
