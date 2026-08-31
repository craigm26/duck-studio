import Foundation
import DuckKit

/// Learning a motion from what somebody prefers, entirely on the phone.
///
/// WHAT THIS IS, IN THE TERMS THE FIELD USES. It is preference-based policy
/// search: no reward function is written down, no reward model is fitted, and
/// no gradient is taken. A person is shown two candidates, says which is
/// better, and the search moves. The human IS the objective. That is the
/// oldest and least glamorous member of the RLHF family and the only one that
/// fits in a pocket.
///
/// WHY IT WORKS HERE AND WOULD NOT WORK ON A POLICY. A motion is OPEN LOOP:
/// keyframes, interpolated, played. Drawing one needs kinematics and nothing
/// else. A locomotion policy is a feedback controller around contact, and
/// `DuckSimulation`'s own doc comment records — with tests — that closing that
/// loop on a phone produces "a fixed point or an oscillation, never a walk",
/// because gyro, projected gravity and joint velocity all arrive through
/// contact and a dependency-free Swift package has no contact. So a policy
/// cannot be rolled out here and a motion can. That is the whole reason this
/// type is about motions.
///
/// WHAT MAKES IT HONEST AT THIRTY COMPARISONS. Preference search resolves
/// roughly as many directions as it has comparisons to spend, and a person
/// will spend tens, not thousands. So the space is deliberately tiny and
/// NAMED: five knobs a person can actually see the effect of, not fifteen
/// joints times N keyframes. `resolution` says how many of those five the
/// answers so far can actually support, and it is allowed to say "none yet".
public struct PreferenceSearch: Equatable, Sendable {

    /// One thing about a motion that a person can see and judge.
    ///
    /// NAMED KNOBS, NOT RAW KEYFRAMES, and the reason is the budget. Perturbing
    /// 15 joints across N keyframes is a space with hundreds of directions in
    /// it; thirty comparisons cannot tell you anything about hundreds of
    /// directions. Five things somebody can name — and see the difference in —
    /// is a space thirty answers can actually move through.
    public enum Knob: String, CaseIterable, Equatable, Sendable, Identifiable {
        /// How far the legs travel from the pose the motion was written around.
        case legDepth
        /// The same for the neck and head.
        case headDepth
        /// How far the mouth opens, which no policy can drive at all.
        case mouthTravel
        /// The whole motion, faster or slower.
        case tempo
        /// How much of the motion is spent arriving rather than holding.
        case lead

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .legDepth:     return "Leg depth"
            case .headDepth:    return "Head travel"
            case .mouthTravel:  return "Mouth"
            case .tempo:        return "Tempo"
            case .lead:         return "Lead-in"
            }
        }

        /// What moving this actually does to the file, said plainly — because
        /// somebody choosing between two ducks deserves to know what changed.
        public var effect: String {
            switch self {
            case .legDepth:
                return "scales every leg joint's distance from the standing pose"
            case .headDepth:
                return "scales the neck and head the same way"
            case .mouthTravel:
                return "scales how far the mouth opens — joint 9, which no policy drives"
            case .tempo:
                return "stretches or compresses every keyframe time"
            case .lead:
                return "moves the first keyframe later or earlier, so the motion has more or "
                     + "less run-up before it commits"
            }
        }

        /// How far this knob may go from 1.0, either way.
        ///
        /// NOT A TASTE SETTING. Past these the motion stops being a variant of
        /// the one somebody wrote and becomes a different motion, and a search
        /// that wanders that far is not answering the question it was asked.
        /// A joint's own travel is applied on top by `apply(_:to:)` — the span
        /// is how far the KNOB may go, not how far the joint will actually
        /// move, and a deep pose reaches its stop well before the knob reaches
        /// its span.
        public var span: Double {
            switch self {
            case .legDepth, .headDepth, .mouthTravel: return 0.45
            case .tempo:                              return 0.35
            case .lead:                               return 0.30
            }
        }
    }

    /// A point in knob space. 1.0 on every knob is the motion as written.
    public struct Settings: Equatable, Sendable {
        public var values: [Knob: Double]

        public init(_ values: [Knob: Double] = [:]) {
            var v = values
            for k in Knob.allCases where v[k] == nil { v[k] = 1 }
            self.values = v
        }

        public static let unchanged = Settings()

        public subscript(_ knob: Knob) -> Double {
            get { values[knob] ?? 1 }
            set { values[knob] = min(max(newValue, 1 - knob.span), 1 + knob.span) }
        }

        /// The knobs this differs from the original on, largest first — what a
        /// screen says when somebody asks what they have been choosing.
        public var moved: [(Knob, Double)] {
            Knob.allCases
                .map { ($0, self[$0]) }
                .filter { abs($0.1 - 1) > 0.02 }
                .sorted { abs($0.1 - 1) > abs($1.1 - 1) }
        }
    }

    /// One answer. **"Cannot tell" is a first-class answer**, and the reason is
    /// that forcing a choice manufactures signal: two motions a person cannot
    /// distinguish carry no information about which direction is better, and
    /// recording a coin flip as a preference is how a search convinces itself
    /// of something nobody said.
    public enum Answer: String, Equatable, Sendable {
        case left, right, cannotTell
    }

    public struct Comparison: Equatable, Sendable {
        public let left: Settings
        public let right: Settings
        public let answer: Answer
        public init(left: Settings, right: Settings, answer: Answer) {
            self.left = left; self.right = right; self.answer = answer
        }
    }

    /// Where the search currently believes the best motion is.
    public private(set) var best: Settings
    /// Every answer, in order, including the ones that said nothing.
    public private(set) var history: [Comparison]
    /// Which knob the next pair will vary. One at a time, because a pair that
    /// differs on three knobs tells you which PAIR was preferred and nothing
    /// about which knob did the work.
    public private(set) var knob: Knob
    /// How far the next pair steps, which shrinks as answers accumulate.
    public private(set) var step: Double

    public init(best: Settings = .unchanged, knob: Knob = .legDepth) {
        self.best = best
        self.history = []
        self.knob = knob
        self.step = 1
    }

    /// How many comparisons have actually said something.
    public var decided: Int { history.filter { $0.answer != .cannotTell }.count }

    /// How many knobs the answers so far can support a claim about.
    ///
    /// A DELIBERATELY MEAN NUMBER. Preference search needs several answers per
    /// direction before a direction means anything, and this app would rather
    /// under-claim what thirty taps bought than over-claim it. Five decided
    /// answers per knob, and it never reports more knobs than have actually
    /// been varied.
    public var resolution: Int {
        let varied = Set(history.filter { $0.answer != .cannotTell }
                                .compactMap { differingKnob($0.left, $0.right) })
        return min(decided / 5, varied.count)
    }

    /// What the search is entitled to say about itself.
    public var standing: String {
        // EMPTY, NOT UNDECIDED. The guard used to be `decided > 0`, so a person
        // whose only answer was "cannot tell" was told nothing had been chosen
        // — which erased the one thing they HAD said.
        guard !history.isEmpty else {
            return "Nothing has been chosen yet, so this is the motion exactly as it was written."
        }
        let skipped = history.count - decided
        let skippedNote = skipped == 0 ? ""
            : " \(skipped) pair\(skipped == 1 ? " was" : "s were") too close to call, which is "
            + "an answer and is kept as one."
        guard decided > 0 else {
            return "No pair has been decided yet — every one so far was too close to call, which "
                 + "is itself worth knowing: these knobs may not be moving anything you can see."
        }
        guard resolution > 0 else {
            return "\(decided) choice\(decided == 1 ? "" : "s") so far — not yet enough to say "
                 + "any one of these knobs is settled, so treat this as a motion you are "
                 + "steering rather than one that has been tuned.\(skippedNote)"
        }
        return "\(decided) choices, enough to have moved \(resolution) of "
             + "\(Knob.allCases.count) knobs with any confidence. This is your preference on "
             + "this phone, not a measurement — nothing here has been run in physics."
             + skippedNote
    }

    /// The two candidates to show next.
    ///
    /// THEY DIFFER ON EXACTLY ONE KNOB. A pair that differs on several answers
    /// a different question — which of these two motions do you like — and the
    /// search cannot spend that answer, because it does not say which change
    /// did the work.
    public func nextPair() -> (left: Settings, right: Settings) {
        var a = best, b = best
        let delta = knob.span * 0.6 * step
        a[knob] = best[knob] - delta
        b[knob] = best[knob] + delta
        return (a, b)
    }

    /// Take an answer and move.
    public mutating func record(_ answer: Answer, left: Settings, right: Settings) {
        history.append(Comparison(left: left, right: right, answer: answer))
        switch answer {
        case .left:  best = left
        case .right: best = right
        case .cannotTell:
            // NOTHING MOVES, AND THE STEP SHRINKS. Two candidates a person
            // cannot tell apart are too far apart to be interesting or too
            // close to matter; either way the honest response is to stop
            // asking this question at this size.
            step *= 0.6
        }
        advance()
    }

    /// Move to the next knob, and shrink the step once every knob has had a turn.
    private mutating func advance() {
        let order = Knob.allCases
        guard let i = order.firstIndex(of: knob) else { return }
        let next = order.index(after: i)
        if next == order.endIndex {
            knob = order[0]
            step *= 0.75
        } else {
            knob = order[next]
        }
        step = max(step, 0.15)
    }

    private func differingKnob(_ a: Settings, _ b: Settings) -> Knob? {
        Knob.allCases.first { abs(a[$0] - b[$0]) > 1e-9 }
    }

    // MARK: - applying a point in knob space to an actual motion

    /// The motion these settings describe.
    ///
    /// EVERY ANGLE IS CLAMPED TO THE JOINT'S OWN TRAVEL, and the first version
    /// of this comment claimed `IntentDraft` would do that for us. It does not
    /// — it REFUSES: `exported()` throws "left_hip_yaw is outside its travel at
    /// 0.50 s". The test that walks every knob to both ends of its span caught
    /// it at `legDepth` 1.45 on a motion whose hip was already deep, which is
    /// not an exotic case; it is the second thing anybody will try. A knob that
    /// can produce a motion the app then refuses to export is a dead end with a
    /// slider on it.
    ///
    /// So the clamp is here, against `DuckModel.jointRanges`, and the knob
    /// stops mattering at the stop rather than pushing past it. Scaling is
    /// around `DuckModel.homePose`, because that is the pose a motion is
    /// written against and the one a policy returns to.
    public static func apply(_ s: Settings, to draft: IntentDraft) -> IntentDraft {
        let home = DuckModel.homePose
        let legs = Set(JointGroup.all.filter { $0.title.hasSuffix("leg") }.flatMap(\.joints))
        let head = Set(JointGroup.all.first { $0.title == "Neck and head" }?.joints ?? [])
        let mouth = DuckModel.mouthIndex

        let ordered = draft.keys.sorted { $0.time < $1.time }
        let firstTime = ordered.first?.time ?? 0
        let span = max((ordered.last?.time ?? 0) - firstTime, 1e-6)

        var out = draft
        out.keys = ordered.map { key in
            var pose = key.pose
            for j in 0..<min(pose.count, home.count) {
                let scale: Double
                if j == mouth { scale = s[.mouthTravel] }
                else if legs.contains(j) { scale = s[.legDepth] }
                else if head.contains(j) { scale = s[.headDepth] }
                else { scale = 1 }
                let scaled = home[j] + (pose[j] - home[j]) * scale
                let travel = DuckModel.jointRanges[j]
                pose[j] = min(max(scaled, travel.lower), travel.upper)
            }
            // Tempo stretches the whole span; lead moves where it starts.
            let fraction = (key.time - firstTime) / span
            let leadShift = (s[.lead] - 1) * span * 0.5
            let time = max(0, firstTime + leadShift + fraction * span * s[.tempo])
            return IntentDraft.Key(id: key.id, time: time, pose: pose)
        }
        return out
    }
}
