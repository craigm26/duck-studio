import Foundation
import DuckKit

/// One scene: what the duck is asked to do, and the machine facts that let a
/// reader reproduce the ask.
///
/// `id` IS A FILENAME AS WELL AS A KEY. Their `FrameStore` builds paths out of
/// it, and the harness's own cell label is `0.0/0.12/1.0/core`, which contains
/// slashes. So a cell becomes `cell-060mm-d120-f10-core` here and the harness's
/// label rides in `scene_metadata` where it can be read and cannot become a
/// directory.
public struct EvalScene: Equatable, Sendable, Identifiable {

    public let id: String
    /// What this scene asks for, in words, which is what makes a log
    /// self describing to somebody who was not there.
    public let instruction: String
    /// The command schedule, for a `/tune` scene.
    public let command: [DuckBench.Step]?
    /// The grid cell, for a `/climb` scene.
    public let cell: DuckBench.Cell?
    /// The grid cell, for a `/chase` scene.
    public let chaseCell: DuckBench.ChaseCell?
    /// The rise a climb cell is measured against, before `cell.dh`.
    public let rise: Double?
    /// Anything else worth writing into `scene_metadata`.
    public let metadata: [String: EvalLogJSON]

    public init(id: String, instruction: String, command: [DuckBench.Step]? = nil,
                cell: DuckBench.Cell? = nil, chaseCell: DuckBench.ChaseCell? = nil,
                rise: Double? = nil, metadata: [String: EvalLogJSON] = [:]) {
        self.id = id
        self.instruction = instruction
        self.command = command
        self.cell = cell
        self.chaseCell = chaseCell
        self.rise = rise
        self.metadata = metadata
    }

    /// `^[A-Za-z0-9._-]+$`, which is what a scene id has to be to survive being
    /// used as a path component.
    public var idIsFilesystemSafe: Bool {
        !id.isEmpty && id.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "_" || $0 == "-"
        }
    }

    /// A climb cell's scene id: `cell-060mm-d120-f10-core`.
    public static func id(for cell: DuckBench.Cell, rise: Double) -> String {
        let millimetres = Int(((rise + cell.dh) * 1000).rounded())
        return "cell-\(pad(millimetres, 3))mm-d\(Int((cell.drop * 1000).rounded()))"
             + "-f\(Int((cell.fmul * 10).rounded()))-\(cell.tier.rawValue)"
    }

    /// A chase cell's scene id: `ball-bp20-r070-d120-f10-core`. The bearing's
    /// sign becomes a letter because a minus sign in a filename is a flag on
    /// somebody's command line.
    public static func id(for cell: DuckBench.ChaseCell) -> String {
        let degrees = Int(cell.bearing.rounded())
        let sign = degrees == 0 ? "0" : (degrees > 0 ? "p" : "m")
        return "ball-b\(sign)\(pad(abs(degrees), 2))-r\(pad(Int((cell.range * 100).rounded()), 3))"
             + "-d\(Int((cell.drop * 1000).rounded()))-f\(Int((cell.fmul * 10).rounded()))"
             + "-\(cell.tier.rawValue)"
    }

    static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return text.count >= width ? text
             : String(repeating: "0", count: width - text.count) + text
    }

    /// What a command schedule is asking for, in a sentence, so the instruction
    /// and the schedule cannot drift apart.
    public static func walkInstruction(command: [DuckBench.Step], seconds: Double) -> String {
        let driven = command.last ?? DuckBench.Step(at: 0)
        var parts: [String] = []
        if driven.vx != 0 { parts.append("forward at \(number(driven.vx)) m/s") }
        if driven.vy != 0 { parts.append("sideways at \(number(driven.vy)) m/s") }
        if driven.vyaw != 0 { parts.append("turning at \(number(driven.vyaw)) rad/s") }
        let ask = parts.isEmpty ? "nothing at all" : parts.joined(separator: ", ")
        let from = driven.at > 0 ? " from \(number(driven.at)) seconds in" : ""
        return "Go \(ask)\(from), and still be standing at \(number(seconds)) seconds."
    }

    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
    }
}

/// A whole evaluation: the scenes, the scorers, one horizon, and the epoch
/// axis.
///
/// A PRESET IS A WHOLE PLAN AND NOT A STARTING POINT. Picking one fills the
/// scenes, the axis, the reducer, the horizon and the scorers, and the only
/// thing left to choose is the policy. That is what keeps the tap budget at
/// eight, and it is also what keeps a person from assembling a combination
/// nobody has thought about.
///
/// THE DEFAULT PRESET ASKS FOR THREE COMMANDS, WHICH IS A DEFECT FIX RATHER
/// THAN A FLOURISH. Four of eight tuner winners collapsed sideways travel to
/// under two per cent of the unchanged network's while passing every gate this
/// app had, and one collapsed yaw by 93 per cent with the reward going up. An
/// evaluation that only ever asks for forward is the exact thing this feature
/// exists to catch, so the default asks for all three and reports them as three
/// rows a mean cannot hide one behind.
public struct EvalTask: Equatable, Sendable, Identifiable {

    /// The three bench routes that can produce a per episode record.
    public enum Route: String, Equatable, Sendable, CaseIterable {
        case tune, climb, chase

        /// The path, which is already in `DuckBench.routes`. No new route is
        /// added by this feature.
        public var path: String {
            switch self {
            case .tune: return "/tune"
            case .climb: return "/climb"
            case .chase: return "/chase"
            }
        }

        /// Only `/tune` can answer with a trajectory.
        public var canTrace: Bool { self == .tune }

        /// Only `/tune` runs a caller named list of episodes in one call.
        public var variesWithinAScene: Bool { self == .tune }
    }

    public let id: String
    /// The user facing name, which becomes `eval.task` and the filename stem.
    ///
    /// IT IS `name` AND IT IS NEVER A POLICY'S OWN WORD FOR ITSELF.
    /// `scripts/check_no_policy_name_keys.sh` refuses a person's nickname
    /// anywhere a file is written, because a nickname is a claim about
    /// somebody else's network and a filename built from one has shipped a
    /// wrong name before. An evaluation's `name` is this app's own, so a
    /// filename may be built from it.
    public let name: String
    public let said: String
    public let route: Route
    public let scenes: [EvalScene]
    public let scorers: EvalScorerSet
    public let epochs: EvalEpochs
    /// The declared horizon in seconds, or nil where the harness owns it per
    /// cell. Bounded to `secondsRange` when it is there at all.
    public let maxSeconds: Double?
    public let wantsTrace: Bool

    init(id: String, name: String, said: String, route: Route, scenes: [EvalScene],
         scorers: EvalScorerSet, epochs: EvalEpochs, maxSeconds: Double?, wantsTrace: Bool) {
        self.id = id
        self.name = name
        self.said = said
        self.route = route
        self.scenes = scenes
        self.scorers = scorers
        self.epochs = epochs
        self.maxSeconds = maxSeconds
        self.wantsTrace = wantsTrace
    }

    // MARK: - the horizon

    /// TEN SECONDS IS NOT AN ARBITRARY CEILING. At `DuckModel.tickHz` a ten
    /// second episode is exactly 500 ticks, which is the bench's own
    /// `TRACE_CAP`. Past that, a traced trial's tick count would be a
    /// truncation, and a recording that stops before the episode does is a
    /// recording somebody would judge on.
    public static let secondsFloor = 0.2
    public static var secondsCeiling: Double { Double(EvalTrace.cap) / DuckModel.tickHz }
    public static var secondsRange: ClosedRange<Double> { secondsFloor...secondsCeiling }

    /// `Task.resolve_envelope`: the integer budget the rollout actually uses.
    public var maxSteps: Int? {
        guard let maxSeconds else { return nil }
        return Swift.max(1, Int((maxSeconds * DuckModel.tickHz).rounded(.up)))
    }

    // MARK: - refusals

    public enum Refusal: Error, Equatable {
        case noScenes
        case duplicateSceneID(String)
        case sceneIDNotFilesystemSafe(String)
        case secondsOutOfRange(Double)
        case epochsOnARouteThatDoesNotVary(String)

        public var message: String {
            switch self {
            case .noScenes:
                return "An evaluation with no scenes has nothing to run."
            case .duplicateSceneID(let id):
                return "Two scenes here are both called \(id), and every score in the log is "
                     + "filed under that name."
            case .sceneIDNotFilesystemSafe(let id):
                return "\(id) cannot be a scene name: it has to survive being used as a "
                     + "filename, so letters, digits, a dot, an underscore and a hyphen only."
            case .secondsOutOfRange(let value):
                return "An episode here runs between "
                     + "\(EvalTask.number(EvalTask.secondsFloor)) and "
                     + "\(EvalTask.number(EvalTask.secondsCeiling)) seconds, and that is "
                     + "\(EvalTask.number(value)). The ceiling is the bench's own trace cap of "
                     + "500 ticks divided by its 50 Hz, so a watched episode is never cut short."
            case .epochsOnARouteThatDoesNotVary(let route):
                return "\(route) runs one episode per call, so a list of drop heights here "
                     + "would be the same episode scored several times. The grid is the axis on "
                     + "that route."
            }
        }
    }

    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
    }

    /// The only way to build one.
    public static func checked(id: String, name: String, said: String, route: Route,
                               scenes: [EvalScene], scorers: EvalScorerSet,
                               epochs: EvalEpochs, maxSeconds: Double?) throws -> EvalTask {
        guard !scenes.isEmpty else { throw Refusal.noScenes }
        var seen = Set<String>()
        for scene in scenes {
            guard scene.idIsFilesystemSafe else {
                throw Refusal.sceneIDNotFilesystemSafe(scene.id)
            }
            guard seen.insert(scene.id).inserted else {
                throw Refusal.duplicateSceneID(scene.id)
            }
        }
        if let maxSeconds, !secondsRange.contains(maxSeconds) {
            throw Refusal.secondsOutOfRange(maxSeconds)
        }
        if !route.variesWithinAScene, epochs.axis.dropValues != nil {
            throw Refusal.epochsOnARouteThatDoesNotVary(route.path)
        }
        return EvalTask(id: id, name: name, said: said, route: route, scenes: scenes,
                        scorers: scorers, epochs: epochs, maxSeconds: maxSeconds,
                        wantsTrace: route.canTrace)
    }

    // MARK: - what goes in scene_metadata

    /// The machine readable half of a scene, so a reader does not have to parse
    /// the epoch axis out of prose.
    ///
    /// `drop_heights_m` IS WRITTEN AS NUMBERS ON PURPOSE. The walk axis is
    /// `DuckTuner.Plan.heldOutDrops` by reference, and that array belongs to
    /// the tuner and the weight search as well. If it ever changes, an archived
    /// log that named the axis only in prose would silently start meaning
    /// something else; a log with the eight numbers in it goes on meaning what
    /// it meant.
    public func sceneMetadata(for scene: EvalScene,
                              refusedTerms: [String] = []) -> [String: EvalLogJSON] {
        var metadata = scene.metadata
        metadata[EvalMeta.route] = .string(route.path)
        metadata[EvalMeta.reducer] = .string(epochs.reducer.rawValue)
        metadata[EvalMeta.termsRefused] = .strings(refusedTerms)
        if let drops = epochs.axis.dropValues {
            metadata[EvalMeta.dropHeights] = .numbers(drops)
        }
        if let seconds = maxSeconds { metadata[EvalMeta.seconds] = .number(seconds) }
        if let command = scene.command {
            metadata[EvalMeta.schedule] = .array(command.map {
                .object(["at": .number($0.at), "vx": .number($0.vx),
                         "vy": .number($0.vy), "vyaw": .number($0.vyaw)])
            })
        }
        if let cell = scene.cell, let rise = scene.rise {
            metadata[EvalMeta.cell] = .object(["dh": .number(cell.dh), "drop": .number(cell.drop),
                                               "fmul": .number(cell.fmul),
                                               "tier": .string(cell.tier.rawValue)])
            metadata[EvalMeta.cellLabel] = .string(cell.said(rise: rise))
            metadata[EvalMeta.riseMetres] = .number(rise)
        }
        if let cell = scene.chaseCell {
            metadata[EvalMeta.cell] = .object(["bearing": .number(cell.bearing),
                                               "range": .number(cell.range),
                                               "drop": .number(cell.drop),
                                               "fmul": .number(cell.fmul),
                                               "tier": .string(cell.tier.rawValue)])
            metadata[EvalMeta.cellLabel] = .string(cell.said)
        }
        return metadata
    }

    // MARK: - the four presets

    /// The walk axis, by reference and never retyped.
    public static var walkDrops: [Double] { DuckTuner.Schedule.onAPhone.heldOutDrops }
    public static let walkSeconds = 6.0

    public static func walkThreeCommands(seconds: Double = walkSeconds) throws -> EvalTask {
        try checked(
            id: "walk-three-commands",
            name: "Walk under three commands",
            said: "The same network asked to walk forward, to step sideways and to turn, each "
                + "from eight drop heights it was never tuned on. Three rows, because a mean "
                + "over the three would let one of them hide behind the other two.",
            route: .tune,
            scenes: [
                walkScene(id: "cmd-forward", command: DuckBench.walkingCommand, seconds: seconds),
                walkScene(id: "cmd-sideways", command: DuckBench.sidewaysCommand, seconds: seconds),
                walkScene(id: "cmd-turning", command: DuckBench.turningCommand, seconds: seconds),
            ],
            scorers: .walk,
            epochs: try EvalEpochs.drops(walkDrops, reducer: .median),
            maxSeconds: seconds)
    }

    public static func walkForwardOnly(seconds: Double = walkSeconds) throws -> EvalTask {
        try checked(
            id: "walk-forward",
            name: "Walk under a forward command",
            said: "One command, forward, from eight drop heights the network was never tuned "
                + "on. The quickest honest measurement this app can make.",
            route: .tune,
            scenes: [walkScene(id: "cmd-forward", command: DuckBench.walkingCommand,
                               seconds: seconds)],
            scorers: .walk,
            epochs: try EvalEpochs.drops(walkDrops, reducer: .median),
            maxSeconds: seconds)
    }

    static func walkScene(id: String, command: [DuckBench.Step], seconds: Double) -> EvalScene {
        EvalScene(id: id,
                  instruction: EvalScene.walkInstruction(command: command, seconds: seconds),
                  command: command)
    }

    /// The stairs grid, one scene per cell.
    ///
    /// `seconds` is nil unless a caller knows the harness's own window, because
    /// a horizon this app made up for a cell the harness times itself would be
    /// a number nobody measured.
    public static func stairsGrid(cells: [DuckBench.Cell], rise: Double,
                                  seconds: Double? = nil) throws -> EvalTask {
        try checked(
            id: "stairs-grid",
            name: "Stairs challenge grid",
            said: "One episode per published cell, scored by the challenge harness rather than "
                + "by this app. A log is a record of what happened and is not a submission.",
            route: .climb,
            scenes: cells.map {
                EvalScene(id: EvalScene.id(for: $0, rise: rise),
                          instruction: "Get onto a step \($0.said(rise: rise)) and be standing "
                                     + "on it when the tail ends.",
                          cell: $0, rise: rise)
            },
            scorers: .stairs,
            epochs: .single(reducer: .mean),
            maxSeconds: seconds)
    }

    public static func ballGrid(cells: [DuckBench.ChaseCell],
                                seconds: Double? = nil) throws -> EvalTask {
        try checked(
            id: "ball-grid",
            name: "Ball challenge grid",
            said: "One episode per published cell, scored by the challenge harness rather than "
                + "by this app. A log is a record of what happened and is not a submission.",
            route: .chase,
            scenes: cells.map {
                EvalScene(id: EvalScene.id(for: $0),
                          instruction: "Find the ball at \($0.longSaid) and send it somewhere.",
                          chaseCell: $0)
            },
            scorers: .ball,
            epochs: .single(reducer: .mean),
            maxSeconds: seconds)
    }

    // MARK: - the sentences

    /// The row under Measure, and the sixth one there.
    public static let rowTitle = "Run a formal evaluation"

    public static let whatAnEvaluationIs =
        "A named task, a named policy and a named bench, run a fixed number of times and written "
      + "into one file. The file is inspect-robots' own evaluation log format, so their tools "
      + "read it and a number from this phone can be checked by somebody who was not holding it."

    /// The same sentence under the door, because a door that describes itself
    /// differently from the screen it opens is two descriptions of one thing.
    public static var doorDetail: String { whatAnEvaluationIs }

    public static let nothingRunYet =
        "No evaluations yet. Pick a preset, pick a policy and start one, and the log lands here "
      + "with everything needed to read it somewhere else."

    public static let stopIsNotAFailure =
        "Stopping keeps what already ran. The log is written with the scenes that finished and "
      + "says it was stopped, because a stopped run is real data about what happened up to the "
      + "stop."

    public static let maxStepsSaid =
        "The horizon is a budget and not a count. It is what the episode was allowed, in seconds "
      + "and in the control ticks those seconds resolve to, and how many ticks were actually "
      + "reported is a separate number."

    public static let whyNotMeasure =
        "The measure route runs the rollouts and answers how many of them ended standing, "
      + "without saying which. An evaluation writes one score per episode, and there is no "
      + "honest way to spread a count of successes across episodes nobody can see."

    public static let whyNotPerform =
        "The perform route is not offered for the same reason, and one more: it chooses its own "
      + "rollouts and returns the frames of the first. An authored motion is evaluated here "
      + "through the stairs grid, which scores the motion itself, one cell at a time."
}
