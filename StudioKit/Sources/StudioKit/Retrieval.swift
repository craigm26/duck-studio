import Foundation
import DuckKit

/// Fetching a stick, composed out of policies that already exist.
///
/// YOU CANNOT TRAIN A NEW NETWORK FROM A SENTENCE, and this does not pretend
/// to. Training is a rollout loop against a physics engine, not a gradient the
/// phone could take; what a sentence CAN do is compose skills the robot already
/// has, and retrieval turns out to need no new one. Walking is `alpha_walking`.
/// Reaching down is `alpha_ground_pick`. The grasp is the fifteenth servo,
/// which no policy drives. That is the whole verb.
///
/// EVERY NUMBER BELOW IS SOURCED. Upstream's training config and the robot's
/// own runtime supply the phase schedule and the payload; the grasp instant is
/// measured from our recording of the policy, because the config's nominal hold
/// and the plant's actual low point DISAGREE — see `graspWindow`.
public enum Retrieval {

    // MARK: - what upstream says

    /// The ground-pick phase period, seconds. BORROWED FROM DuckKit rather
    /// than restated — a second copy of 4.0 is a copy that eventually
    /// disagrees with the package that models the robot. `GP_PERIOD` in
    /// microduck_rl's `microduck_ground_pick_env_cfg.py`, and
    /// `ground_pick_period` in the robot's own `robotd/src/control.rs`. Both
    /// say 4.0, and the env's header warns that the deployment flag must match.
    public static var phasePeriod: Double { DuckModel.groundPickPeriod }

    /// The robot stops driving ground-pick at this phase.
    /// `GROUND_PICK_END_PHASE` in `robotd/src/control.rs`.
    ///
    /// THE RUN IS CUT BEFORE THE RISE FINISHES, and upstream knows: the env
    /// config's rise does not complete until phase 0.80, and its comment flags
    /// exactly this ("⚠️ RISE_END=0.80 > coupure φ=0.7"). So a real ground-pick
    /// ends with the head still a few degrees short of home. Our recording
    /// shows the mouth tip 7 mm higher at the last frame than the first. That
    /// is the robot, not the recording, and a retrieval has to allow for it —
    /// see `settleAfterLift`.
    public static var endPhase: Double { DuckModel.groundPickEndPhase }

    /// How long a ground-pick actually runs on the robot: 2.8 s.
    public static var pickDuration: Double { DuckModel.groundPickDuration }

    /// What the policy was trained to lift, kilograms. `sample_mouth_payload`
    /// draws 0.01–0.04 kg per episode and applies it at the mouth tip through
    /// the rise, so carrying something IS in the training distribution — but
    /// only up to 40 g.
    public static let payloadRange = 0.010...0.040

    // MARK: - what we measured

    /// When the mouth is actually at its lowest, seconds into the pick.
    ///
    /// MEASURED, AND IT DISAGREES WITH THE CONFIG. The env's reward schedule
    /// calls phase 0.375–0.425 the low hold — 1.50 s to 1.70 s. Run the shipped
    /// policy and the mouth tip bottoms out at 1.16 s (phase 0.29) and is
    /// already climbing by 1.50 s. Close the jaw on the config's window and you
    /// close it on the way up. The plant lags its own reward gate, and only the
    /// measurement is usable.
    public static let graspInstant = 1.16

    /// The span where the mouth tip is within 5 mm of its lowest — the window a
    /// grasp has to land in. Measured through DuckKit's kinematics over the
    /// recorded `ground_pick` clip.
    public static let graspWindow = 0.76...1.50

    /// How high the mouth tip is at its lowest, metres, mouth OPEN.
    public static let openTipHeight = 0.0349

    /// And with the jaw shut: the bite closes 20 mm above the floor.
    ///
    /// THIS IS WHY A FLAT STICK CANNOT BE PICKED UP. The policy is rewarded for
    /// bringing the mouth close to the ground and PENALISED for touching it —
    /// upstream's docstring says "AS CLOSE AS POSSIBLE to the ground WITHOUT
    /// touching it" — so the jaw never reaches the floor. Anything thinner than
    /// this passes underneath the bite.
    ///
    /// Caveat carried from the model: the jaw and its `mouth_tip` site are
    /// OURS, derived from the mouth servo's placement, because upstream's mesh
    /// does not split the head. The 20 mm is as good as that derivation.
    public static let closedTipHeight = 0.0200

    /// Walking speed, m/s. The canon plant's measured `alpha_walking`.
    public static let walkSpeed = 0.106

    /// After the truncated rise, how long to stand before walking off. The
    /// clip ends mid-return, so setting straight into a walk hands the walking
    /// policy a pose its own recording never starts from.
    public static let settleAfterLift = 0.6

    // MARK: - the thing being fetched

    public struct Stick: Equatable, Sendable {
        /// Grams. Compared against the trained payload.
        public let grams: Double
        /// How thick the part it will bite, millimetres.
        public let thicknessMillimetres: Double
        /// How far away it is, metres.
        public let metresAway: Double
        /// How high off the floor the part it would bite is, millimetres. Nil
        /// means lying on the floor. A broom leaning against a wall puts its
        /// handle up in the air, and the ground-pick arc sweeps the mouth
        /// through every height from 35 mm to 184 mm on the way down — so this
        /// changes WHEN to close the jaw, not whether it can be reached.
        public let graspHeightMillimetres: Double?
        /// How well it slides. AN ESTIMATE OF YOUR FLOOR, not a measurement of
        /// anything: 0.4 is a middling guess between a smooth board and a rug.
        public let floorFriction: Double

        public init(grams: Double, thicknessMillimetres: Double, metresAway: Double,
                    graspHeightMillimetres: Double? = nil, floorFriction: Double = 0.4) {
            self.grams = grams
            self.thicknessMillimetres = thicknessMillimetres
            self.metresAway = metresAway
            self.graspHeightMillimetres = graspHeightMillimetres
            self.floorFriction = floorFriction
        }

        /// Light enough for the lift the policy was trained against.
        public var isLiftable: Bool { grams <= Retrieval.payloadRange.upperBound * 1000 }
    }

    /// Why a retrieval will not work. Each one names a measurement.
    public enum Refusal: Equatable, Sendable {
        /// Past the lift, but the floor can take the weight.
        case tooHeavyToLift(grams: Double, drag: Drag.Verdict)
        /// Past the lift AND past the pull.
        case tooHeavyToDrag(grams: Double, drag: Drag.Verdict)
        case tooThin(millimetres: Double)
        /// Held higher than the arc ever reaches, or lower than its bottom.
        case outOfReach(millimetres: Double)
        case tooFar(metres: Double, minutes: Double)

        public var message: String {
            switch self {
            case .tooHeavyToLift(let grams, let drag):
                return String(format: "%.0f g is more than it can lift — the ground-pick policy "
                    + "is trained with 10–40 g hanging at its mouth through the rise. But it "
                    + "does not have to lift it. %@ %@", grams, drag.message, Drag.untestedNote)
            case .tooHeavyToDrag(let grams, let drag):
                return String(format: "%.0f g is past lifting AND past pulling. %@",
                              grams, drag.message)
            case .tooThin(let mm):
                return String(format: "At %.0f mm it passes under the bite. The jaw "
                    + "closes %.0f mm above the floor — the policy is rewarded for "
                    + "reaching down and penalised for touching, so it never gets "
                    + "lower. Prop it up, or fetch something thicker.",
                    mm, closedTipHeight * 1000)
            case .outOfReach(let mm):
                return String(format: "The mouth sweeps from %.0f mm down to %.0f mm through a "
                    + "ground pick, and %.0f mm is outside that. Move it into the arc — or "
                    + "lay it down, which is the same problem with a different answer.",
                    Reach.highestDuringPick * 1000, Reach.lowestDuringPick * 1000, mm)
            case .tooFar(let metres, let minutes):
                return String(format: "%.1f m each way at 0.106 m/s is %.0f minutes of "
                    + "walking. It will do it; it is worth knowing first.", metres, minutes)
            }
        }

        /// Whether this stops the plan or merely warns. Distance is a warning:
        /// slow is not the same as impossible, and refusing a duck for being
        /// slow would be refusing it for being a duck.
        /// Whether this stops the plan or merely warns.
        ///
        /// DISTANCE IS A WARNING: slow is not impossible, and refusing a duck
        /// for being slow would be refusing it for being a duck. SO IS BEING
        /// TOO HEAVY TO LIFT, now that there is a second answer — the plan
        /// switches to dragging and says what is unknown about it.
        public var isFatal: Bool {
            switch self {
            case .tooFar, .tooHeavyToLift: return false
            case .tooHeavyToDrag, .tooThin, .outOfReach: return true
            }
        }
    }

    // MARK: - the plan

    public enum Step: Equatable, Sendable {
        /// Walk to it, steering on an arc. `alpha_walking`.
        case approach(metres: Double)
        /// `alpha_ground_pick` from phase 0 down to the grasp instant.
        case reachDown
        /// Shut the fifteenth servo. NOT a policy output — no network drives
        /// the mouth, which is exactly why this step can exist at all.
        case closeMouth
        /// The rest of the pick: the rise, carrying the payload.
        case lift
        /// Stand still long enough to finish the return the runtime cut short.
        case settle
        /// Walk back, still carrying.
        case carryBack(metres: Double)
        /// Walk back TOWING it. The floor holds the weight; the duck only
        /// fights friction — and nothing has ever measured it doing so.
        case dragBack(metres: Double)
        /// Open the servo again.
        case release

        public var label: String {
            switch self {
            case .approach(let m): return String(format: "Walk %.2f m to it", m)
            case .reachDown:       return "Reach down"
            case .closeMouth:      return "Close the mouth"
            case .lift:            return "Lift"
            case .settle:          return "Settle"
            case .carryBack(let m): return String(format: "Carry it %.2f m back", m)
            case .dragBack(let m): return String(format: "Drag it %.2f m back", m)
            case .release:         return "Open the mouth"
            }
        }

        /// Which policy drives it, or nil for the servo steps — the honest
        /// answer to "what is running right now".
        public var policy: String? {
            switch self {
            case .approach, .carryBack, .dragBack: return "alpha_walking"
            case .reachDown, .lift:     return "alpha_ground_pick"
            case .closeMouth, .release, .settle: return nil
            }
        }

        public var seconds: Double {
            switch self {
            case .approach(let m), .carryBack(let m), .dragBack(let m): return m / walkSpeed
            case .reachDown:  return graspInstant
            case .closeMouth: return 0.25
            case .lift:       return pickDuration - graspInstant
            case .settle:     return settleAfterLift
            case .release:    return 0.25
            }
        }
    }

    public struct Plan: Equatable, Sendable {
        public let stick: Stick
        public let steps: [Step]
        public let refusals: [Refusal]

        public var isPossible: Bool { !refusals.contains { $0.isFatal } }
        public var seconds: Double { steps.reduce(0) { $0 + $1.seconds } }

        /// When each step starts, for a timeline.
        public var schedule: [(start: Double, step: Step)] {
            var t = 0.0
            var out: [(Double, Step)] = []
            for step in steps { out.append((t, step)); t += step.seconds }
            return out
        }
    }

    /// Build the plan, and say what is wrong with it.
    public static func plan(for stick: Stick) -> Plan {
        var refusals: [Refusal] = []

        // TOO HEAVY TO LIFT IS NOT THE END OF IT. The floor can take the
        // weight — dragging only has to beat friction — so a broom that could
        // never be carried may still be towed, and saying "too heavy" and
        // stopping would refuse a job the duck might well do.
        let dragging = !stick.isLiftable
        if dragging {
            let verdict = Drag.verdict(kilograms: stick.grams / 1000,
                                       floorFriction: stick.floorFriction)
            refusals.append(verdict.isWithin
                ? .tooHeavyToLift(grams: stick.grams, drag: verdict)
                : .tooHeavyToDrag(grams: stick.grams, drag: verdict))
        }

        // The bite is what the thickness has to clear, and only when the thing
        // is on the floor: something held up at handle height is met by the
        // side of the beak, not by an arc that bottoms out above it.
        if stick.graspHeightMillimetres == nil,
           stick.thicknessMillimetres < closedTipHeight * 1000 {
            refusals.append(.tooThin(millimetres: stick.thicknessMillimetres))
        }
        if let height = stick.graspHeightMillimetres,
           Reach.graspTime(forHeight: height / 1000) == nil {
            refusals.append(.outOfReach(millimetres: height))
        }

        let minutes = 2 * stick.metresAway / walkSpeed / 60
        if minutes >= 1 {
            refusals.append(.tooFar(metres: stick.metresAway, minutes: minutes))
        }

        var steps: [Step] = [.approach(metres: stick.metresAway), .reachDown, .closeMouth]
        if dragging {
            // No lift and no settle: it never stands the load up, it leans
            // into it and walks.
            steps.append(.dragBack(metres: stick.metresAway))
        } else {
            steps.append(contentsOf: [.lift, .settle, .carryBack(metres: stick.metresAway)])
        }
        steps.append(.release)
        return Plan(stick: stick, steps: steps, refusals: refusals)
    }
}

// MARK: - saying it in plain language

extension Retrieval {

    /// Everyday things people ask a duck to fetch.
    ///
    /// THESE ARE ESTIMATES OF YOUR OBJECT, NOT MEASUREMENTS OF THE ROBOT, and
    /// the screen says so — every one is editable. The distinction matters: the
    /// robot's numbers in this file were measured or read out of upstream's
    /// config, and mixing a guess about a pencil in with them under the same
    /// styling would be the quiet kind of dishonesty this app avoids.
    public static let everydayObjects: [(word: String, grams: Double, millimetres: Double)] = [
        ("pencil", 6, 7),
        ("pen", 10, 10),
        ("chopstick", 5, 5),
        ("twig", 8, 10),
        ("stick", 20, 20),
        ("dowel", 25, 20),
        ("crayon", 7, 9),
        ("cork", 2, 22),
        ("ball", 30, 40),
        ("carrot", 60, 30),
        ("broom", 600, 25),
        ("mop", 700, 25),
        ("rake", 800, 28),
        ("umbrella", 400, 30),
    ]

    /// Things that are usually standing up, and roughly where you would take
    /// hold of them, millimetres off the floor.
    ///
    /// A LEANING BROOM IS NOT OUT OF REACH, it is a timing problem: the arc
    /// sweeps the mouth from 184 mm down to 35 mm, so a handle anywhere in
    /// that band is bitten by closing the jaw as the mouth passes it. 150 mm
    /// is where a broom handle crosses that band when it leans on a wall —
    /// an estimate of your broom, and editable like every other one.
    public static let usuallyStanding: [String: Double] = [
        "broom": 150, "mop": 150, "rake": 150, "umbrella": 120,
    ]

    /// What a sentence turned into, and how much of it was guessed.
    public struct Reading: Equatable, Sendable {
        public let stick: Stick
        /// Whether the sentence asked for a drag rather than a fetch.
        public var wantsDrag: Bool = false
        /// The word that matched, if the sentence named a thing.
        public let object: String?
        /// Facts taken from the sentence, in the sentence's own terms.
        public let understood: [String]
        /// Facts nobody supplied. THE UI MUST SHOW THESE — a plan built on
        /// three defaults and presented as an answer is a guess wearing a
        /// timeline.
        public let assumed: [String]
    }

    /// Read a plain sentence into something checkable.
    ///
    /// Deterministic on purpose. A model can phrase the request, and the app's
    /// drafter is welcome to hand its output through here, but the STRUCTURE —
    /// how heavy, how thick, how far, and therefore whether the duck can do it
    /// — is decided by code that runs under `swift test` on a Pi rather than by
    /// something that has to be online and might say anything.
    public static func read(_ sentence: String) -> Reading {
        let text = sentence.lowercased()
        var understood: [String] = []
        var assumed: [String] = []

        let object = everydayObjects.first { text.contains($0.word) }
        if let object { understood.append("a \(object.word)") }

        var grams = object?.grams
        if let (value, unit) = number(in: text, units: ["kg", "g", "gram", "grams"]) {
            grams = unit == "kg" ? value * 1000 : value
            understood.append(String(format: "%.0f g", grams!))
        } else if let object {
            assumed.append(String(format: "a %@ weighs about %.0f g", object.word, object.grams))
        }

        var thickness = object?.millimetres
        if let (value, unit) = number(in: text, units: ["mm", "cm"], near: ["thick", "wide", "across", "diameter"]) {
            thickness = unit == "cm" ? value * 10 : value
            understood.append(String(format: "%.0f mm thick", thickness!))
        } else if let object {
            assumed.append(String(format: "a %@ is about %.0f mm thick", object.word, object.millimetres))
        }

        var away: Double?
        if let (value, unit) = number(in: text, units: ["m", "metre", "metres", "meter", "meters", "cm"],
                                      near: ["away", "off", "from", "ahead"]) {
            away = unit == "cm" ? value / 100 : value
            understood.append(String(format: "%.1f m away", away!))
        }
        if away == nil, text.contains("across the room") {
            away = 4.0
            assumed.append("\"across the room\" taken as 4 m")
        }

        if grams == nil { assumed.append("weight unknown — taken as 20 g") }
        if thickness == nil { assumed.append("thickness unknown — taken as 20 mm") }
        if away == nil { assumed.append("distance unknown — taken as 1 m") }

        // Standing, leaning — or laid down, which puts it back on the floor.
        var height: Double? = nil
        let laidDown = ["laid down", "lying", "lying down", "on the floor", "flat", "on its side"]
            .contains { text.contains($0) }
        let standing = ["standing", "leaning", "upright", "against the wall", "propped"]
            .contains { text.contains($0) }
        if let (value, unit) = number(in: text, units: ["mm", "cm"],
                                      near: ["up", "high", "off the floor", "above"]) {
            height = unit == "cm" ? value * 10 : value
            understood.append(String(format: "held %.0f mm up", height!))
        } else if !laidDown, let word = object?.word, let usual = usuallyStanding[word] {
            if standing {
                height = usual
                understood.append("standing up")
                assumed.append(String(format: "you would take a %@ at about %.0f mm up",
                                      word, usual))
            } else {
                // A broom nobody described is a broom in the corner.
                height = usual
                assumed.append(String(format: "a %@ taken as standing, gripped %.0f mm up — "
                                    + "say \"laid down\" if it is on the floor", word, usual))
            }
        } else if laidDown {
            understood.append("laid down")
        }

        let wantsDrag = ["drag", "pull", "tow", "haul"].contains { text.contains($0) }
        if wantsDrag { understood.append("dragging it, not carrying it") }

        return Reading(
            stick: Stick(grams: grams ?? 20,
                         thicknessMillimetres: thickness ?? 20,
                         metresAway: away ?? 1.0,
                         graspHeightMillimetres: height),
            wantsDrag: wantsDrag,
            object: object?.word, understood: understood, assumed: assumed)
    }

    /// A number and its unit, optionally only when one of `near` appears within
    /// a few words after it — so "2 m away" gives a distance and "2 mm thick"
    /// does not.
    private static func number(in text: String, units: [String],
                               near: [String] = []) -> (Double, String)? {
        let pattern = "([0-9]+(?:\\.[0-9]+)?)\\s*(" + units.joined(separator: "|") + ")\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            guard let valueRange = Range(match.range(at: 1), in: text),
                  let unitRange = Range(match.range(at: 2), in: text),
                  let value = Double(text[valueRange]) else { continue }
            let unit = String(text[unitRange])
            if near.isEmpty { return (value, unit) }
            // Look at the twenty characters after the unit for a qualifier.
            let after = text[unitRange.upperBound...].prefix(20)
            if near.contains(where: { after.contains($0) }) { return (value, unit) }
        }
        return nil
    }

    /// The plan for a sentence, in one call.
    public static func plan(for sentence: String) -> (reading: Reading, plan: Plan) {
        let reading = read(sentence)
        return (reading, plan(for: reading.stick))
    }
}

// MARK: - keeping it

extension Retrieval.Plan {

    /// The plan as a `.duck` task, so it can be saved, read, shared and run by
    /// something other than this screen.
    ///
    /// THE BODY IS THE INTERESTING PART. A task file carries prose an agent
    /// reads, and what it needs to be told here is not "fetch the stick" — it
    /// is the four facts that decide whether fetching works at all. They are
    /// written into the body rather than left in this app, because a task that
    /// travels without its constraints is a task that gets run against a
    /// carrot.
    /// `.duck` names are slugs, so a title typed by a person is slugged here
    /// rather than thrown back at them — "Fetch the dowel" is a reasonable
    /// thing to type and `fetch-the-dowel` is what the format wants.
    public static func slug(_ title: String) -> String {
        let mapped = title.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        let parts = String(mapped).split(separator: "-", omittingEmptySubsequences: true)
        let slug = parts.joined(separator: "-")
        return slug.isEmpty ? "retrieval" : slug
    }

    public func duckTask(named name: String, author: String? = nil) throws -> DuckTask {
        let mm = Retrieval.closedTipHeight * 1000
        let slug = Retrieval.Plan.slug(name)
        let body = """
        # \(name)

        Fetch it and bring it back. Composed out of policies that already
        exist — there is no new network here, and none is needed.

        ## The order

        \(schedule.map { entry in
            String(format: "%.2f s  %@%@", entry.start, entry.step.label,
                   entry.step.policy.map { " (\($0))" } ?? " (servo 9, no policy)")
        }.joined(separator: "\n"))

        ## What decides whether this works

        - **The jaw closes \(String(format: "%.0f", mm)) mm above the floor.** The ground-pick
          policy is rewarded for reaching down and penalised for touching, so it
          never gets lower. Anything thinner passes under the bite.
        - **The grasp has to land between \(String(format: "%.2f", Retrieval.graspWindow.lowerBound)) s
          and \(String(format: "%.2f", Retrieval.graspWindow.upperBound)) s** after the pick starts,
          lowest at \(String(format: "%.2f", Retrieval.graspInstant)) s. This is measured from the
          policy, and it is EARLIER than the training config's nominal hold —
          closing on the config's window closes on the way up.
        - **10–40 g.** That is the payload the lift was trained against.
        - **It cannot pivot.** Every approach is an arc; standing still to turn
          saturates at about 14 degrees and stops.
        - **The pick is cut at phase 0.7**, so the rise does not quite finish.
          Let it settle before walking off.

        ## This object

        \(String(format: "%.0f g, %.0f mm thick, %.2f m away.",
                 stick.grams, stick.thicknessMillimetres, stick.metresAway))
        \(refusals.isEmpty ? "Inside every envelope."
                           : refusals.map { ($0.isFatal ? "REFUSED: " : "Warning: ") + $0.message }
                             .joined(separator: "\n"))
        """
        return try DuckTask(
            name: slug,
            summary: "Pick something light off the floor and bring it back.",
            author: author,
            verbs: .init(allow: ["walk_to", "ground_pick", "mouth", "stand"],
                         confirm: []),
            success: ["the object is back where the duck started",
                      "the duck is standing"],
            abortWhen: ["the object is not where it was expected",
                        "the duck falls",
                        "the lift leaves the mouth empty"],
            learnedVerbs: [],
            body: body)
    }
}

// MARK: - taking hold of something that is not on the floor, and pulling it

extension Retrieval {

    /// Grasping at a height, and dragging rather than lifting.
    ///
    /// A BROOM IS NOT A STICK, in two ways that matter. Leaning against a wall,
    /// the part you would bite is up in the air rather than on the floor — and
    /// the ground-pick arc sweeps the mouth through every height between 35 mm
    /// and 184 mm on its way down, so the grasp is a matter of TIMING, not of
    /// reaching somewhere new. And a broom is far too heavy to lift, which does
    /// not settle the question, because dragging is not lifting: the floor
    /// carries the weight and the duck only has to overcome friction.
    ///
    /// NOTHING HERE IS A MEASUREMENT OF DRAGGING. No such experiment exists.
    /// What follows are CEILINGS derived from things that are known — the
    /// robot's own mass out of the MJCF, the torque limit training runs at, the
    /// friction range training randomises over — and a ceiling is a statement
    /// about what is impossible, never a promise about what works.
    public enum Reach {

        /// The mouth's height at the top of the ground-pick arc, metres.
        /// Measured through the recorded clip: 0.184 m at t = 0.
        public static let highestDuringPick = 0.184

        /// And at the bottom, mouth open: 0.035 m.
        public static let lowestDuringPick = 0.035

        /// When the mouth passes each height on the way DOWN, seconds into the
        /// pick. Measured from the clip through DuckKit's kinematics.
        ///
        /// THE ARC PASSES EVERY HEIGHT TWICE, and the descending pass is the
        /// one to use: on the way up the duck is already committed to standing,
        /// and a bite taken then is a bite taken while pulling away.
        static let descent: [(height: Double, at: Double)] = [
            (0.150, 0.18), (0.120, 0.26), (0.100, 0.30),
            (0.080, 0.36), (0.060, 0.44), (0.040, 0.76),
        ]

        /// When to shut the jaw to catch something at `height`, or nil if the
        /// arc never reaches it.
        public static func graspTime(forHeight height: Double) -> Double? {
            guard height <= highestDuringPick, height >= lowestDuringPick else { return nil }
            // Below the table's last entry, the bottom of the arc is the answer.
            guard let first = descent.first(where: { height >= $0.height }) else {
                return Retrieval.graspInstant
            }
            // Between two rows, walk the line between them.
            guard let index = descent.firstIndex(where: { $0.height == first.height }),
                  index > 0 else { return first.at }
            let above = descent[index - 1]
            let span = above.height - first.height
            guard span > 1e-9 else { return first.at }
            let fraction = (above.height - height) / span
            return above.at + (first.at - above.at) * fraction
        }
    }

    /// What the duck can pull before something gives.
    public enum Drag {

        /// The robot's mass, kilograms. Summed from every `<inertial>` in
        /// Pollen's `pollen_robot.xml`.
        public static let duckMass = 0.7372

        /// Per-joint torque ceiling training runs at, newton-metres.
        /// `forcerange="-0.6405 0.6405"` in the training scene — tighter than
        /// the 0.96 the plain robot file declares, and the tighter one is what
        /// every shipped policy was trained against.
        public static let jointTorque = 0.6405

        /// Distance from the neck-pitch joint to the mouth tip in the sagittal
        /// plane at the home pose, metres. Measured through the kinematics.
        /// This is the lever a horizontal pull at the beak works through.
        public static let neckLever = 0.0836

        /// The friction range training randomises the feet over.
        /// `cfg.events["foot_friction"].params["ranges"] = (0.7, 1.3)`.
        public static let footFriction = 0.7...1.3

        static let gravity = 9.81

        /// How hard it can pull before its feet slide, newtons.
        public static func pullBeforeSlipping(footFriction: Double) -> Double {
            footFriction * duckMass * gravity
        }

        /// How hard it can pull before the neck stalls, newtons. One joint
        /// holding the load through one lever — a floor for the real answer,
        /// since nothing here models the head and neck sharing it.
        public static var pullBeforeNeckStalls: Double { jointTorque / neckLever }

        /// The binding ceiling at a given foot friction, and what binds.
        public static func ceiling(footFriction: Double) -> (newtons: Double, limit: String) {
            let feet = pullBeforeSlipping(footFriction: footFriction)
            let neck = pullBeforeNeckStalls
            return feet < neck
                ? (feet, "its feet slide before it pulls harder")
                : (neck, "its neck stalls before it pulls harder")
        }

        /// What it takes to drag something, newtons: friction times weight.
        public static func forceToDrag(kilograms: Double, floorFriction: Double) -> Double {
            floorFriction * kilograms * gravity
        }

        public enum Verdict: Equatable, Sendable {
            case within(needed: Double, ceiling: Double, limit: String)
            case beyond(needed: Double, ceiling: Double, limit: String)

            public var isWithin: Bool { if case .within = self { return true }; return false }

            public var message: String {
                switch self {
                case .within(let needed, let ceiling, _):
                    return String(format: "Dragging it needs about %.1f N and the duck has "
                        + "roughly %.1f N before something gives. That is a ceiling, not a "
                        + "demonstration — nobody has measured this duck dragging anything.",
                        needed, ceiling)
                case .beyond(let needed, let ceiling, let limit):
                    return String(format: "Dragging it needs about %.1f N. The duck runs out at "
                        + "roughly %.1f N — %@.", needed, ceiling, limit)
                }
            }
        }

        /// Can it drag this? At the WORST friction training covers, because a
        /// ceiling quoted at the best case is a ceiling that flatters.
        public static func verdict(kilograms: Double, floorFriction: Double,
                                   footFriction: Double = Drag.footFriction.lowerBound) -> Verdict {
            let needed = forceToDrag(kilograms: kilograms, floorFriction: floorFriction)
            let (ceiling, limit) = Drag.ceiling(footFriction: footFriction)
            return needed <= ceiling
                ? .within(needed: needed, ceiling: ceiling, limit: limit)
                : .beyond(needed: needed, ceiling: ceiling, limit: limit)
        }

        /// THE THING NO CEILING COVERS. Being pulled backwards while walking is
        /// not in any training distribution: the payload event hangs a weight
        /// at the mouth during a ground-pick rise, and the walking policy was
        /// trained with pushes, not with a load it is towing. Whether the duck
        /// stays upright while dragging is genuinely unknown, and no arithmetic
        /// here will settle it.
        public static let untestedNote =
            "Nothing has trained or measured a duck towing anything. The payload it knows "
            + "about is 10–40 g hanging at its mouth while it stands up, not a load it is "
            + "pulling along. Staying upright while dragging is the open question, and these "
            + "numbers do not answer it."
    }
}

// MARK: - reading a sentence against the things actually in a scene

extension Retrieval {

    /// The plan for a sentence, preferring a prop somebody has already
    /// described over anything guessed.
    ///
    /// A NAMED PROP BEATS THE CATALOGUE, ALWAYS. If you built a broom in a
    /// scene and gave it 800 g because yours is a heavy one, "drag the broom"
    /// has to mean 800 g — not the catalogue's 600. The estimates exist for
    /// the case where nobody has described anything yet, and they should lose
    /// the moment somebody has.
    public static func plan(for sentence: String,
                            props: [DuckScene.Prop]) -> (reading: Reading, plan: Plan) {
        var reading = read(sentence)
        let lowered = sentence.lowercased()
        guard let prop = props.first(where: { lowered.contains($0.name.lowercased()) }) else {
            return (reading, plan(for: reading.stick))
        }
        // Laying it down or standing it up is something the sentence can say
        // about a prop without editing the prop.
        var stick = prop.stick
        if ["laid down", "lying", "on the floor", "flat"].contains(where: { lowered.contains($0) }) {
            stick = Stick(grams: stick.grams,
                          thicknessMillimetres: stick.thicknessMillimetres,
                          metresAway: stick.metresAway,
                          graspHeightMillimetres: nil,
                          floorFriction: stick.floorFriction)
        }
        reading = Reading(
            stick: stick,
            wantsDrag: reading.wantsDrag,
            object: prop.name,
            understood: [String(format: "the %@ in your scene — %.0f g, %.0f mm across, %.2f m away",
                                prop.name.lowercased(), stick.grams,
                                stick.thicknessMillimetres, stick.metresAway)]
                + (stick.graspHeightMillimetres.map {
                    [String(format: "gripped %.0f mm up", $0)] } ?? ["lying on the floor"]),
            // Nothing was guessed: every number came from the prop.
            assumed: [])
        return (reading, plan(for: stick))
    }
}
