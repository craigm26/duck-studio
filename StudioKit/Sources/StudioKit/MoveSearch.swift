import Foundation
import DuckKit

/// Searching a MOVE's keyframes, as opposed to searching a network's weights.
///
/// TWO SEARCHES, ONE VOCABULARY, TWO HOSTS. `DuckTuner` searches twenty-eight
/// numbers that fold into a network's last layer and comes back with a file
/// robotd loads. This searches poses and times and comes back with a harness
/// intent the challenge replays. They cannot share a screen — one needs a base
/// policy and the other needs a move — so they share this package instead: the
/// same seeded generator, the same (1+λ) shape, the same refusal to report a
/// number nobody measured.
///
/// EDIT, SCORE, KEEP. Nothing here is trained and no gradient is computed. A
/// candidate is a set of offsets on the handles a person unlocked; it is played
/// on the challenge's own grid; the one that scored best is kept. `notTraining`
/// is that sentence in the words the screen shows.
///
/// SCORED ON `/climb`, STAIRS ONLY, AND THE REASON IS A MEASUREMENT.
/// `/perform` answers with a count out of eight and two summaries — an integer
/// gives a search no direction and no spread to measure against, which is the
/// exact shape `DuckTuner` refuses. `/climb` answers one cell at a time with
/// unrounded continuous fields, so `onlyTheStairs` is a not-yet with a reason
/// rather than a scope note.
public enum MoveSearch {

    // MARK: - what may move

    /// One direction the search is allowed to move in.
    ///
    /// A HANDLE IS A PERSON'S DECISION, NOT A DIMENSION THE APP CHOSE. Fifteen
    /// joints across six keyframes is eighty-four directions and no phone
    /// budget says anything about eighty-four directions, so everything starts
    /// held and each handle is one thing somebody actually suspects.
    public struct Handle: Equatable, Sendable, Codable, Identifiable {

        /// Which joints a pose handle moves.
        public enum Selection: Equatable, Sendable, Codable {
            /// A `JointGroup.title`.
            case group(String)
            /// An index into `DuckModel.jointNames`.
            case joint(Int)
        }

        public enum Kind: Equatable, Sendable, Codable {
            /// Keyed by `IntentDraft.Key.id`, NOT AN INDEX: sorting by time
            /// means an index names a different keyframe the moment one is
            /// dragged past its neighbour.
            case pose(keyframe: UUID, Selection)
            case time(keyframe: UUID)
            /// "blend" | "gap" | "side" | "approach"
            case shape(String)
        }

        public enum Unit: String, Equatable, Sendable, Codable {
            case degrees, seconds, bare
        }

        public let kind: Kind
        /// How far the search may move this handle, EITHER WAY, in `unit`.
        public let room: Double

        public init(kind: Kind, room: Double) {
            self.kind = kind
            self.room = room
        }

        public var unit: Unit {
            switch kind {
            case .pose:  return .degrees
            case .time:  return .seconds
            case .shape: return .bare
            }
        }

        /// Stable, readable, and not an index. `Point.offsets` is keyed by it.
        public var id: String {
            switch kind {
            case .pose(let keyframe, .group(let title)):
                return "pose:\(keyframe.uuidString):group:\(title)"
            case .pose(let keyframe, .joint(let index)):
                return "pose:\(keyframe.uuidString):joint:\(index)"
            case .time(let keyframe):
                return "time:\(keyframe.uuidString)"
            case .shape(let key):
                return "shape:\(key)"
            }
        }

        /// The keyframe this handle is about, or nil for a shape handle.
        public var keyframe: UUID? {
            switch kind {
            case .pose(let id, _): return id
            case .time(let id):    return id
            case .shape:           return nil
            }
        }

        /// What the row says: the moment and the thing, in a person's words.
        public func title(in move: StairsChallenge.Move) -> String {
            let draft = MoveSearch.draft(of: move)
            let moment = keyframe
                .flatMap { id in draft.keys.first { $0.id == id } }
                .map { String(format: "%.2f s", $0.time) }
            switch kind {
            case .pose(_, .group(let group)):
                return "\(moment ?? "a keyframe") · \(group.lowercased())"
            case .pose(_, .joint(let index)):
                return "\(moment ?? "a keyframe") · \(JointControl(index: index).plainName)"
            case .time:
                return "\(moment ?? "a keyframe") · when it happens"
            case .shape(let key):
                return "the move's \(key)"
            }
        }

        /// How the room reads on a row, in the handle's own unit.
        public var roomSaid: String {
            switch unit {
            case .degrees: return String(format: "±%.0f°", room)
            case .seconds: return String(format: "±%.2f s", room)
            case .bare:    return String(format: "±%.3f", room)
            }
        }
    }

    /// The four shape parameters a family used to GENERATE its keyframes, in
    /// the order the files write them.
    public static let shapeKeys = ["blend", "gap", "side", "approach"]

    // MARK: - the spec

    public struct Spec: Equatable, Sendable, Codable {
        public var moveFile: String
        public var rise: Double
        public var handles: [Handle]
        public var lambda: Int
        public var generations: Int
        public var seed: UInt64

        public init(moveFile: String, rise: Double, handles: [Handle],
                    lambda: Int, generations: Int, seed: UInt64) {
            self.moveFile = moveFile; self.rise = rise; self.handles = handles
            self.lambda = lambda; self.generations = generations; self.seed = seed
        }

        /// EVERYTHING STARTS HELD.
        public static func everythingHeld(_ file: String, rise: Double) -> Spec {
            Spec(moveFile: file, rise: rise, handles: [],
                 lambda: defaultLambda, generations: defaultGenerations, seed: 1)
        }

        public func with(handles: [Handle]) -> Spec {
            var copy = self; copy.handles = handles; return copy
        }

        public func handle(_ id: String) -> Handle? { handles.first { $0.id == id } }
    }

    /// The children and generations a fresh spec opens on. Small, because the
    /// budget below is counted in bench requests and a phone pays for each one.
    public static let defaultLambda = 4
    public static let defaultGenerations = 6
    /// Degrees a pose handle opens at, and the ends of the stepper.
    public static let defaultDegrees = 5.0
    public static let degreeRange = (low: 1.0, high: 20.0)
    /// Seconds a timing handle opens at.
    public static let defaultSeconds = 0.10

    // MARK: - a point in the space the handles describe

    public struct Point: Equatable, Sendable, Codable {
        /// `Handle.id` → offset, in that handle's unit.
        public var offsets: [String: Double]

        public init(offsets: [String: Double]) { self.offsets = offsets }

        public static let unchanged = Point(offsets: [:])

        public var isUnchanged: Bool { offsets.values.allSatisfy { $0 == 0 } }

        /// The residual, handle by handle, in the words the result section
        /// prints. Only handles that actually moved.
        public func described(_ spec: Spec, in move: StairsChallenge.Move) -> String {
            let moved = spec.handles.compactMap { handle -> String? in
                guard let offset = offsets[handle.id], offset != 0 else { return nil }
                switch handle.unit {
                case .degrees:
                    return String(format: "%@ %+.1f°", handle.title(in: move), offset)
                case .seconds:
                    return String(format: "%@ %+.3f s", handle.title(in: move), offset)
                case .bare:
                    return String(format: "%@ %+.4f", handle.title(in: move), offset)
                }
            }
            return moved.isEmpty ? "Nothing moved: the move as written scored best."
                                 : moved.joined(separator: "\n")
        }
    }

    // MARK: - the budget, which is the headline

    /// How many children one direction needs before a result about it means
    /// anything.
    public static let candidatesPerDimension = 6

    public struct Budget: Equatable, Sendable {
        public let dimensions: Int
        /// generations × lambda
        public let candidates: Int
        /// The fourteen-cell baseline.
        public let baselineRequests: Int
        /// Two scored runs per handle, on the core nine.
        public let swingRequests: Int
        /// Every child, on the core nine.
        public let searchRequests: Int
        /// The five the search never sees.
        public let checkRequests: Int
        /// What a search costs in children per direction, before it is thin.
        public let resolvable: Int

        public var totalRequests: Int {
            baselineRequests + swingRequests + searchRequests + checkRequests
        }

        /// A search over more directions than its children can resolve is a
        /// search that reports a number about nothing. Zero directions is not
        /// resolvable either — there is no search without a handle.
        public var isResolvable: Bool { dimensions >= 1 && dimensions <= resolvable }

        /// COUNTED, NOT ESTIMATED. Every one of these is one `/climb` request
        /// this app is about to send, and a screen that rounded them would be
        /// quoting somebody else's machine.
        public var described: String {
            "\(dimensions) handle\(dimensions == 1 ? "" : "s") unlocked. "
          + "\(baselineRequests) cells to measure this move as written, "
          + "\(swingRequests) to measure what each handle is worth, "
          + "\(searchRequests) for \(candidates) versions across the search, and "
          + "\(checkRequests) held back to check the winner on conditions it never saw. "
          + "That is \(totalRequests) requests to the bench, counted rather than estimated, "
          + "one cell each."
        }
    }

    public static func budget(for spec: Spec) -> Budget {
        let core = StairsChallenge.Grid.coreCount
        let candidates = max(spec.generations, 0) * max(spec.lambda, 0)
        return Budget(
            dimensions: spec.handles.count,
            candidates: candidates,
            baselineRequests: StairsChallenge.Grid.count,
            swingRequests: spec.handles.count * 2 * core,
            searchRequests: candidates * core,
            checkRequests: StairsChallenge.Grid.count - core,
            resolvable: candidates / candidatesPerDimension)
    }

    public static func budgetTooThin(dimensions: Int, resolvable: Int) -> String {
        "\(dimensions) handles are unlocked and this many children can resolve \(resolvable). "
      + "A search that spends \(candidatesPerDimension) children per direction is a search whose "
      + "answer is about the directions; one that spends fewer is a number about noise. Lock "
      + "some handles, or raise the generations and the children per generation — the cost above "
      + "is what that buys."
    }

    // MARK: - the room a handle actually has

    /// What a pose handle can actually deliver, before a joint hits its stop.
    public struct Headroom: Equatable, Sendable {
        /// Degrees each way before the tightest joint in the selection stops.
        public let up: Double, down: Double
        /// Degrees the person asked for.
        public let asked: Double
        /// The joint that binds first, by wire name.
        public let bindingJoint: String?
        /// How many OTHER joints in the selection also have less room than was
        /// asked for, on at least one side.
        public let othersTighter: Int

        /// What the search is guaranteed BOTH ways. Never more than was asked.
        public var delivered: Double { Swift.min(asked, Swift.min(up, down)) }

        public var sentence: String {
            let binder = bindingJoint.map { " before \(MotionTweak.plainName($0)) hits its stop" }
                ?? ""
            let others = othersTighter > 0
                ? " \(othersTighter) other joint\(othersTighter == 1 ? "" : "s") in this "
                + "selection \(othersTighter == 1 ? "is" : "are") also inside what you asked for."
                : ""
            // THE SECOND CLAUSE IS WHAT THE CLAMP DELIVERS, not the joint's
            // room: `mutate` clamps to ±room, so a joint with more travel than
            // was asked for still moves by what was asked.
            return String(format: "You asked ±%.0f°. This keyframe has %.1f° up and %.1f° down%@, "
                                + "so the search gets %.1f° one way and %.1f° the other.%@",
                          asked, up, down, binder,
                          Swift.min(asked, up), Swift.min(asked, down), others)
        }
    }

    /// The room a handle has, or nil where the idea does not apply — a timing
    /// or shape handle has no joint stop to run into.
    public static func headroom(_ handle: Handle, in move: StairsChallenge.Move) -> Headroom? {
        guard case .pose(let keyframe, let selection) = handle.kind,
              let key = draft(of: move).keys.first(where: { $0.id == keyframe }) else { return nil }
        let joints = MoveSearch.joints(of: selection)
        guard !joints.isEmpty else { return nil }
        var up = Double.infinity, down = Double.infinity
        var binder: String?
        var tighter = 0
        for joint in joints where key.pose.indices.contains(joint) {
            let travel = DuckModel.jointRanges[joint]
            let upRoom = degrees(travel.upper - key.pose[joint])
            let downRoom = degrees(key.pose[joint] - travel.lower)
            if Swift.min(upRoom, downRoom) < Swift.min(up, down) {
                binder = DuckModel.jointNames[joint]
            }
            up = Swift.min(up, upRoom); down = Swift.min(down, downRoom)
            if Swift.min(upRoom, downRoom) < handle.room { tighter += 1 }
        }
        guard up.isFinite, down.isFinite else { return nil }
        // The binding joint is itself one of the tight ones; the sentence is
        // about the OTHERS.
        return Headroom(up: Swift.max(up, 0), down: Swift.max(down, 0), asked: handle.room,
                        bindingJoint: binder, othersTighter: Swift.max(tighter - 1, 0))
    }

    static func joints(of selection: Handle.Selection) -> [Int] {
        switch selection {
        case .group(let title):
            return JointGroup.all.first { $0.title == title }?.joints ?? []
        case .joint(let index):
            return DuckModel.jointNames.indices.contains(index) ? [index] : []
        }
    }

    static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
    static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

    // MARK: - the keyframe identities a handle is keyed by

    /// The draft a move opens as, WITH KEYFRAME IDENTITIES THAT DO NOT MOVE.
    ///
    /// `Move.toDraft()` mints a fresh `UUID` per keyframe on every call, which
    /// is right for the editor — a draft is a new document — and wrong for a
    /// handle: a spec saved to disk on Monday would name nothing on Tuesday,
    /// and `apply` would resolve no handle at all on the second call inside one
    /// run. So the identity is DERIVED from the keyframe itself: its ordinal in
    /// the file, its time and its pose, mixed into a v4-shaped UUID.
    ///
    /// WHY NOT AN INDEX, WHICH IS WHAT THIS LOOKS LIKE. Because it is not one.
    /// An index names a different keyframe the moment one is dragged past its
    /// neighbour; this names the same keyframe as long as that keyframe is the
    /// same keyframe, and stops naming anything the moment somebody edits it —
    /// which is exactly when a handle's measured headroom went stale.
    /// `SearchSpecStore` drops such a handle and counts it rather than
    /// re-homing it onto a neighbour.
    public static func draft(of move: StairsChallenge.Move) -> IntentDraft {
        var draft = move.toDraft()
        let frames = move.keyframes
        draft.keys = draft.keys.enumerated().map { index, key in
            var seed = "\(move.name)|\(index)|"
            if frames.indices.contains(index) {
                seed += HarnessJSON.literal(for: frames[index].t) + "|"
                seed += frames[index].pose.map(HarnessJSON.literal(for:)).joined(separator: ",")
            }
            return IntentDraft.Key(id: derivedIdentity(seed), time: key.time, pose: key.pose)
        }
        return draft
    }

    /// A UUID from a string, deterministically. FNV-1a twice over, with the
    /// version and variant nibbles set so what comes out is a well-formed
    /// UUID rather than sixteen bytes wearing one's clothes.
    static func derivedIdentity(_ seed: String) -> UUID {
        func fnv(_ text: String, offset: UInt64) -> UInt64 {
            var hash = offset
            for byte in Array(text.utf8) {
                hash ^= UInt64(byte)
                hash = hash &* 0x100000001B3
            }
            return hash
        }
        let low = fnv(seed, offset: 0xCBF29CE484222325)
        let high = fnv(seed + "·", offset: 0x84222325CBF29CE4)
        var bytes = [UInt8]()
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((high >> UInt64(shift)) & 0xFF))
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((low >> UInt64(shift)) & 0xFF))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    // MARK: - applying a point

    public enum Refusal: Error, Equatable {
        case notThisMove(String)
        case mouthIsNotSearched
        case shapeHasNoDeclaredBounds(String)
        case leftItsBox(cells: Int)
        case partialGrid(answered: Int, of: Int)
        case noBaselineYet
        case timesWouldCollide(Double)

        public var message: String {
            switch self {
            case .notThisMove(let id):
                return "A handle names a keyframe this move does not have any more (\(id)). It "
                     + "is dropped rather than moved onto a neighbour: a lock that lands on the "
                     + "wrong keyframe is worse than no lock."
            case .mouthIsNotSearched:
                return MoveSearch.mouthIsNotSearched
            case .shapeHasNoDeclaredBounds(let key):
                return MoveSearch.shapeNeedsDeclaredBounds
                     + " The field asked for is \(key)."
            case .leftItsBox(let cells):
                return "The bench refused \(cells) cell\(cells == 1 ? "" : "s") as outside this "
                     + "move's own declared search bounds. That is a file that is not a result, "
                     + "so nothing here is scored — a mean over the cells that did answer would "
                     + "be a number about the half that stayed inside the box."
            case .partialGrid(let answered, let total):
                return "\(answered) of \(total) cells came back. A score is the whole grid: a "
                     + "mean over the ones that answered is not this move's number, and it is "
                     + "not comparable with anything published."
            case .noBaselineYet:
                return "Nothing has measured this move as written yet, and every number a search "
                     + "reports is a difference from that. Measure it first."
            case .timesWouldCollide(let time):
                return String(format: "That timing window would push two keyframes onto the same "
                                    + "instant at %.2f s. Two poses at one moment is not a "
                                    + "transition, so the window is refused rather than clamped "
                                    + "into one.", time)
            }
        }
    }

    /// The move a point describes.
    ///
    /// THE CLAMP IS HERE AND IT IS LOAD-BEARING. `IntentDraft.exported()` does
    /// not clamp — it REFUSES, with "left_hip_yaw is outside its travel at
    /// 0.50 s" — which `PreferenceSearch` found the hard way at `legDepth` 1.45
    /// on a motion whose hip was already deep. A search that could produce a
    /// move the app then refuses to export is a dead end with a stepper on it,
    /// so every pose lands inside `DuckModel.jointRanges` before it leaves.
    public static func apply(_ point: Point, to move: StairsChallenge.Move,
                             spec: Spec) throws -> StairsChallenge.Move {
        var edited = draft(of: move)
        var json = move.json

        for handle in spec.handles {
            let offset = point.offsets[handle.id] ?? 0
            switch handle.kind {

            case .pose(let keyframe, let selection):
                let joints = MoveSearch.joints(of: selection)
                guard !joints.contains(DuckModel.mouthIndex) else {
                    throw Refusal.mouthIsNotSearched
                }
                guard let index = edited.keys.firstIndex(where: { $0.id == keyframe }) else {
                    throw Refusal.notThisMove(handle.id)
                }
                guard offset != 0 else { continue }
                var pose = edited.keys[index].pose
                for joint in joints where pose.indices.contains(joint) {
                    let travel = DuckModel.jointRanges[joint]
                    pose[joint] = Swift.min(Swift.max(pose[joint] + radians(offset),
                                                      travel.lower), travel.upper)
                }
                edited.keys[index] = IntentDraft.Key(id: keyframe,
                                                     time: edited.keys[index].time, pose: pose)

            case .time(let keyframe):
                guard let index = edited.keys.firstIndex(where: { $0.id == keyframe }) else {
                    throw Refusal.notThisMove(handle.id)
                }
                guard offset != 0 else { continue }
                let moved = Swift.max(edited.keys[index].time + offset, 0)
                for (other, key) in edited.keys.enumerated() where other != index {
                    if abs(key.time - moved) < MotionTweak.sameInstant {
                        throw Refusal.timesWouldCollide(moved)
                    }
                }
                edited.keys[index] = IntentDraft.Key(id: keyframe, time: moved,
                                                     pose: edited.keys[index].pose)

            case .shape(let key):
                guard let bounds = declaredBounds(for: key, in: move) else {
                    throw Refusal.shapeHasNoDeclaredBounds(key)
                }
                guard offset != 0 else { continue }
                let current = json[key]?.doubleValue ?? 0
                let moved = Swift.min(Swift.max(current + offset, bounds.low), bounds.high)
                json = json.setting(key, to: .number(moved))
            }
        }

        return try StairsChallenge.Move(json: json).applying(draft: edited)
    }

    /// The search box the FILE ITSELF declares for one shape field, or nil.
    ///
    /// NIL IS THE ANSWER FOR SEVENTEEN OF THE NINETEEN, and that is a not-yet
    /// rather than an oversight: see `shapeNeedsDeclaredBounds`.
    public static func declaredBounds(for key: String,
                                      in move: StairsChallenge.Move) -> (low: Double,
                                                                         high: Double)? {
        guard let pair = move.json["bounds"]?[key]?.arrayValue, pair.count == 2,
              let low = pair[0].doubleValue, let high = pair[1].doubleValue,
              high > low else { return nil }
        return (low, high)
    }

    /// Whether this move carries a landing law — an event or servo block on top
    /// of the keyframes. A caveat, never an exclusion: see
    /// `landingLawNotSearched`.
    public static func carriesALandingLaw(_ move: StairsChallenge.Move) -> Bool {
        move.hasEvent || move.hasServo
    }

    /// Whether this move still carries the params block its keyframes were
    /// generated from.
    public static func carriesParams(_ move: StairsChallenge.Move) -> Bool {
        move.json["params"] != nil
    }

    // MARK: - the objective

    /// One cell's contribution, and the flight gate that is the whole reason it
    /// is not just a height.
    ///
    /// MEASURED, AND THE MEASUREMENT IS WHY THE GATE EXISTS.
    /// `peakAboveTread_mm` is `maxZ − (rise + dh)`, so a duck that never moves
    /// is already about 66 mm above a 60 mm tread: on the four climb fixtures
    /// this app ships, `ctrl_do_nothing` scores 0.592345 on reach × stability
    /// alone — a number that sits above three of the nine core cells of the
    /// published 4-of-9 vault, and above six of the fourteen cells of the
    /// 5-of-9 one. That is the same hole `DuckTuner` documents in a different
    /// reward, closed the same way: by the bench's own criterion rather than a
    /// new one. `reachedFlight` is the bench saying the trunk crossed the riser
    /// line or a foot rested on a tread. A cell that did neither earns nothing.
    ///
    /// (The plan this was built from said "above six of the nine core cells of
    /// the published 4-of-9 vault". Recomputed over the shipped fixtures it is
    /// three of nine — the ungated mean clears 0.160000, 0.566838 and 0.536049
    /// and nothing else. `MoveSearchObjectiveTests` asserts the counts that are
    /// true, and the mean itself reproduces the plan's 0.592345 exactly.)
    public static func cellScore(_ c: DuckBench.Climbed) -> Double {
        guard c.reachedFlight, !c.invalid else { return 0 }
        let reach = Swift.min(Swift.max(c.peakAboveTreadMillimetres, 0),
                              StairsChallenge.barMillimetres) / StairsChallenge.barMillimetres
        let ticks = Swift.max(c.tailTicks, 1)
        let stability = Swift.min(Swift.max(Double(c.uprightTailTicks) / Double(ticks), 0), 1)
        return reach * stability
    }

    public struct Reading: Equatable, Sendable {
        /// The mean over the core nine. THIS APP'S NUMBER, not the audit's.
        public let objective: Double
        public let perCore: [Double]
        public let perExtended: [Double]
        public let reachedFlightCells: Int
        /// The audit's own counts, so this app's number never travels alone.
        public let audit: StairsChallenge.Score

        public init(objective: Double, perCore: [Double], perExtended: [Double],
                    reachedFlightCells: Int, audit: StairsChallenge.Score) {
            self.objective = objective; self.perCore = perCore
            self.perExtended = perExtended; self.reachedFlightCells = reachedFlightCells
            self.audit = audit
        }

        /// Both numbers in one line — this app's continuous stand-in and the
        /// integer it stands in for.
        public var line: String {
            String(format: "%.4f over the core nine · %@", objective, audit.verdict)
        }
    }

    /// Fourteen answered cells, read.
    ///
    /// AN INVALID CELL REFUSES THE WHOLE READING rather than scoring zero: a
    /// file outside its own declared bounds is not a move that failed, it is a
    /// file that is not a result, and averaging a zero in would report a bad
    /// score for an episode that never ran.
    public static func reading(_ cells: [DuckBench.Climbed]) throws -> Reading {
        let invalid = cells.filter(\.invalid).count
        guard invalid == 0 else { throw Refusal.leftItsBox(cells: invalid) }
        guard cells.count == StairsChallenge.Grid.count else {
            throw Refusal.partialGrid(answered: cells.count, of: StairsChallenge.Grid.count)
        }
        let core = cells.filter { $0.cell.tier == .core }.map(cellScore)
        let extended = cells.filter { $0.cell.tier == .ext }.map(cellScore)
        return Reading(objective: core.isEmpty ? 0 : core.reduce(0, +) / Double(core.count),
                       perCore: core, perExtended: extended,
                       reachedFlightCells: cells.filter(\.reachedFlight).count,
                       audit: StairsChallenge.Score(rise: cells.first?.rise ?? 0, cells: cells))
    }

    /// The core-nine mean of whatever cells are in hand, for a generation line
    /// mid-run where the grid is nine and not fourteen.
    public static func coreMean(_ cells: [DuckBench.Climbed]) -> Double {
        let core = cells.filter { $0.cell.tier == .core }
        guard !core.isEmpty else { return 0 }
        return core.map(cellScore).reduce(0, +) / Double(core.count)
    }

    // MARK: - the spread, and the verdict

    /// The PAIRED per-cell difference, candidate minus baseline.
    ///
    /// REFUSED FOR FEWER THAN TWO VALUES, ANY NON-FINITE VALUE, OR A SPREAD OF
    /// EXACTLY ZERO — the same three refusals `DuckTuner.noiseFloor` makes,
    /// over a different set and for the same reasons. `/climb` cells are
    /// deterministic, so this is NOT a noise floor: repeating a cell is not an
    /// independent sample. It is the spread BETWEEN CONDITIONS, which is what
    /// every sentence that prints it calls it.
    public static func conditionSpread(_ differences: [Double]) -> Double? {
        guard differences.count >= 2, differences.allSatisfy(\.isFinite),
              let low = differences.min(), let high = differences.max() else { return nil }
        guard high > low else { return nil }
        return high - low
    }

    public static func heldOutVerdict(meanGain: Double, conditionSpread: Double,
                                      flightKept: Int, baselineFlight: Int) -> String {
        guard flightKept >= baselineFlight else {
            return "It reached flight in \(flightKept) of the checked cells where the move as "
                 + "written reached it in \(baselineFlight). A score that went up while the duck "
                 + "stopped getting off the floor is the hole this objective exists to refuse, "
                 + "and no gain rescues it."
        }
        guard meanGain > conditionSpread else {
            return String(format: "It did not survive the conditions it was not searched on: "
                                + "%+.4f on average against a spread of %.4f between those same "
                                + "cells. What the search found on the nine it scored did not "
                                + "carry. That is the usual outcome here and it is a real "
                                + "answer.", meanGain, conditionSpread)
        }
        return String(format: "It survived: %+.4f on average across cells the search never saw, "
                            + "against a spread of %.4f between them.", meanGain, conditionSpread)
    }

    // MARK: - the swing table

    /// One handle, moved to each end of its own room, and what the score did.
    ///
    /// A FINITE DIFFERENCE OVER TWO SCORED RUNS. Not a gradient — nothing here
    /// differentiates anything — and not a ranking of importance. The sentence
    /// says "the score swung", which is the whole claim.
    public struct Swing: Equatable, Sendable, Identifiable {
        public let handle: Handle
        public let base: Double, up: Double, down: Double

        public init(handle: Handle, base: Double, up: Double, down: Double) {
            self.handle = handle; self.base = base; self.up = up; self.down = down
        }

        public var swing: Double { Swift.max(abs(up - base), abs(down - base)) }

        public var direction: String {
            if up > base && up >= down { return "deeper" }
            if down > base { return "shallower" }
            return "neither way"
        }

        public var id: String { handle.id }
    }

    /// Above the measured spread, and under it. A handle under the spread is
    /// UNRANKED, never "a small effect" — with no spread measured, nothing can
    /// be ranked at all and everything is under it.
    public static func ranked(_ swings: [Swing], spread: Double?)
        -> (above: [Swing], below: [Swing]) {
        guard let spread else { return (above: [], below: swings) }
        let above = swings.filter { $0.swing > spread }.sorted { $0.swing > $1.swing }
        let below = swings.filter { $0.swing <= spread }.sorted { $0.swing > $1.swing }
        return (above: above, below: below)
    }

    public static func swingLine(_ s: Swing, in move: StairsChallenge.Move) -> String {
        String(format: "%@ — the score swung %.2f when this moved %@.",
               s.handle.title(in: move), s.swing, s.handle.roomSaid)
    }

    public static func swingsUnderTheSpread(_ n: Int, spread: Double) -> String {
        String(format: "%d handle%@ swung the score by less than %.4f, which is how much these "
                     + "conditions move it on their own. They are not ranked: a swing under the "
                     + "spread is a swing this grid cannot tell from the conditions, and calling "
                     + "it a small effect would be claiming a measurement nobody made.",
               n, n == 1 ? "" : "s", spread)
    }

    // MARK: - the run

    /// One child. REUSES `DuckTuner.Seeded` VERBATIM — a second SplitMix64 is a
    /// second generator to get wrong.
    public static func mutate(_ parent: Point, with spec: Spec,
                              using rng: inout DuckTuner.Seeded) -> Point {
        var offsets: [String: Double] = [:]
        for handle in spec.handles {
            let step = handle.room * 0.5 * rng.gaussian()
            let moved = (parent.offsets[handle.id] ?? 0) + step
            offsets[handle.id] = Swift.min(Swift.max(moved, -handle.room), handle.room)
        }
        return Point(offsets: offsets)
    }

    /// ONE HANDLE AT THE END OF ITS OWN ROOM, EVERYTHING ELSE UNTOUCHED. This
    /// is what the swing table is measured with: two real scored runs per
    /// handle, at +room and −room.
    public static func probe(_ spec: Spec, handle: Handle, direction: Double) -> Point {
        Point(offsets: [handle.id: handle.room * (direction >= 0 ? 1 : -1)])
    }

    public enum Rejection: String, Equatable, Sendable {
        case invalid, neverReachedFlight

        public var message: String {
            switch self {
            case .invalid:
                return "Rejected: the bench refused this version as outside the move's own "
                     + "declared search bounds. That is a search that left its box rather than a "
                     + "result, and it is thrown out before any number is compared."
            case .neverReachedFlight:
                return "Rejected: in every searched cell the trunk never crossed the riser line "
                     + "and no foot ever rested on a tread. There is nothing in that episode for "
                     + "a height to be a height above."
            }
        }
    }

    /// Why a candidate is thrown away before a number is compared, or nil.
    ///
    /// THERE IS NO SATURATED-TORQUE REJECTION, AND THAT IS A MEASUREMENT.
    /// `maxTq` is exactly 0.6405 in fourteen of fourteen cells for BOTH
    /// published vaults; only the two non-climbing controls sit near 0.09.
    /// Saturation is the normal operating state of a working vault, so a
    /// rejection on it would throw out the parent move before generation 1 and
    /// every child after it, and the screen could never produce a number.
    public static func rejected(_ cells: [DuckBench.Climbed]) -> Rejection? {
        guard !cells.isEmpty else { return nil }
        if cells.contains(where: \.invalid) { return .invalid }
        if !cells.contains(where: \.reachedFlight) { return .neverReachedFlight }
        return nil
    }

    public struct Generation: Equatable, Sendable, Identifiable {
        public let index: Int
        public let best: Double
        public let rejectedAsInvalid: Int
        public let rejectedAsNeverReachedFlight: Int

        public init(index: Int, best: Double, rejectedAsInvalid: Int,
                    rejectedAsNeverReachedFlight: Int) {
            self.index = index; self.best = best
            self.rejectedAsInvalid = rejectedAsInvalid
            self.rejectedAsNeverReachedFlight = rejectedAsNeverReachedFlight
        }

        public var id: Int { index }
    }

    public static func generationLine(_ g: Generation) -> String {
        var line = String(format: "Generation %d: best %.4f over the core nine", g.index, g.best)
        var thrown: [String] = []
        if g.rejectedAsInvalid > 0 { thrown.append("\(g.rejectedAsInvalid) outside the box") }
        if g.rejectedAsNeverReachedFlight > 0 {
            thrown.append("\(g.rejectedAsNeverReachedFlight) never reached flight")
        }
        line += thrown.isEmpty ? "." : " — \(thrown.joined(separator: ", "))."
        return line
    }

    /// Handles a stored spec named and this move no longer has.
    public static func handlesDropped(_ n: Int) -> String {
        "\(n) saved handle\(n == 1 ? "" : "s") named \(n == 1 ? "a keyframe" : "keyframes") this "
      + "move no longer has, so \(n == 1 ? "it was" : "they were") dropped rather than moved onto "
      + "the nearest neighbour. A lock that lands on the wrong keyframe is worse than no lock, "
      + "and it would be invisible for a whole run."
    }

    // MARK: - the sentences

    public static let notTraining =
        "This is not training and it is not a reward model. No gradient is computed here and "
      + "nothing is learned: a search changes the poses and times you unlocked, plays each "
      + "version on the challenge's own grid, and keeps the one that scored best. You edit, the "
      + "bench scores, you decide what to keep."

    public static let whatItSearches =
        "What moves is exactly what you unlock: a keyframe's pose for one group of joints, or "
      + "one joint, or when that keyframe happens. Everything else is held. The move's own shape "
      + "parameters move only where the file declares bounds for them."

    public static let everythingIsHeldToStart =
        "Everything starts held. A search over fifteen joints across six keyframes is eighty-four "
      + "directions, and no budget a phone can spend tells you anything about eighty-four "
      + "directions. Unlock the two or three you actually suspect."

    public static let mouthIsNotSearched =
        "The mouth is not offered. A harness pose is the fourteen joints a policy commands and "
      + "the mouth is the one they all skip, so a mouth edit never reaches the bench — a search "
      + "that spent children on it would report a number for a joint the score cannot depend on."

    public static let reachIsNotZeroAtRest =
        "A standing duck's trunk is already about 66 mm above a 60 mm tread, so height alone is "
      + "not a measure of climbing: on this app's own fixtures the do-nothing control scores "
      + "0.59 out of 1 on height and stillness together. Nothing scores at all until the bench "
      + "says the duck reached flight — that the trunk crossed the riser line, or a foot rested "
      + "on a tread."

    public static let nothingToImproveYet =
        "This move does not reach flight in any cell the search would score on, so every version "
      + "of it scores zero and there is nothing for the search to climb. That is a real answer "
      + "and not a failure: get the duck off the floor first — by hand, in the motion editor — "
      + "and then come back."

    public static let howMuchTheConditionsMove =
        "Measured on the two published vaults this app ships, one leaderboard place apart: cell "
      + "by cell their scores differ by an average of 0.004 on the five conditions a winner is "
      + "checked on, and that difference swings by 0.91 across those five cells. The conditions "
      + "move this score far more than the gap between two expert moves does. The usual honest "
      + "outcome of a run here is that nothing cleared the spread."

    public static let objectiveIsOurs =
        "This number is this app's, not the audit's. The audit counts cells: how many of nine the "
      + "duck cleared and stayed up in. That is an integer, and an integer over nine cells cannot "
      + "tell a search which way to go. So each cell is scored on how far the trunk's peak got "
      + "toward the 95 mm bar, times how much of the fifty-tick tail it stayed upright for, and "
      + "zero unless the bench says it reached flight. The audit's own count is reported beside "
      + "it, every time, and it is the one to quote."

    public static let aScoreHereIsNotALeaderboardRow =
        "Each version in the search is scored on nine of the fourteen cells and checked on the "
      + "other five. Only the winner gets a fourteen-cell score, and that is the one comparable "
      + "with a published row. The running numbers above it are not."

    public static let noBlendPerTransition =
        "There is no per-transition blend to search. A keyframe carries a time and a pose; what "
      + "happens between two of them is a smoothstep DuckKit applies, with no parameter, and no "
      + "bench would see one if this app invented it. Moving a keyframe's time is the one thing "
      + "that changes a transition, and it changes the two either side of it."

    public static let theOtherBlend =
        "The word blend also names something else in a challenge file: a shape parameter the "
      + "family that wrote the move used to GENERATE its keyframes. It is offered above, where "
      + "the file declares bounds for it. Two different things with one name, and the timing "
      + "controls only ever mean the gap between two poses."

    public static let shapeNeedsDeclaredBounds =
        "This move declares no search bounds for that field, so this app will not move it. The "
      + "bench refuses a move that left its declared bounds; a move that never had any is not "
      + "inside them, it is a search with no box drawn — which is worse, because nothing would "
      + "refuse it."

    public static let landingLawNotSearched =
        "This move carries a landing law — an event or servo block the family that wrote it "
      + "added on top of the keyframes. It is kept exactly as written and it is not searched, so "
      + "what you are editing is the keyframes underneath a rule that will still fire. Read the "
      + "result knowing that half the move did not move."

    public static let paramsAreNowStale =
        "This file still carries the params block the original keyframes were generated from. "
      + "This search edited the keyframes and did not touch it, so those parameters no longer "
      + "produce this move. The keyframes are what the bench replays; the block is kept because "
      + "the move's own hash folds parts of it in, and dropping it would change the identity."

    public static let onlyTheStairs =
        "Only stairs moves can be searched. /climb is the one route that answers with a graded "
      + "number for an authored move — how high the trunk got, how long it stayed up, cell by "
      + "cell. /perform answers with a count out of eight and two summaries; a count gives a "
      + "search no direction and no spread to measure against, so this app does not pretend to "
      + "search on it."

    /// The swing table before any held-out check has run on THIS move: the
    /// numbers are real, the ranking is missing because nothing measured the
    /// spread, not because a measurement failed.
    /// The two search-size controls. Every number a sentence can write is a
    /// control on the screen a person could have set, and can change back.
    public static let generationsSaid = "Generations"
    public static let childrenSaid = "Children per generation"
    /// The ranges the words path clamps to; the steppers share them so the
    /// two paths cannot disagree about what a number may be.
    public static let generationsRange = 1...40
    public static let childrenRange = 1...20

    public static let spreadNotMeasuredYet =
        "No held-out check has run on this move yet, so there is no measured spread to rank "
      + "these swings against. The numbers below are real measurements; the ranking is missing "
      + "because nothing has measured the spread, not because a measurement failed."

    public static let noConditionSpread =
        "Fewer than two checked cells came back, or they all differed by exactly the same amount, "
      + "so the spread across conditions could not be measured — and without it there is no way "
      + "to say whether anything mattered. The versions are kept and the ranking is not, because "
      + "a ranking against an invented floor is worse than none."

    /// Said on the tune screen, where somebody came looking for "the search"
    /// and meant the other one.
    public static let theOtherSearchIsHere =
        "The search on this screen changes a network's numbers. The one that changes a move's "
      + "poses and times is its own screen, under Measure."
}

// MARK: - the arithmetic the run needs, kept out of the app target

extension MoveSearch {

    /// The PAIRED per-cell difference, candidate minus baseline, over cells
    /// that are the same cell. Paired because the conditions are the thing that
    /// moves this score most: comparing two unpaired means would be comparing
    /// two different sets of conditions and calling the difference a result.
    public static func pairedDifferences(candidate: [DuckBench.Climbed],
                                         baseline: [DuckBench.Climbed]) -> [Double] {
        let base = Dictionary(baseline.map { ($0.cell.id, cellScore($0)) },
                              uniquingKeysWith: { first, _ in first })
        return candidate.compactMap { cell in
            guard let was = base[cell.cell.id] else { return nil }
            return cellScore(cell) - was
        }
    }

    public static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    public static func flightCells(_ cells: [DuckBench.Climbed]) -> Int {
        cells.filter(\.reachedFlight).count
    }

    /// One keyframe in a person's words: the joints that are away from where
    /// the robot stands, and by how much.
    ///
    /// THE SAME VOCABULARY THE EDITOR AND THE WORDS PATH USE.
    /// `MotionTweak.describe` writes the whole table for a model to read; this
    /// writes one row for a person to read, out of the one joint vocabulary, so
    /// a row and a sentence cannot name the same joint two ways.
    public static func describe(keyframe key: IntentDraft.Key,
                                in move: StairsChallenge.Move) -> String {
        let moved = MotionProposal.jointVocabulary.compactMap { entry -> String? in
            guard entry.joint != "mouth",
                  let slot = DuckModel.jointIndex(of: entry.joint),
                  key.pose.indices.contains(slot) else { return nil }
            let away = degrees(key.pose[slot] - DuckModel.homePose[slot])
            guard abs(away) >= 1 else { return nil }
            return String(format: "%@ %+.0f°", entry.word, away)
        }
        return moved.isEmpty ? "standing" : moved.joined(separator: ", ")
    }

    /// How far through the counted budget a run is, said as a count.
    public static func progressLine(done: Int, of total: Int) -> String {
        "\(done) of \(total) cells asked for."
    }

    /// The fourteen-cell score of a winner: its nine core from the generation
    /// that produced it, plus the five extended from the held-out check.
    ///
    /// ASSEMBLED RATHER THAN RE-RUN, because those are the cells that were
    /// actually scored — re-running them would be a second measurement quoted
    /// under the first one's verdict.
    public static func winnersScore(rise: Double, core: [DuckBench.Climbed],
                                    extended: [DuckBench.Climbed]) -> StairsChallenge.Score {
        StairsChallenge.Score(rise: rise, cells: core + extended)
    }
}
