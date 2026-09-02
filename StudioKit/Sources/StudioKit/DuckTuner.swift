import Foundation
import DuckKit

/// Searching a per-joint residual on a bench, and being exact about what that
/// is and is not.
///
/// IT IS NOT TRAINING, AND THE WORD MATTERS MORE HERE THAN ANYWHERE ELSE IN THE
/// APP. Nothing below computes a gradient, touches a weight matrix's interior,
/// or sees a single frame of the data Pollen trained on. What it searches is
/// twenty-eight numbers — a multiplier and an additive trim on each of the
/// fourteen policy slots — and what it does with the winner is fold it into the
/// last layer of somebody else's trained network, which `DuckPolicyWriter.folding`
/// proves is exact arithmetic rather than a new network. A person who reads
/// "tuned" as "retrained" would be wrong about where the behaviour came from,
/// and would credit this app for a walk Pollen's optimiser found.
///
/// WHY A RESIDUAL AND NOT SOMETHING BIGGER. Because a residual is the only
/// thing that can reach a robot. robotd takes an ONNX pointed at by `[policy]`
/// and a handful of config keys; there is no hook for "and then multiply the
/// ninth output by 1.07", so a per-joint correction has exactly two fates — it
/// gets folded into the file, or it never leaves the phone. Everything larger
/// than a fold is a patch with a policy attached.
///
/// THE REWARD IS POLLEN'S OWN, READ FROM ONE PLACE. Six terms of
/// `microduck_velocity_env_cfg`, at the weights `RunMetrics.Task.velocity`
/// already reads out of that file for grading a clip. A search that optimised a
/// second transcription of those weights would be climbing a hill the rest of
/// the app cannot see, and both numbers would look plausible.
///
/// AND FIVE OF THE SIX PAY FOR STANDING STILL, WHICH IS MEASURED AND NOT
/// FEARED. `upright` is perfect when nothing moves, `pose` is perfect at home,
/// `action_rate_l2` and `body_ang_vel` are zero, and only the two tracking
/// terms object. `PolicyBlend` has the receipt from a different experiment — a
/// 75% blend scoring 16 of 16 on "ends standing" while travelling two
/// millimetres — and its `wentInertRatherThanFalling` check is reused here
/// verbatim rather than reimplemented, because the failure is the same failure.
///
/// WHAT THIS APP CANNOT DO TODAY, SAID BEFORE THE BUTTON RATHER THAN AFTER.
/// The bench's steering answers carry a position, a quaternion and fourteen
/// joint angles. They carry no velocity and no action. So a loop driven from
/// Swift over `/reset`, `/policy` and `/intent` can compute two of the six
/// terms — and both of those are terms a duck standing still maximises.
/// Measured on this project's own phone-bench build, six seconds at vx = 0.5,
/// 275 scored ticks:
///
///     alpha_walking   upright 0.9467  pose 0.6353  2·upright + pose = 2.5287  travelled 1231 mm
///     alpha_stand     upright 0.9991  pose 0.9830  2·upright + pose = 2.9812  travelled    1 mm
///
/// A search scored that way climbs 18% by stopping. That is why `Scoring`
/// exists, why `readiness` refuses, and why the screen ships as a stated
/// not-yet with the endpoint it needs named — rather than as a Start button
/// over a reward that rewards the wrong thing.
public enum DuckTuner {

    // MARK: - what is being searched

    /// Twenty-eight numbers: a multiplier and a trim on each policy slot.
    ///
    /// POLICY SLOTS, NOT JOINTS, AND THE DIFFERENCE IS THE MOUTH. The robot has
    /// fifteen joints and every alpha policy has fourteen outputs, because the
    /// mouth (`DuckModel.mouthIndex`) is absent from the action vector
    /// entirely. `DuckPolicyWriter.folding` is indexed the same way for the same
    /// reason, so a vector built here drops straight into it — and a fifteen-wide
    /// array is refused by name rather than silently shifting every joint past
    /// index 9 by one.
    public struct TuningVector: Equatable, Sendable {

        /// Per-slot multipliers on the network's own output.
        public let gain: [Double]
        /// Per-slot additive trims, in radians of RAW action — the number the
        /// runtime then multiplies by its own `action_scale`.
        public let offset: [Double]

        /// The envelope the search may move inside.
        ///
        /// ±30% ON A GAIN AND ±0.05 rad ON A TRIM, and neither is arbitrary.
        /// The gain range is the same 0.7–1.3 the training config randomises
        /// foot friction over (`Retrieval.Drag.footFriction`), which is the one
        /// multiplicative range in this family anybody has evidence about. The
        /// trim is about three degrees: enough to take a limp out of a stance,
        /// small enough that a fold cannot walk a joint into its stop from a
        /// pose the policy thought was safe.
        public static let gainLower = 0.7
        public static let gainUpper = 1.3
        public static let offsetLimit = 0.05

        /// Nothing changed — the network exactly as it was trained.
        public static let identity = TuningVector(
            gain: [Double](repeating: 1, count: DuckModel.policyJointCount),
            offset: [Double](repeating: 0, count: DuckModel.policyJointCount))

        /// UNCHECKED, AND ONLY REACHABLE FROM INSIDE. Every way in from outside
        /// goes through `checked`, which is where the widths and the bounds are
        /// enforced; this exists so `identity` and the mutator can build a
        /// vector they have already constrained without paying to re-prove it.
        init(gain: [Double], offset: [Double]) {
            self.gain = gain; self.offset = offset
        }

        public enum Refusal: Error, Equatable {
            case wrongWidth(field: String, was: Int)
            case notANumber(field: String)
            case outsideTheEnvelope(field: String, slot: Int, was: Double)

            public var message: String {
                switch self {
                case .wrongWidth(let field, let was):
                    return "The \(field) is \(was) wide, not \(DuckModel.policyJointCount). The "
                         + "mouth has no policy output, so a 15-joint array has to have index "
                         + "\(DuckModel.mouthIndex) — \(DuckModel.jointNames[DuckModel.mouthIndex]) "
                         + "— dropped before it gets here."
                case .notANumber(let field):
                    return "The \(field) holds something that is not a number. A fold is "
                         + "arithmetic on every weight in the last layer, and one NaN in it "
                         + "makes a file that loads and drives nothing."
                case .outsideTheEnvelope(let field, let slot, let was):
                    let name = DuckModel.jointNames[DuckModel.jointOfPolicySlot(slot)]
                    return "The \(field) for \(name) is \(trimmed(was)), outside what this "
                         + "search is allowed to try. Nothing here has measured what a duck "
                         + "does past that, and a fold does not ask before it is written."
                }
            }
        }

        /// The widest trim this slot may take: the flat envelope, or half the
        /// room the joint has between its home pose and the nearer of its two
        /// stops — whichever is smaller.
        ///
        /// THE MODEL AND NOT A TASTE. 0.05 rad is a number somebody chose; the
        /// distance from `left_hip_roll`'s home pose to its stop is a fact
        /// about a robot, and a trim that walked a joint into its travel limit
        /// would make a policy that presses against a stop for six seconds
        /// while every reward term reports something plausible. So the two are
        /// compared and the model wins.
        ///
        /// AND ON THIS ROBOT IT NEVER BINDS, WHICH IS WORTH SAYING RATHER THAN
        /// LEAVING TO BE ASSUMED. Computed over all fourteen slots from
        /// `DuckModel.homePose` and `DuckModel.jointRanges`, the tightest joint
        /// is the hip roll, with 0.2967 rad between home and its nearer stop —
        /// so its half-room is 0.1483, nearly three times the flat 0.05. Every
        /// other slot has more. The guard is slack today and is kept anyway: it
        /// costs nothing, and the thing it protects against is silent. Widen
        /// the envelope past 0.1483 and it starts doing work, which is exactly
        /// when it would be needed and exactly when nobody would think to add
        /// it.
        ///
        /// - Parameter within: the flat envelope to compare against. Defaulted,
        ///   and a parameter ONLY so a test can prove this rule is capable of
        ///   binding — a guard that has never been observed to fire is a guard
        ///   nobody has checked.
        public static func offsetLimit(forSlot slot: Int,
                                       within flat: Double = offsetLimit) -> Double {
            let joint = DuckModel.jointOfPolicySlot(slot)
            let range = DuckModel.jointRanges[joint]
            let home = DuckModel.homePose[joint]
            let room = min(range.upper - home, home - range.lower)
            return min(flat, max(room, 0) / 2)
        }

        /// The only way in from outside: widths, finiteness and bounds, in that
        /// order, each with the sentence that says which number was wrong.
        public static func checked(gain: [Double], offset: [Double]) throws -> TuningVector {
            let width = DuckModel.policyJointCount
            guard gain.count == width else {
                throw Refusal.wrongWidth(field: "gain", was: gain.count)
            }
            guard offset.count == width else {
                throw Refusal.wrongWidth(field: "trim", was: offset.count)
            }
            guard gain.allSatisfy(\.isFinite) else { throw Refusal.notANumber(field: "gain") }
            guard offset.allSatisfy(\.isFinite) else { throw Refusal.notANumber(field: "trim") }
            for slot in 0..<width {
                guard gain[slot] >= gainLower, gain[slot] <= gainUpper else {
                    throw Refusal.outsideTheEnvelope(field: "gain", slot: slot, was: gain[slot])
                }
                let limit = offsetLimit(forSlot: slot)
                guard abs(offset[slot]) <= limit + 1e-12 else {
                    throw Refusal.outsideTheEnvelope(field: "trim", slot: slot, was: offset[slot])
                }
            }
            return TuningVector(gain: gain, offset: offset)
        }

        /// The same vector, moved back inside the envelope rather than refused.
        ///
        /// FOR THE MUTATOR AND NOTHING ELSE. A search that threw away every
        /// child that stepped over a bound would sample the edges of the box
        /// less often than the middle, which is a bias nobody asked for; a
        /// search that clamped a number a PERSON typed would be quietly
        /// changing what they asked for. So the clamp is here and the refusal
        /// is in `checked`, and the two are not the same door.
        public func clamped() -> TuningVector {
            var g = gain, o = offset
            for slot in 0..<DuckModel.policyJointCount {
                g[slot] = min(max(g[slot].isFinite ? g[slot] : 1, Self.gainLower), Self.gainUpper)
                let limit = Self.offsetLimit(forSlot: slot)
                o[slot] = min(max(o[slot].isFinite ? o[slot] : 0, -limit), limit)
            }
            return TuningVector(gain: g, offset: o)
        }

        /// Whether this is the untouched network.
        public var isIdentity: Bool { self == Self.identity }

        /// The slots this vector actually moves, so a result can name them.
        public var changedSlots: [Int] {
            (0..<DuckModel.policyJointCount).filter {
                abs(gain[$0] - 1) > 1e-9 || abs(offset[$0]) > 1e-9
            }
        }

        /// The candidate as a network — the thing that would be written.
        ///
        /// FOLDED THROUGH DUCKKIT'S OWN WRITER AND READER, so what is scored is
        /// a `DuckPolicy` in the sense every other screen means it, not a
        /// struct assembled behind the loader's back. That is `folding`'s
        /// guarantee and this does not restate it.
        public func folded(into policy: DuckPolicy) throws -> DuckPolicy {
            try DuckPolicyWriter.folding(policy: policy, gain: gain, offset: offset)
        }

        /// One line per moved slot, for a receipt.
        public var described: String {
            let moved = changedSlots
            guard !moved.isEmpty else { return "Nothing changed: gain 1, trim 0 on every slot." }
            return moved.map { slot in
                let name = DuckModel.jointNames[DuckModel.jointOfPolicySlot(slot)]
                return "\(name) ×\(trimmed(gain[slot])) \(offset[slot] < 0 ? "−" : "+")"
                     + "\(trimmed(abs(offset[slot]))) rad"
            }.joined(separator: ", ")
        }
    }

    // MARK: - the schedule, as data rather than as a loop

    /// A (1+λ)-ES, written down instead of written out.
    ///
    /// THE SCHEDULE IS A VALUE SO THE RECEIPT CAN CARRY IT. "Tuned by evolution
    /// search" is not a provenance; "fifteen generations of six children, six
    /// seconds an episode, scored on three drop heights and checked on eight it
    /// never saw" is. Every number a run was shaped by is in here, so the
    /// manifest can print the schedule rather than the word.
    public struct Schedule: Equatable, Sendable {
        /// Children per generation. The `λ` in (1+λ).
        public let lambda: Int
        public let generations: Int
        /// Standard deviations of one mutation step.
        public let gainSigma: Double
        public let offsetSigma: Double
        /// How long one episode runs, seconds of sim time.
        public let seconds: Double
        /// Which slots the search is allowed to move.
        public let searchedSlots: [Int]
        /// The drop heights every candidate is scored on.
        public let searchDrops: [Double]
        /// Drop heights the search never sees, which the winner is checked on.
        public let heldOutDrops: [Double]

        public init(lambda: Int, generations: Int, gainSigma: Double, offsetSigma: Double,
                    seconds: Double, searchedSlots: [Int],
                    searchDrops: [Double], heldOutDrops: [Double]) {
            self.lambda = lambda; self.generations = generations
            self.gainSigma = gainSigma; self.offsetSigma = offsetSigma
            self.seconds = seconds; self.searchedSlots = searchedSlots
            self.searchDrops = searchDrops; self.heldOutDrops = heldOutDrops
        }

        /// The head slots, which are held at gain 1 and trim 0.
        ///
        /// NOT SEARCHED, AND THE CONFIG AGREES. The head is driven by a pose
        /// command that rides in the observation, so trimming it is trimming
        /// against a command rather than against a gait — and
        /// `microduck_velocity_env_cfg`'s own `pose` term deliberately excludes
        /// those four joints for the same reason (`RunMetrics.legStd` returns
        /// nil for them). Fourteen slots exist; ten of them are the search
        /// space.
        public static let headSlots = [5, 6, 7, 8]
        public static let legSlots = (0..<DuckModel.policyJointCount)
            .filter { !headSlots.contains($0) }

        /// What a phone is asked to do — sized by the ONE thing that has been
        /// measured about the cost, and honest that the measurement is not a
        /// phone's.
        ///
        /// The drop heights are the range `/measure` already randomises over,
        /// Pollen's own 0.12–0.13 m, split into three the search sees and eight
        /// it does not. Three is not a taste: a single drop is not a
        /// measurement of a policy, because the spread of ONE unchanged setting
        /// across that range has been measured at up to 273 mm of travel.
        public static let onAPhone = Schedule(
            lambda: 6, generations: 15,
            gainSigma: 0.05, offsetSigma: 0.008,
            seconds: 6,
            searchedSlots: legSlots,
            searchDrops: [0.1210, 0.1250, 0.1290],
            heldOutDrops: [0.1200, 0.1215, 0.1230, 0.1245, 0.1260, 0.1275, 0.1285, 0.1300])

        /// How many episodes a whole run costs, counted rather than estimated.
        ///
        /// THE BASELINE IS IN IT, ON BOTH SETS, AND SO IS THE FINAL CHECK. A
        /// count that left them out would be short by the two runs that decide
        /// whether the answer means anything.
        public var episodes: Int {
            let baseline = searchDrops.count + heldOutDrops.count
            let search = generations * lambda * searchDrops.count
            let check = heldOutDrops.count
            return baseline + search + check
        }

        /// Sim seconds of physics the whole run asks for. NOT wall-clock, which
        /// is a fact about a machine and is measured, never promised.
        public var simSeconds: Double { Double(episodes) * seconds }

        /// The schedule in a sentence, for the panel that goes before the run.
        public var described: String {
            "(1+\(lambda)) evolution search, \(generations) generations over "
          + "\(searchedSlots.count) leg gains and \(searchedSlots.count) leg trims. Every "
          + "candidate is scored on \(searchDrops.count) drop heights and the winner is "
          + "checked on \(heldOutDrops.count) it never saw. That is \(episodes) episodes of "
          + "\(trimmed(seconds)) s."
        }

        /// Why the head is left alone, in the words the reason deserves.
        public static let headIsNotSearched =
            "The four head slots are held at gain 1 and trim 0. The head follows a pose command "
          + "that rides in the observation, so trimming it trims against a command rather than "
          + "against a gait — and the velocity config's own pose term leaves those joints out "
          + "for the same reason."
    }

    // MARK: - the mutation, deterministic and pure

    /// SplitMix64. A seeded generator, so a run is reproducible from its seed.
    ///
    /// WRITTEN OUT RATHER THAN TAKEN FROM `SystemRandomNumberGenerator`,
    /// because a search whose candidates cannot be regenerated is a result
    /// nobody can check. The seed goes in the manifest with everything else.
    public struct Seeded: Sendable {
        private var state: UInt64
        public init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }

        public mutating func next() -> UInt64 {
            state = state &+ 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }

        /// A double in [0, 1). 53 bits, the mantissa's worth.
        public mutating func uniform() -> Double {
            Double(next() >> 11) * (1.0 / 9007199254740992.0)
        }

        /// Box–Muller. The `max` keeps `log(0)` — and the infinity it returns —
        /// out of a number that is about to be multiplied into a weight matrix.
        public mutating func gaussian() -> Double {
            let u = max(uniform(), 1e-12), v = uniform()
            return (-2 * Foundation.log(u)).squareRoot() * Foundation.cos(2 * .pi * v)
        }
    }

    /// One child of a parent, inside the envelope.
    public static func mutate(_ parent: TuningVector, with schedule: Schedule,
                              using rng: inout Seeded) -> TuningVector {
        var gain = parent.gain, offset = parent.offset
        for slot in schedule.searchedSlots {
            gain[slot] += schedule.gainSigma * rng.gaussian()
            offset[slot] += schedule.offsetSigma * rng.gaussian()
        }
        return TuningVector(gain: gain, offset: offset).clamped()
    }

    // MARK: - the reward

    /// One term of the reward, and what it pays for.
    public struct Term: Equatable, Sendable, Identifiable {
        /// `microduck_velocity_env_cfg`'s own name for it, which is also the
        /// key `RunMetrics` reports it under and the key a bench must answer
        /// with. One spelling, three readers.
        public let key: String
        public let weight: Double
        public let purpose: String
        public var id: String { key }

        /// Whether a bigger number is better. It is the SIGN and not a taste,
        /// and it is here because a missing penalty term reads as a perfect
        /// score — see `reward(_:)`.
        public var isPenalty: Bool { weight < 0 }
    }

    /// The six terms of `microduck_velocity_env_cfg` a bench with the trace in
    /// front of it can answer, at that config's own weights.
    ///
    /// THE WEIGHTS ARE READ, NOT TYPED. Every one comes from
    /// `RunMetrics.Task.velocity`, which reads them out of the config file for
    /// grading a recorded clip. A search optimising a second copy of those
    /// numbers would be climbing a hill the rest of the app cannot see.
    ///
    /// `action_rate_l2` IS AT ITS RAMP END. Every config ramps that weight over
    /// training and the trained policy lived under the final value; −0.1 is
    /// what it was worth in the first stage and −1.0 is what it was worth by
    /// the time the network was any good.
    public static let terms: [Term] = {
        let task = RunMetrics.Task.velocity
        return [
            Term(key: "upright", weight: task.upright.weight,
                 purpose: "Holds the trunk level. Perfect when nothing is moving."),
            Term(key: "track_linear_velocity", weight: RunMetrics.Task.trackLinearVelocityWeight,
                 purpose: "Rewards matching the commanded forward and sideways velocity. One of "
                        + "only two terms a duck standing still does badly on."),
            Term(key: "track_angular_velocity", weight: RunMetrics.Task.trackAngularVelocityWeight,
                 purpose: "Rewards matching the commanded turn rate without pitching or rolling."),
            Term(key: "pose", weight: RunMetrics.Task.poseWeight,
                 purpose: "Holds the legs near the home stance. Perfect at home, which is where a "
                        + "duck that has stopped tends to be."),
            Term(key: "body_ang_vel", weight: task.bodyAngularVelocityWeight,
                 purpose: "Penalises trunk pitch and roll rate. Zero when nothing turns."),
            Term(key: "action_rate_l2", weight: task.actionRateWeight,
                 purpose: "Penalises jerky commands, at the ramp end the trained policy lived "
                        + "under. Zero when the output never changes."),
        ]
    }()

    /// The config file every weight above came out of.
    public static let configFile = RunMetrics.Task.velocity.configFile

    /// One thing the reward leaves out, and the reason.
    public struct Refused: Equatable, Sendable, Identifiable {
        public let key: String
        public let why: String
        public var id: String { key }
    }

    /// Terms `microduck_velocity_env_cfg` carries that NOTHING here can answer,
    /// whatever endpoint the bench grows.
    ///
    /// REUSED, NOT RETYPED. `RunMetrics.Task.velocity.unevaluable` is the list
    /// and the reasons; a second list here would be a second opinion about what
    /// this project can measure, and the day one grew a term the other would
    /// not.
    public static let refusedByThePlant: [Refused] =
        RunMetrics.Task.velocity.unevaluable.map { Refused(key: $0.0, why: $0.1) }

    /// The weighted sum, or a refusal naming what was missing.
    ///
    /// A MISSING TERM IS NOT A ZERO, AND THIS IS THE WHOLE REASON THIS FUNCTION
    /// THROWS. Two of the six weights are negative, so a bench that quietly
    /// omitted `action_rate_l2` would hand every candidate the best possible
    /// value of the term that punishes jerk — and the search would find the
    /// jerkiest duck in the envelope and call it the winner. Summing a
    /// dictionary with `?? 0` is the one-character version of that bug.
    public static func reward(_ measured: [String: Double]) throws -> Double {
        var total = 0.0
        for term in terms {
            guard let value = measured[term.key] else { throw Refusal.termMissing(term.key) }
            guard value.isFinite else { throw Refusal.termNotANumber(term.key) }
            total += value * term.weight
        }
        return total
    }

    public enum Refusal: Error, Equatable {
        case termMissing(String)
        case termNotANumber(String)
        case noBaselineYet
        case benchCannotScore

        public var message: String {
            switch self {
            case .termMissing(let key):
                return "The bench answered without \(key), and this will not score a run "
                     + "without it. Two of the six weights are negative, so a term left out "
                     + "reads as the best possible value of the thing it punishes."
            case .termNotANumber(let key):
                return "The bench answered \(key) with something that is not a number."
            case .noBaselineYet:
                return "The unchanged network has not been run yet. Every number this screen "
                     + "shows is a difference from it, and a difference from nothing is not one."
            case .benchCannotScore:
                return notYet
            }
        }
    }

    // MARK: - whether a search can honestly run at all

    /// Where the six term values would come from.
    public enum Scoring: Equatable, Sendable {
        /// The bench computed them: it has the trace, so it can. This is what
        /// `/tune` is for and the only arrangement that scores all six.
        case benchComputesThem
        /// Swift drove `/reset`, `/policy` and `/intent` and read the states
        /// back. Two of six.
        case aLoopOverStates
    }

    /// The four terms a state loop cannot reach, and exactly why.
    ///
    /// THE REASONS ARE `RunMetrics`' OWN SENTENCES, because they are the same
    /// two absences it already reports for a recording made before format 3:
    /// the network's own output, and the trunk's twist. A bench's `/state` and
    /// `/intent` answers are a format-2 clip in every way that matters here.
    public static let refusedByAStateLoop: [Refused] = [
        Refused(key: "track_linear_velocity",
                why: "needs the trunk's twist, and a state answer carries a position but no "
                   + "velocity"),
        Refused(key: "track_angular_velocity",
                why: "needs the trunk's twist"),
        Refused(key: "body_ang_vel",
                why: "needs the trunk's twist"),
        Refused(key: "action_rate_l2",
                why: "needs the network's own output, which no bench answer reports"),
    ]

    /// What is left when those four are gone, and what it is worth.
    public static var scorableByAStateLoop: [Term] {
        let gone = Set(refusedByAStateLoop.map(\.key))
        return terms.filter { !gone.contains($0.key) }
    }

    /// The measurement that settles it, kept as numbers so nothing retypes them.
    ///
    /// Six seconds at vx = 0.5 on this project's own phone-bench build, 275
    /// scored ticks after the settle, both policies through the same loop.
    public static let inertScore = 2.9812
    public static let walkingScore = 2.5287
    public static let inertTravelMillimetres = 1
    public static let walkingTravelMillimetres = 1231

    /// Whether a search can be run honestly on this arrangement, and the
    /// sentence either way.
    public struct Readiness: Equatable, Sendable {
        public let canSearch: Bool
        public let missing: [Refused]
        public let sentence: String
    }

    public static func readiness(for scoring: Scoring) -> Readiness {
        switch scoring {
        case .benchComputesThem:
            return Readiness(canSearch: true, missing: [], sentence: ready)
        case .aLoopOverStates:
            return Readiness(canSearch: false, missing: refusedByAStateLoop, sentence: notYet)
        }
    }

    /// The sentence a bench that CAN score gets.
    public static let ready =
        "This bench scores all six terms itself, because it has the trace: the trunk's twist and "
      + "the network's own output are in front of it and are in front of nothing else. A search "
      + "here is scored on the reward Pollen trained the walk under."

    /// The not-yet. IT NAMES THE MISSING ENDPOINT AND THE NUMBER, because a
    /// blocked surface that only says "not supported" teaches somebody that the
    /// app is small, where this one is a specific and fixable gap in a bench.
    public static let notYet =
        "This phone's bench cannot score a search yet, so there is no Start button. Its answers "
      + "carry a position, a quaternion and fourteen joint angles — no velocity and no action — "
      + "so four of the six reward terms cannot be computed from them, and the two that survive "
      + "are both terms a duck standing still maximises. Measured here at six seconds and "
      + "vx = 0.5: the standing policy scores 2.9812 on those two where the walking policy "
      + "scores 2.5287, having travelled 1 mm against 1231 mm. A search scored that way would "
      + "climb 18% by stopping. The fix is one endpoint — /tune — on the bench, which has the "
      + "trace and can weigh it."

    /// The two terms that DO survive, said where somebody might read the
    /// not-yet as "nothing can be measured here".
    public static let whatStillWorksWithoutTune =
        "What this bench can still do is run a candidate and count outcomes: how often it ends "
      + "standing, and how far it got. That is a comparison between two networks, which is worth "
      + "having. It is not a search, because a comparison does not tell anything which way to go."

    // MARK: - the farming guard

    /// It stayed on its feet and stopped doing the thing.
    ///
    /// `PolicyBlend.Behaviour.wentInertRatherThanFalling`, REUSED RATHER THAN
    /// REIMPLEMENTED. That property is the app's one measured account of this
    /// failure — a 75% blend at 16 of 16 on "ends standing" while travelling
    /// two millimetres — and a second copy of the threshold here is a second
    /// number to get wrong. A candidate that trips it is REJECTED rather than
    /// scored: five of the six terms pay for standing still, so a search that
    /// merely ranked it low would still be pulled toward it.
    public static func wentInert(travelled: Double, baselineTravelled: Double,
                                 standing: Int, of episodes: Int) -> Bool {
        PolicyBlend.Behaviour(
            achieves: standing, rollouts: episodes,
            criterion: "ends standing",
            travelled: travelled,
            liveliestIngredientTravelled: baselineTravelled,
            plant: "").wentInertRatherThanFalling
    }

    /// Said beside a rejected candidate.
    public static let rejectedAsInert =
        "Rejected: it stayed up and stopped walking. Five of the six terms pay for standing "
      + "still, so a candidate that has quietly stopped scores well — that is a hole in the "
      + "reward, not a discovery, and it is thrown away rather than ranked."

    // MARK: - what one candidate came to

    /// A candidate, its reward, and the distance that keeps the reward honest.
    public struct Score: Equatable, Sendable {
        public let reward: Double
        /// Metres, median over the drops it was scored on.
        public let travelled: Double
        public let standing: Int
        public let episodes: Int
        /// Each term's own mean, kept so a result can be read term by term
        /// rather than as one number nobody can take apart.
        public let terms: [String: Double]
        /// The same terms, per drop height, when the bench reported them.
        ///
        /// THE ONLY SOURCE OF A NOISE FLOOR. A spread cannot be recovered from
        /// a mean, and the spread is what decides whether a gain is a gain, so
        /// this is carried rather than summarised away. Empty from a bench that
        /// reports only aggregates, and `DuckTuner.noiseFloor` returns nil for
        /// that rather than inventing one.
        public let perDrop: [[String: Double]]

        public init(reward: Double, travelled: Double, standing: Int, episodes: Int,
                    terms: [String: Double], perDrop: [[String: Double]] = []) {
            self.reward = reward; self.travelled = travelled
            self.standing = standing; self.episodes = episodes
            self.terms = terms; self.perDrop = perDrop
        }
    }

    /// One generation of the search, as the run panel draws it.
    public struct Generation: Equatable, Sendable, Identifiable {
        public let index: Int
        public let best: Score
        /// Children thrown out by the inert guard, which is a number worth
        /// seeing: a generation where five of six went inert is a search
        /// pressing against the hole in its own reward.
        public let rejectedAsInert: Int
        public init(index: Int, best: Score, rejectedAsInert: Int) {
            self.index = index
            self.best = best
            self.rejectedAsInert = rejectedAsInert
        }
        public var id: Int { index }
    }

    /// Best reward AND the distance beside it, never one alone.
    ///
    /// THE SAME RULE `PolicyBlend.measured` ENFORCES, for the same measured
    /// reason. A reward that went up while the distance went to nothing is the
    /// failure, and a panel that showed only the reward would draw it as
    /// progress.
    public static func generationLine(_ generation: Generation) -> String {
        "Generation \(generation.index): reward \(number(generation.best.reward, places: 4)), "
      + "travelled \(millimetres(generation.best.travelled)), standing "
      + "\(generation.best.standing) of \(generation.best.episodes)"
      + (generation.rejectedAsInert > 0
            ? " — \(generation.rejectedAsInert) rejected as inert." : ".")
    }

    /// The spread of the UNCHANGED network's own reward across the drops it was
    /// never selected on — the number a gain has to beat to be a gain.
    ///
    /// MEASURED FROM PER-EPISODE REWARDS, AND REFUSED WITHOUT THEM. This is the
    /// one figure that decides whether a whole run meant anything, and it
    /// cannot be derived from an aggregate mean: the spread IS the thing, and
    /// a mean has thrown it away. One unchanged setting's travel has been
    /// measured varying by up to 273 mm across this drop range, so the wobble
    /// is large and assuming it small is not available. A bench that reports
    /// only aggregates gets a nil here and a screen that says the verdict
    /// cannot be reached, which is worse than a number and better than a
    /// number nobody measured.
    /// A NaN ANYWHERE REFUSES THE WHOLE FLOOR, and checking the min and the max
    /// is not enough to catch one. Every comparison with a NaN is false, so
    /// `[2.5, nan].min()` and `.max()` are both 2.5 and the spread comes out a
    /// confident zero — which is the smallest possible noise floor and would
    /// wave through any gain at all. Found by a test that expected nil.
    public static func noiseFloor(_ rewards: [Double]) -> Double? {
        guard rewards.count >= 2, rewards.allSatisfy(\.isFinite),
              let low = rewards.min(), let high = rewards.max() else { return nil }
        return high - low
    }

    /// Said when the floor could not be measured.
    public static let noNoiseFloor =
        "This bench reported one number for the whole batch rather than one per drop, so the "
      + "unchanged network's own wobble across those drops could not be measured — and without "
      + "it there is no way to say whether a gain is a gain. The result is kept and the verdict "
      + "is not, because a verdict against an invented floor is worse than none."

    /// Whether the answer survived drops the search never saw.
    ///
    /// THE ONLY QUESTION THAT MATTERS AT THE END. A gain on the three drops a
    /// candidate was selected on is a gain on three drops; the noise floor is
    /// the spread of the UNCHANGED network over the eight it did not see, and
    /// anything under that is not a result.
    public static func heldOutVerdict(gain: Double, noiseFloor: Double) -> String {
        guard gain > noiseFloor else {
            return "It did not survive the drop heights it was not selected on: "
                 + "\(signed(gain)) against a noise floor of \(number(noiseFloor, places: 4)) — "
                 + "the spread of the UNCHANGED network over those same drops. What the search "
                 + "found on the three drops it scored did not transfer. That is the usual "
                 + "outcome and it is a real answer."
        }
        return "It survived: \(signed(gain)) on drop heights the search never saw, against a "
             + "noise floor of \(number(noiseFloor, places: 4)) — the unchanged network's own "
             + "spread over those same drops. The gain is bigger than the wobble."
    }

    // MARK: - the sentences that must travel with the result

    /// The provenance line. IT GOES IN THE MANIFEST, IN THE ONNX METADATA AND
    /// ON THE ROW, because those are three places somebody meets this file and
    /// only one of them is this app.
    public static func provenance(episodes: Int, seconds: Double, bench: String,
                                  basePolicy: String, baseFingerprint: String,
                                  seed: UInt64) -> String {
        "Tuned on \(bench) by evolution search: \(episodes) episodes of \(trimmed(seconds)) s, "
      + "scored on \(terms.map(\.key).joined(separator: ", ")) at "
      + "\(configFile)'s own weights, seed \(seed). The network underneath is \(basePolicy) "
      + "(\(baseFingerprint.prefix(12))), trained by somebody else; this changed a per-joint "
      + "gain and trim and folded it into the last layer. \(neverOnHardware)"
    }

    /// The sentence no result may leave without.
    public static let neverOnHardware =
        "Never run on hardware. Every number behind this came out of a simulator, and no "
      + "Microduck has moved because of it."

    /// The correction for anybody who reads "tuned" as "trained".
    public static let notTraining =
        "This is not training. No gradient is computed here and no weight is learned: a search "
      + "tries twenty-eight numbers, a multiplier and a trim per joint, and folds the best of "
      + "them into a network somebody else trained. The walk is still theirs."

    /// What is NOT folded, said where it would otherwise be assumed.
    public static let actionScaleIsNotFolded =
        "The action scale is not in the file. robotd multiplies this network's output by its own "
      + "action_scale before it becomes a joint offset, and folding a scale in would mean the "
      + "file and the config both claimed it — the robot would apply the product. A gain here is "
      + "a per-joint shape change on top of whatever scale the runtime is set to."

    // MARK: - duration: measured, never promised

    /// Before anything has run.
    public static let durationNotMeasuredYet =
        "How long this takes on this phone has not been measured. It will be timed as it runs "
      + "and reported then; a figure quoted before the first episode would be a number from "
      + "somebody else's machine."

    /// After N episodes have actually finished, and not before.
    ///
    /// THE REMAINDER IS AN EXTRAPOLATION AND SAYS SO. A progress line that
    /// printed "4 minutes left" as though it were a fact is the same move as
    /// quoting a Raspberry Pi's tick as a phone's.
    public static func durationSoFar(episodesDone: Int, elapsed: TimeInterval,
                                     schedule: Schedule) -> String {
        guard episodesDone > 0, elapsed > 0 else { return durationNotMeasuredYet }
        let each = elapsed / Double(episodesDone)
        let left = Double(schedule.episodes - episodesDone) * each
        return "\(episodesDone) of \(schedule.episodes) episodes in \(duration(elapsed)) — "
             + "\(number(each, places: 2)) s each, measured here. At that rate the rest is about "
             + "\(duration(left)), which is an extrapolation from what has run and not a promise."
    }

    /// What a finished run cost, which is the only duration worth keeping.
    public static func durationMeasured(episodes: Int, elapsed: TimeInterval) -> String {
        "\(episodes) episodes in \(duration(elapsed)), measured on this bench."
    }

    // MARK: - the export

    /// Everything a tuned policy leaves this phone as.
    ///
    /// THREE ARTEFACTS BECAUSE THERE ARE THREE READERS, and a file that served
    /// all of them would serve none. `onnx` is what robotd loads and nothing
    /// else; `manifest` is what another copy of this app — or Pollen's own
    /// sharing format — reads to learn the command layout and the caveats;
    /// `robotdExcerpt` is what a person pastes into a config, and it is the one
    /// that has to refuse to invent values.
    public struct Export: Equatable, Sendable {
        public let onnx: Data
        public let manifest: Data
        public let robotdExcerpt: String
        /// The digest of the TUNED parameters — a new network by every rule
        /// this app identifies networks with.
        public let fingerprint: String
        /// The digest of what it was folded into.
        public let baseFingerprint: String
        public let filename: String
    }

    /// Fold, write, and attach the provenance where each reader will find it.
    /// - Parameters:
    ///   - baseFile: the base policy's own BYTES, not just its parameters. The
    ///     metadata in them has to be carried forward — see below — and taking
    ///     the file rather than a `DuckPolicy` is what makes it impossible to
    ///     fold one network and copy another's account of itself.
    ///   - declaredActionScale: what a MANIFEST said, if one came with the
    ///     file. A manifest outranks the file's own metadata because it is what
    ///     the person sharing the policy wrote down for a reader; nil falls
    ///     back to the file's `action_scale`, and when neither exists the key
    ///     is omitted rather than filled in. `folding` leaves the scale exactly
    ///     where it was, so this app has learned nothing about it and writing a
    ///     plausible 0.9 would be inventing the number that decides how hard
    ///     the robot drives every joint.
    public static func export(baseFile: Data, basePolicy: String,
                              declaredActionScale: Double?,
                              vector: TuningVector, schedule: Schedule,
                              seed: UInt64, bench: String,
                              measuredTerms: [String: Double],
                              travelled: Double,
                              elapsed: TimeInterval) throws -> Export {
        let base = try DuckPolicy.load(from: baseFile)
        let folded = try vector.folded(into: base)
        let story = provenance(episodes: schedule.episodes, seconds: schedule.seconds,
                               bench: bench, basePolicy: basePolicy,
                               baseFingerprint: base.fingerprint, seed: seed)

        // THE BASE FILE'S OWN METADATA COMES WITH IT, AND LEAVING IT BEHIND WAS
        // A REAL BUG THAT A REAL PARSER FOUND. `DuckPolicyWriter.encoded`
        // writes a graph and no `metadata_props` at all — correctly, it is a
        // writer for parameters — so a folded file assembled from parameters
        // alone arrives with NOTHING. Read out of Pollen's own
        // `alpha_walking.onnx`, that "nothing" costs eight keys, and one of
        // them is load-bearing: `default_joint_pos` is the neutral pose the
        // policy's actions are offsets FROM. duck-sounds carries a whole file
        // (`sim/onnx_meta.mjs`) whose entire reason for existing is that
        // ignoring that key lied to the community `headspin.onnx` by seven
        // degrees on the neck and nineteen on the head — in a policy whose job
        // is balancing on that head. A fold does not change a neutral pose, so
        // dropping the declaration would produce a file that is arithmetically
        // exact and deployed against the wrong pose. `action_scale`,
        // `joint_names`, `joint_stiffness` and `joint_damping` are the same
        // shape of loss, quieter.
        //
        // OURS WINS ON A COLLISION, and only `producer` collides: everything
        // this app adds is under a `microduck_studio.` prefix precisely so that
        // carrying a stranger's keys forward can never overwrite this file's
        // account of itself.
        let inherited = metadata(of: baseFile)
        var pairs = inherited
            .filter { $0.key != "producer" }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
        // THE ONNX CARRIES THE STORY TOO, because the `.onnx` is the artefact
        // most likely to arrive somewhere alone: a manifest can be lost in a
        // copy and a config excerpt is prose. `metadata_props` is where every
        // trained policy in this family already keeps its own account of
        // itself, so this is the field a reader is already looking at.
        pairs += [
                ("producer", "Microduck Studio"),
                ("microduck_studio.kind", "tuned"),
                ("microduck_studio.base_policy", basePolicy),
                ("microduck_studio.base_fingerprint", base.fingerprint),
                ("microduck_studio.terms", terms.map { "\($0.key)=\(trimmed($0.weight))" }
                    .joined(separator: " ")),
                ("microduck_studio.reward_config", configFile),
                ("microduck_studio.schedule", schedule.described),
                ("microduck_studio.seed", String(seed)),
                ("microduck_studio.residual", vector.described),
                ("microduck_studio.provenance", story),
                ("microduck_studio.never_on_hardware", neverOnHardware),
                ("microduck_studio.inherited_keys",
                 inherited.keys.sorted().joined(separator: ",")),
        ]
        let annotated = try withMetadata(try DuckPolicyWriter.encoded(
            mean: folded.parameters.mean, std: folded.parameters.std,
            layers: folded.parameters.layers), pairs)
        // A MANIFEST OUTRANKS THE FILE, AND THE FILE OUTRANKS A GUESS. There is
        // no third fallback on purpose.
        let actionScale = declaredActionScale ?? inherited["action_scale"].flatMap(Double.init)
        return Export(
            onnx: annotated,
            manifest: try manifestData(folded: folded, basePolicy: basePolicy,
                                       baseFingerprint: base.fingerprint,
                                       baseActionScale: actionScale,
                                       inheritedKeys: inherited.keys.sorted(),
                                       vector: vector, schedule: schedule,
                                       story: story, measuredTerms: measuredTerms,
                                       travelled: travelled, elapsed: elapsed),
            robotdExcerpt: robotdExcerpt(filename: filename(for: folded),
                                         basePolicy: basePolicy, story: story),
            fingerprint: folded.fingerprint,
            baseFingerprint: base.fingerprint,
            filename: filename(for: folded))
    }

    /// `tuned-<first twelve of the tuned digest>.onnx`.
    ///
    /// THE DIGEST AND NOT THE BASE'S NAME. Three runs against `alpha_walking`
    /// produce three different networks, and calling all of them
    /// `alpha_walking_tuned.onnx` is how the second one overwrites the first on
    /// somebody's robot.
    public static func filename(for policy: DuckPolicy) -> String {
        "tuned-\(policy.fingerprint.prefix(12)).onnx"
    }

    /// The manifest, in the format `PolicyManifest` reads.
    /// - Parameter baseFingerprint: THE DIGEST OF WHAT WAS FOLDED INTO, and it
    ///   is a parameter rather than a read off `folded` because the first
    ///   version of this took it off `folded` and wrote the TUNED digest into a
    ///   field called `base_fingerprint`. The manifest then said the network
    ///   underneath was itself — which is a claim about provenance, in the one
    ///   field that exists to make a result reproducible, and it looked
    ///   completely normal.
    static func manifestData(folded: DuckPolicy, basePolicy: String,
                             baseFingerprint: String,
                             baseActionScale: Double?, inheritedKeys: [String],
                             vector: TuningVector, schedule: Schedule,
                             story: String, measuredTerms: [String: Double],
                             travelled: Double, elapsed: TimeInterval) throws -> Data {
        var cautions = [
            neverOnHardware,
            notTraining,
            actionScaleIsNotFolded,
            Schedule.headIsNotSearched,
        ]
        cautions.append("Scored on \(schedule.searchDrops.count) drop heights and checked on "
                      + "\(schedule.heldOutDrops.count) it never saw. Nothing here varied the "
                      + "floor, the payload or the battery, so this is tuned for one bench's "
                      + "world and not for a room.")
        for refused in refusedByThePlant {
            cautions.append("\(refused.key) was not in the reward: \(refused.why).")
        }
        if baseActionScale == nil {
            cautions.append("Neither a manifest nor the base file's own metadata says what action "
                          + "scale this network was meant to be driven at, and this file does not "
                          + "guess one. A reader that assumes a default is assuming, not reading.")
        }
        if inheritedKeys.isEmpty {
            cautions.append("The base file declared no metadata of its own, so nothing was "
                          + "carried forward — including the neutral pose its actions are "
                          + "offsets from. Anything replaying this has to know that pose from "
                          + "somewhere else.")
        }
        return try PolicyManifest.encode(PolicyManifest.Written(
            name: filename(for: folded),
            summary: story,
            // CARRIED THROUGH UNCHANGED, OR OMITTED. `folding` leaves
            // `action_scale` exactly where it was, so the tuned file declares
            // whatever the base declared and nothing more. Nil means the base
            // declared nothing, and the key is left out — a policy driven 10%
            // short because this app filled in a plausible number is the exact
            // failure `PolicyLibrary.declaredScale` was written to stop.
            actionScale: baseActionScale,
            kind: "perpetual",
            durationSeconds: nil,
            entryPose: "standing",
            twist: ["forward velocity, m/s", "sideways velocity, m/s", "turn rate, rad/s"],
            idle: [0, 0, 0],
            cautions: cautions,
            extra: [
                "artifact": "policy",
                "authored_in": "Microduck Studio",
                "tuning": [
                    "base_policy": basePolicy,
                    "base_fingerprint": baseFingerprint,
                    "fingerprint": folded.fingerprint,
                    "method": "(1+\(schedule.lambda))-ES over a per-joint gain and trim, folded "
                            + "into the last layer",
                    "reward_config": configFile,
                    "terms": terms.map { ["name": $0.key, "weight": $0.weight] },
                    // ONLY WHAT THE PLANT CANNOT ANSWER. `refusedByAStateLoop`
                    // was in this list and should never have been: it names
                    // what a BENCH could not report, and a run that reached
                    // this point was scored by a bench that reported all six.
                    // Writing those four here told every future reader that
                    // four terms had been left out of a reward they were in.
                    "refused": refusedByThePlant.map { ["name": $0.key, "why": $0.why] },
                    "inherited_metadata": inheritedKeys,
                    "measured_terms": measuredTerms,
                    "travelled_m": travelled,
                    "episodes": schedule.episodes,
                    "wall_seconds": elapsed,
                    "residual": vector.described,
                ],
            ]))
    }

    /// The `[policy]` lines a tuned file changes, and NOT ONE MORE.
    ///
    /// IT KEEPS `SimDuckConfig.robotdToml()`'s REFUSAL. That function declines
    /// to write `action_scale` because this app holds no value for the robot's,
    /// and a default written there would be inventing a robot's tuning. Nothing
    /// about a fold changes that: the scale the SEARCH ran under is a fact
    /// about a bench, not about anybody's robot, so it goes in a comment where
    /// it can be read and cannot be pasted into a live key. Writing it as a key
    /// would be the exact failure that comment exists to prevent, arriving
    /// through a new door.
    public static func robotdExcerpt(filename: String, basePolicy: String,
                                     story: String) -> String {
        var lines: [String] = []
        lines.append("# \(filename) — the walking slot, tuned.")
        lines.append("#")
        for line in wrapped(story, at: 74) { lines.append("# \(line)") }
        lines.append("#")
        lines.append("[policy]")
        lines.append("walk = \(SimDuckConfig.tomlString(filename))")
        lines.append("# It was \(SimDuckConfig.tomlComment(basePolicy)) before this.")
        lines.append("#")
        lines.append("# action_scale is NOT written here, and that is deliberate. The fold left")
        lines.append("# it alone — it is your robot's key and this app has never read it — so a")
        lines.append("# number written here would be inventing your tuning rather than")
        lines.append("# recording it. Whatever you had, keep.")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - metadata_props, appended to a written ONNX

    /// A `ModelProto` with string metadata attached.
    ///
    /// APPENDED RATHER THAN WOVEN IN, WHICH IS LEGAL AND IS THE POINT. A
    /// ModelProto is a flat protobuf message and `metadata_props` is field 14,
    /// repeated; a repeated field's entries may appear anywhere in the message,
    /// so writing them after the graph produces exactly the message a writer
    /// that emitted them in order would. That keeps duckkit's writer the single
    /// author of the graph — this adds a field and touches no tensor — and it
    /// is why `DuckPolicy.load` still reads the result: it walks to field 7 and
    /// what follows field 7 is not its business.
    ///
    /// THE ENCODING IS FOUR RULES AND THEY ARE WRITTEN OUT BELOW rather than
    /// pulled from a library, because the alternative was a dependency for
    /// thirty lines — and duckkit's own writer, which this file will not
    /// duplicate, took the same view about the same format for the same reason.
    ///
    ///     ModelProto            14 = metadata_props (repeated)
    ///     StringStringEntryProto 1 = key   2 = value
    static func withMetadata(_ model: Data, _ pairs: [(String, String)]) throws -> Data {
        var out = [UInt8](model)
        for (key, value) in pairs {
            let entry = delimited(1, Array(key.utf8)) + delimited(2, Array(value.utf8))
            out += delimited(14, entry)
        }
        return Data(out)
    }

    /// The `metadata_props` of a model, read back.
    ///
    /// HERE BECAUSE A WRITER WITHOUT A READER IS A CLAIM. The test that matters
    /// is the round trip — write the pairs, read them back, and separately
    /// prove `DuckPolicy.load` still takes the file — and neither half can be
    /// asserted without this.
    ///
    /// Unknown fields are SKIPPED BY WIRE TYPE rather than assumed away, so
    /// this reads a real ONNX from anywhere and not only the ones written
    /// above.
    public static func metadata(of model: Data) -> [String: String] {
        var found: [String: String] = [:]
        let bytes = [UInt8](model)
        var i = 0
        while i < bytes.count {
            guard let (tag, next) = varint(bytes, i) else { return found }
            i = next
            let field = Int(tag >> 3), wire = Int(tag & 7)
            switch wire {
            case 0:
                guard let (_, after) = varint(bytes, i) else { return found }
                i = after
            case 1: i += 8
            case 5: i += 4
            case 2:
                guard let (length, after) = varint(bytes, i) else { return found }
                let start = after, end = start + Int(length)
                guard end <= bytes.count else { return found }
                if field == 14, let (key, value) = entry(bytes, start, end) {
                    found[key] = value
                }
                i = end
            default:
                return found
            }
        }
        return found
    }

    /// One `StringStringEntryProto` between two offsets.
    private static func entry(_ bytes: [UInt8], _ from: Int, _ to: Int) -> (String, String)? {
        var i = from, key: String?, value: String?
        while i < to {
            guard let (tag, next) = varint(bytes, i) else { return nil }
            i = next
            let field = Int(tag >> 3), wire = Int(tag & 7)
            guard wire == 2, let (length, after) = varint(bytes, i) else { return nil }
            let start = after, end = start + Int(length)
            guard end <= to else { return nil }
            let text = String(decoding: bytes[start..<end], as: UTF8.self)
            if field == 1 { key = text } else if field == 2 { value = text }
            i = end
        }
        guard let key else { return nil }
        return (key, value ?? "")
    }

    private static func varint(_ bytes: [UInt8], _ from: Int) -> (UInt64, Int)? {
        var value: UInt64 = 0, shift: UInt64 = 0, i = from
        while i < bytes.count {
            let byte = bytes[i]; i += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return (value, i) }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }

    private static func varintBytes(_ value: UInt64) -> [UInt8] {
        var v = value, out: [UInt8] = []
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            out.append(byte)
        } while v != 0
        return out
    }

    private static func delimited(_ field: Int, _ payload: [UInt8]) -> [UInt8] {
        varintBytes(UInt64(field << 3 | 2)) + varintBytes(UInt64(payload.count)) + payload
    }

    // MARK: - printing

    /// A number with the trailing zeros taken off, for a gain that is 1.08 and
    /// not 1.0800.
    static func trimmed(_ value: Double) -> String {
        guard value.isFinite else { return value.isNaN ? "not a number" : "unbounded" }
        var text = String(format: "%.4f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text.isEmpty ? "0" : text
    }

    static func number(_ value: Double, places: Int) -> String {
        String(format: "%.\(places)f", value)
    }

    static func signed(_ value: Double) -> String {
        (value >= 0 ? "+" : "") + number(value, places: 4)
    }

    /// Metres as millimetres under a centimetre, which is where a walk that
    /// stopped lives.
    static func millimetres(_ metres: Double) -> String {
        metres < 0.01 ? "\(Int((metres * 1000).rounded())) mm"
                      : String(format: "%.2f m", metres)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "an unmeasured time" }
        if seconds < 90 { return "\(Int(seconds.rounded())) s" }
        let minutes = Int((seconds / 60).rounded())
        return "\(minutes) min"
    }

    /// Wrap for a comment block, on whitespace, without splitting a word.
    static func wrapped(_ text: String, at width: Int) -> [String] {
        var lines: [String] = [], current = ""
        for word in text.split(separator: " ") {
            if current.isEmpty { current = String(word) }
            else if current.count + 1 + word.count <= width { current += " \(word)" }
            else { lines.append(current); current = String(word) }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
}

private func trimmed(_ value: Double) -> String { DuckTuner.trimmed(value) }
