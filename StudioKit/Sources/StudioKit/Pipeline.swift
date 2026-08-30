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
        /// Which plant it ran against. The rollers scene and the legs scene
        /// are different robots and a result from one is not a result for the
        /// other.
        public var plant: String
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

        public init(when: Date, bench: String, plant: String, policy: String,
                    achieves: Int, rollouts: Int, criterion: String,
                    medianHeight: Double? = nil, peakJointRate: Double? = nil) {
            self.when = when; self.bench = bench; self.plant = plant
            self.policy = policy; self.achieves = achieves; self.rollouts = rollouts
            self.criterion = criterion; self.medianHeight = medianHeight
            self.peakJointRate = peakJointRate
        }

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
    /// metres. MEASURED on the canon plant: `BEST_alpha_stand.onnx` over three
    /// seconds holds 0.1162 m from the first frame to the last. The model's
    /// nominal rest height is 0.12; this is what the policy actually does.
    public static let standingHeight = 0.116

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
                detail: "\(bench.summary) On \(bench.plant)."))
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
