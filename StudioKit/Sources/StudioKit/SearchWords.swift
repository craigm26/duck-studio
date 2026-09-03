import Foundation
import DuckKit

/// Words that change a SEARCH, on either of the two screens that run one.
///
/// ONE READER, TWO HOSTS. The sentence goes to `DraftEngine.ask(…, kind:
/// .search, instructions:)` — the existing three-engine router, no new engine
/// and no new reader, so every non-Apple path still lands in
/// `ChatWire.firstJSONObject`. What comes back is a flat `Reading`; what it is
/// applied to is either a `MoveSearch.Spec` (the keyframe search) or a
/// `DuckTuner.Schedule` (the policy search). Anything a host has no seat for is
/// refused BY NAME rather than ignored.
///
/// EVERY NUMBER A SENTENCE WRITES IS A CONTROL THE PERSON COULD HAVE SET
/// THEMSELVES. There is no read-only proposal here: the words land in the spec,
/// the spec is drawn as steppers and toggles, and the person edits them by
/// hand afterwards. A sentence that produced nothing produces NO SEAL —
/// `nothingWasRead` in the refusal colour and an untouched spec, which is
/// `AutomationChatView`'s rule applied to a different surface.
///
/// AND IT MAY NOT MOVE WHAT THE SCORE IS. A weight asked for is read so that it
/// can be refused by name; it is never applied. `termWeightsAreNotYours` says
/// why, and `DuckTuner.whatWordsMayNotChange` says it again where the six
/// weights are on screen.
public enum SearchWords {

    // MARK: - what a sentence can ask for

    public enum Edit: Equatable, Sendable {
        /// Stop searching a part. `at` nil means everywhere in the move.
        case hold(word: String, at: Double?)
        /// Search a part, with how far it may move.
        case free(word: String, at: Double?, degrees: Double)
        /// Let a keyframe's moment move, by this many seconds either way.
        case time(at: Double, seconds: Double)
        /// One of the move's declared shape parameters.
        case shape(key: String, span: Double)
        case generations(Int)
        case children(Int)
        case rise(Double)
        /// READ SO IT CAN BE REFUSED BY NAME. Never applied.
        case termWeight(term: String, weight: Double)
    }

    public struct Reading: Equatable, Sendable {
        public let summary: String
        public let edits: [Edit]
        public init(summary: String, edits: [Edit]) {
            self.summary = summary; self.edits = edits
        }
    }

    public struct Outcome: Equatable, Sendable {
        public let spec: MoveSearch.Spec
        public let notes: [String]
        public let refusals: [String]
        public init(spec: MoveSearch.Spec, notes: [String], refusals: [String]) {
            self.spec = spec; self.notes = notes; self.refusals = refusals
        }
    }

    // MARK: - what cannot be resolved

    public enum Failure: Error, Equatable {
        case nothingUnderstood
        case unknownJoint(String, closest: String?)
        case noKeyframeNear(Double)

        public var reason: String {
            switch self {
            case .nothingUnderstood:
                return "Nothing in that named a part of the duck, a moment, or a number this "
                     + "search has a control for."
            case .unknownJoint(let word, let closest):
                let hint = closest.map { " The nearest name is \"\($0)\"." }
                    ?? " The parts are: " + MotionProposal.jointVocabulary.map(\.word)
                        .joined(separator: ", ") + "."
                return "\"\(word)\" is not a part this robot has.\(hint)"
            case .noKeyframeNear(let time):
                return String(format: "There is no keyframe within %.2f s of %.2f s, so that "
                                    + "instruction names a moment this move does not have.",
                              MotionTweak.nearEnough, time)
            }
        }

        /// When the whole sentence failed.
        public var message: String { reason + " Nothing was changed." }
        /// When part of it landed and this part did not.
        public var skipped: String { reason + " That instruction was skipped." }
    }

    // MARK: - what the model is told

    /// The instructions, built from the SAME vocabulary the resolver matches
    /// against and the SAME keyframe table the motion editor shows — so the
    /// words offered and the words that resolve are one list.
    public static func instructions(for move: StairsChallenge.Move,
                                    spec: MoveSearch.Spec) -> String {
        let shapes = MoveSearch.shapeKeys
            .filter { MoveSearch.declaredBounds(for: $0, in: move) != nil }
        let shapeLine = shapes.isEmpty
            ? "This move declares no searchable shape parameters, so do not ask for one."
            : "This move declares search bounds for: \(shapes.joined(separator: ", "))."
        return """
        You change the SETTINGS of a search over an existing move for a 25 cm \
        robot duck. You do not write a move and you do not score one. You decide \
        which parts of which keyframes the search may touch, and how far.

        \(MotionTweak.describe(MoveSearch.draft(of: move)))

        \(MotionProposal.grounding())

        Everything starts held. "hold" stops a part being searched; "free" starts \
        it, with a number of degrees it may move either way. A moment in seconds \
        names one of the keyframes above. \(shapeLine)

        Right now \(spec.handles.count) handle\(spec.handles.count == 1 ? " is" : "s are") \
        unlocked, over \(spec.generations) generations of \(spec.lambda) versions each.

        You may NOT change what the score is. There is no reward weight here and \
        no term to weigh.

        Answer with JSON and nothing else. No explanation, no markdown fence.
        Exactly this shape:
        {"summary":"what you changed","edits":[{"hold":"hips","at":0.42},\
        {"free":"left leg","at":0.42,"degrees":5},{"at":0.42,"time":0.1},\
        {"generations":6}]}
        """
    }

    // MARK: - reading it

    /// A flat `Reading`. ANYTHING IT DOES NOT UNDERSTAND IS DROPPED, NEVER
    /// GUESSED — a guessed lock lands on the wrong keyframe for a whole run
    /// and nobody sees it.
    public static func read(fromJSON json: String) throws -> Reading {
        guard let data = json.data(using: .utf8),
              let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.nothingUnderstood
        }
        let summary = (top["summary"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var edits: [Edit] = []
        for raw in (top["edits"] as? [[String: Any]]) ?? [] {
            let at = number(raw["at"])
            if let term = raw["term"] as? String, let weight = number(raw["weight"]) {
                edits.append(.termWeight(term: term, weight: weight))
                continue
            }
            if let word = raw["hold"] as? String {
                edits.append(.hold(word: word, at: at))
                continue
            }
            if let word = raw["free"] as? String {
                edits.append(.free(word: word, at: at,
                                   degrees: number(raw["degrees"]) ?? MoveSearch.defaultDegrees))
                continue
            }
            if let seconds = number(raw["time"]), let at {
                edits.append(.time(at: at, seconds: seconds))
                continue
            }
            if let key = raw["shape"] as? String, let span = number(raw["span"]) {
                edits.append(.shape(key: key, span: span))
                continue
            }
            if let generations = number(raw["generations"]) {
                edits.append(.generations(Int(generations)))
                continue
            }
            if let children = number(raw["children"]) ?? number(raw["lambda"]) {
                edits.append(.children(Int(children)))
                continue
            }
            if let rise = number(raw["rise"]) {
                edits.append(.rise(rise))
                continue
            }
        }
        guard !edits.isEmpty else { throw Failure.nothingUnderstood }
        return Reading(summary: summary, edits: edits)
    }

    static func number(_ any: Any?) -> Double? {
        if let value = any as? Double { return value }
        if let value = any as? Int { return Double(value) }
        if let text = any as? String { return Double(text) }
        return nil
    }

    // MARK: - applying it to a keyframe search

    /// Every edit resolved against THIS move and THIS spec.
    ///
    /// THROWS ONLY WHEN NOTHING AT ALL LANDED AND NOTHING WAS REFUSED BY NAME.
    /// A refusal by name — the mouth, a term weight, a shape field with no
    /// declared bounds — is an answer and comes back in `refusals`. A
    /// resolution failure with nothing else to show for the sentence is a
    /// failure, and it throws with "Nothing was changed." so no seal is drawn
    /// over an untouched spec.
    public static func outcome(_ reading: Reading, applyingTo spec: MoveSearch.Spec,
                               move: StairsChallenge.Move) throws -> Outcome {
        let draft = MoveSearch.draft(of: move)
        let ordered = draft.keys.enumerated().sorted { $0.element.time < $1.element.time }
        var handles = spec.handles
        var result = spec
        var notes: [String] = []
        var refusals: [String] = []
        var failures: [Failure] = []

        /// The keyframe a stated moment means, its human index and its time.
        func keyframe(at time: Double) -> (id: UUID, index: Int, time: Double)? {
            guard let index = MotionTweak.nearestIndex(to: time, in: draft) else { return nil }
            let key = draft.keys[index]
            let human = (ordered.firstIndex { $0.offset == index } ?? index) + 1
            return (key.id, human, key.time)
        }

        func moment(_ index: Int, _ time: Double) -> String {
            String(format: "keyframe %d, %.2f s", index, time)
        }

        for edit in reading.edits {
            switch edit {

            case .termWeight(let term, _):
                refusals.append(termWeightsAreNotYours + " The weight asked for was \(term).")

            case .hold(let word, let at):
                guard let targets = MotionTweak.targets(for: word) else {
                    failures.append(.unknownJoint(word, closest: MotionProposal.closest(to: word)))
                    continue
                }
                let joints = Set(targets.compactMap { DuckModel.jointIndex(of: $0.joint) })
                guard !joints.contains(DuckModel.mouthIndex) else {
                    refusals.append(MoveSearch.mouthIsNotSearched)
                    continue
                }
                var wanted: UUID?
                var where_ = "everywhere in this move"
                if let at {
                    guard let found = keyframe(at: at) else {
                        failures.append(.noKeyframeNear(at))
                        continue
                    }
                    wanted = found.id
                    where_ = "at " + moment(found.index, found.time)
                }
                let before = handles.count
                handles.removeAll { handle in
                    guard case .pose(let key, let selection) = handle.kind else { return false }
                    if let wanted, key != wanted { return false }
                    return !Set(MoveSearch.joints(of: selection)).isDisjoint(with: joints)
                }
                let removed = before - handles.count
                notes.append(removed == 0
                    ? "\"\(word)\" was already held \(where_)."
                    : "\(word) held \(where_) — "
                    + "\(removed) handle\(removed == 1 ? "" : "s") removed.")

            case .free(let word, let at, let degrees):
                guard let targets = MotionTweak.targets(for: word) else {
                    failures.append(.unknownJoint(word, closest: MotionProposal.closest(to: word)))
                    continue
                }
                let joints = targets.compactMap { DuckModel.jointIndex(of: $0.joint) }
                guard !joints.contains(DuckModel.mouthIndex) else {
                    refusals.append(MoveSearch.mouthIsNotSearched)
                    continue
                }
                guard let at else {
                    refusals.append(freeNeedsAMoment)
                    continue
                }
                guard let found = keyframe(at: at) else {
                    failures.append(.noKeyframeNear(at))
                    continue
                }
                let room = min(max(abs(degrees), MoveSearch.degreeRange.low),
                               MoveSearch.degreeRange.high)
                var added = 0
                for joint in joints {
                    let handle = MoveSearch.Handle(
                        kind: .pose(keyframe: found.id, .joint(joint)), room: room)
                    guard !handles.contains(where: { $0.id == handle.id }) else { continue }
                    handles.append(handle)
                    added += 1
                }
                notes.append(String(format: "%@ free to move ±%.0f° at %@ — %d handle%@ added.",
                                    word, room, moment(found.index, found.time), added,
                                    added == 1 ? "" : "s"))

            case .time(let at, let seconds):
                guard let found = keyframe(at: at) else {
                    failures.append(.noKeyframeNear(at))
                    continue
                }
                let room = min(max(abs(seconds), 0.01), 0.5)
                let handle = MoveSearch.Handle(kind: .time(keyframe: found.id), room: room)
                if !handles.contains(where: { $0.id == handle.id }) { handles.append(handle) }
                notes.append(String(format: "%@ may move ±%.2f s.",
                                    moment(found.index, found.time), room))

            case .shape(let key, let span):
                guard MoveSearch.shapeKeys.contains(key) else {
                    refusals.append(MoveSearch.shapeNeedsDeclaredBounds
                                  + " The field asked for is \(key).")
                    continue
                }
                guard let bounds = MoveSearch.declaredBounds(for: key, in: move) else {
                    refusals.append(MoveSearch.shapeNeedsDeclaredBounds
                                  + " The field asked for is \(key).")
                    continue
                }
                let room = min(max(abs(span), 1e-4), (bounds.high - bounds.low) / 2)
                let handle = MoveSearch.Handle(kind: .shape(key), room: room)
                if !handles.contains(where: { $0.id == handle.id }) { handles.append(handle) }
                notes.append(String(format: "%@ may move ±%.4f, inside the file's own declared "
                                          + "%.4f to %.4f.", key, room, bounds.low, bounds.high))

            case .generations(let value):
                let clamped = min(max(value, 1), 40)
                result.generations = clamped
                notes.append("\(clamped) generations.")

            case .children(let value):
                let clamped = min(max(value, 1), 20)
                result.lambda = clamped
                notes.append("\(clamped) versions per generation.")

            case .rise(let value):
                let metres = value > 1 ? value / 1000 : value
                let snapped = StairsChallenge.rises
                    .min { abs($0 - metres) < abs($1 - metres) } ?? StairsChallenge.defaultRise
                result.rise = snapped
                notes.append("Scored at \(StairsChallenge.riseSaid(snapped)).")
            }
        }

        result.handles = handles
        // NOTHING LANDED AND NOTHING WAS REFUSED BY NAME: the sentence failed,
        // and it says so with "Nothing was changed." rather than handing back an
        // untouched spec under a seal. A refusal BY NAME — the mouth, a term
        // weight, a shape field with no declared bounds — is an answer, so it
        // comes back in `refusals` and the spec comes back untouched beside it.
        if notes.isEmpty, refusals.isEmpty {
            throw failures.first ?? Failure.nothingUnderstood
        }
        return Outcome(spec: result, notes: notes,
                       refusals: refusals + failures.map(\.skipped))
    }

    // MARK: - the sentences

    public static let nothingWasRead =
        "Nothing in that changed the search. Try naming a part and a moment — \"hold the hips in "
      + "the second pose\", \"let the left leg move 5° at the launch\"."

    public static let termWeightsAreNotYours =
        "A weight was asked for and none was set. There is no reward to weigh here: the score is "
      + "the bench's own measurement of one cell, and the app is not going to invent a second one "
      + "from a sentence. On the policy search the weights are read out of Pollen's own training "
      + "config for the same reason — a search optimising a second copy of them would be climbing "
      + "a hill the rest of the app cannot see."

    public static let freeNeedsAMoment =
        "Freeing a part needs a moment as well as a name: a handle is one keyframe's pose, not "
      + "the whole move's. Say which pose — \"let the left leg move 5° at 0.42 s\" — and it "
      + "lands on that keyframe."

    /// Apple's on-device path, on both screens.
    public static func appleHandsBackOneValue(_ name: String) -> String {
        "\(name) hands back one typed value, which is the shape it guarantees. A search change is "
      + "a list — hold this, free that, ten degrees — and there is no typed shape here for a "
      + "list, the same reason the motion editor asks a server for its edits. Add a server or "
      + "download a model onto this phone; every number either one asks for is checked here "
      + "afterwards."
    }
}
