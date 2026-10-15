import Foundation
import DuckKit

/// Walk and Turn cards closed on what robotd reports: one board square, one quarter turn.
///
/// A timed card is a twist held for two seconds, and a duck held to a twist does not land on a
/// square: duckbench measured it (`duckbench/sim/cardsize.mjs`, `cardloop.mjs`). So when robotd's
/// `robot.state` carries `odom` (Pollen's contact odometry, whose `yaw` is the trunk IMU's), a
/// Walk card walks until odometry says the duck has covered one duck square along the card's
/// heading, steering onto that line, and a Turn card turns until the yaw is a quarter turn from
/// the card's heading, then settles and trims. Every other card runs as it always has.
///
/// ONE SPEC, TWO READERS. The numbers are `Resources/DuckCards/duck-card-loop.json`, which the
/// card reader on the duck carries byte for byte (`cardreader/duckcards/duck-card-loop.json`,
/// `scripts/check_duckcards_vectors.sh`), and the stepping rules here are `CardLoop` in
/// `cardreader/duckcards/cardloop.py`, held to each other by `cardreader/vectors/cardloop/*.json`:
/// a card, a trace of odometry samples, and the command or the stop each sample must produce.
///
/// THE BOARD. A row keeps where the duck should be: the odometry pose it started the first card
/// at, then one square or one quarter turn per card. Each card aims at that board pose rather than
/// at "one more square from wherever the last card stopped", so an overshoot or the drift of a
/// turn is taken back by the next card instead of adding up. A skill moves the duck in ways the
/// board does not count, so after one the board's position is put back where the duck stands;
/// its heading is kept.
public enum DuckCardLoop {

    public static let format = "duck-card-loop/1"
    /// The four cards that close on odometry. Every other card is unchanged.
    public static let cards: Set<String> = ["walk_forward", "walk_backward", "turn_left", "turn_right"]

    // MARK: - the spec

    public struct Spec: Equatable, Sendable, Decodable {
        public struct Speeds: Equatable, Sendable, Decodable {
            public let slow: Double, normal: Double, fast: Double
            public func of(_ label: String?) -> Double {
                switch label {
                case "slow": return slow
                case "fast": return fast
                default: return normal
                }
            }
        }
        public struct Walk: Equatable, Sendable, Decodable {
            public let speed: Speeds
            public let backSpeed: Speeds
            public let headingGain: Double, crossGain: Double, maxYaw: Double
            public let stopEarlyM: Double, backStopEarlyM: Double, maxS: Double
            /// A Walk card less than `stallM` further along its line in `stallS` is stuck.
            public let stallS: Double, stallM: Double
            enum CodingKeys: String, CodingKey {
                case speed, backSpeed = "back_speed", headingGain = "heading_gain", crossGain = "cross_gain",
                     maxYaw = "max_yaw", stopEarlyM = "stop_early_m", backStopEarlyM = "back_stop_early_m", maxS = "max_s",
                     stallS = "stall_s", stallM = "stall_m"
            }
        }
        public struct Turn: Equatable, Sendable, Decodable {
            public let yawRate: Speeds
            public let forward: Double, stopEarlyDeg: Double, toleranceDeg: Double
            public let trimRate: Double, trimForward: Double, trimStopEarlyDeg: Double
            public let trims: Int, settleS: Double, maxS: Double
            /// A turn or trim not `stallDeg` closer to its heading in `stallS` is stuck.
            public let stallS: Double, stallDeg: Double
            enum CodingKeys: String, CodingKey {
                case yawRate = "yaw_rate", forward, stopEarlyDeg = "stop_early_deg", toleranceDeg = "tolerance_deg",
                     trimRate = "trim_rate", trimForward = "trim_forward", trimStopEarlyDeg = "trim_stop_early_deg",
                     trims, settleS = "settle_s", maxS = "max_s", stallS = "stall_s", stallDeg = "stall_deg"
            }
        }
        public let format: String
        /// THE OFF SWITCH. Closed-loop cards ship OFF for real ducks until they pass
        /// docs/PACKS.md, "Acceptance". Off, `RobotPlan` runs a Duck Card's Walk and Turn as the
        /// timed cards they were and says `offNote`; only "Measure my duck" (`DuckMeasure`) runs
        /// them closed on a robot, as a test. The card reader reads the same key.
        public let enabledOnRobot: Bool
        /// Null until every rung has passed; then one line citing the three results.
        public let validated: String?
        /// One duck square: how far a Walk card carries the duck.
        public let squareM: Double
        /// How often the controller sends `robot.move`.
        public let controlHz: Double
        /// A pose older than this, mid-card, is a duck that stopped reporting.
        public let staleS: Double
        /// The still moment after every card, before the next.
        public let betweenS: Double
        public let walk: Walk
        public let turn: Turn
        enum CodingKeys: String, CodingKey {
            case format, enabledOnRobot = "enabled_on_robot", validated,
                 squareM = "square_m", controlHz = "control_hz", staleS = "stale_s",
                 betweenS = "between_s", walk, turn
        }

        public static func read(_ data: Data) throws -> Spec {
            let spec = try JSONDecoder().decode(Spec.self, from: data)
            guard spec.format == DuckCardLoop.format else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "not \(DuckCardLoop.format)"))
            }
            return spec
        }
    }

    static var specURL: URL? { Bundle.module.url(forResource: "DuckCards/duck-card-loop", withExtension: "json") }

    /// The shipped spec. A bundle without it is a build that cannot close a card, so it is fatal
    /// where the deck's absence is: at first use, by name.
    public static let spec: Spec = {
        guard let url = specURL, let data = try? Data(contentsOf: url), let spec = try? Spec.read(data) else {
            fatalError("StudioKit is missing Resources/DuckCards/duck-card-loop.json")
        }
        return spec
    }()

    // MARK: - Pollen's envelope

    /// Pollen's pad envelope: `PadDriveParams::default()` in pollen-robotics/microduck
    /// `robotd-params/src/lib.rs`, read at the commit it names, in `Resources/DuckCards/
    /// pollen-pad-drive.json` (the card reader carries it byte for byte). Pollen's own words: what
    /// the v8 velstand "follows well on the robot". robotd does not clamp a `robot.move` to it (the
    /// pad is bounded, other clients are not), so no card, and no stick here, asks for more.
    public struct Envelope: Equatable, Sendable, Decodable {
        public let format: String
        /// Where the numbers were read: file, symbol and lines.
        public let source: String
        public let commit: String
        /// Forward (positive) and back (negative), m/s.
        public let vx: [Double]
        /// Left (positive) and right (negative), m/s.
        public let vy: [Double]
        /// Turning left (positive) and right (negative), rad/s.
        public let vyaw: [Double]

        public var forward: Double { vx[1] }
        public var backward: Double { -vx[0] }
        public var sideways: Double { min(vy[1], -vy[0]) }
        public var turn: Double { min(vyaw[1], -vyaw[0]) }

        public static let format = "pollen-pad-drive/0"

        public static func read(_ data: Data) throws -> Envelope {
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            func aroundZero(_ range: [Double]) -> Bool {
                guard range.count == 2 else { return false }
                let low: Double = range[0], high: Double = range[1]
                return low <= 0 && 0 <= high
            }
            guard env.format == Envelope.format, aroundZero(env.vx), aroundZero(env.vy), aroundZero(env.vyaw) else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "not \(Envelope.format)"))
            }
            return env
        }
    }

    static var envelopeURL: URL? { Bundle.module.url(forResource: "DuckCards/pollen-pad-drive", withExtension: "json") }

    /// The shipped envelope; fatal at first use without it, like the spec.
    public static let envelope: Envelope = {
        guard let url = envelopeURL, let data = try? Data(contentsOf: url), let env = try? Envelope.read(data) else {
            fatalError("StudioKit is missing Resources/DuckCards/pollen-pad-drive.json")
        }
        return env
    }()

    /// Every number in a spec that would command more than Pollen's pad envelope, said by name, in
    /// the spec's order: the same sentences as `cardloop.envelope_problems`. The shipped spec must
    /// answer empty; `scripts/check_duckcards_vectors.sh` fails when it does not.
    public static func envelopeProblems(_ spec: Spec, envelope env: Envelope = envelope) -> [String] {
        struct Check { let name: String; let value: Double; let limit: Double }
        let w = spec.walk, t = spec.turn
        func speeds(_ name: String, _ s: Spec.Speeds, _ limit: Double) -> [Check] {
            [Check(name: name + ".slow", value: s.slow, limit: limit),
             Check(name: name + ".normal", value: s.normal, limit: limit),
             Check(name: name + ".fast", value: s.fast, limit: limit)]
        }
        var checks: [Check] = speeds("walk.speed", w.speed, env.forward)
        checks += speeds("walk.back_speed", w.backSpeed, env.backward)
        checks.append(Check(name: "walk.max_yaw", value: w.maxYaw, limit: env.turn))
        checks += speeds("turn.yaw_rate", t.yawRate, env.turn)
        let forwardLimit: Double = t.forward >= 0 ? env.forward : env.backward
        checks.append(Check(name: "turn.forward", value: abs(t.forward), limit: forwardLimit))
        checks.append(Check(name: "turn.trim_rate", value: t.trimRate, limit: env.turn))
        let trimLimit: Double = t.trimForward >= 0 ? env.forward : env.backward
        checks.append(Check(name: "turn.trim_forward", value: abs(t.trimForward), limit: trimLimit))
        var out: [String] = []
        for c in checks where !(0 <= c.value && c.value <= c.limit) {
            out.append(c.name + " is " + String(format: "%g", c.value) + ", past Pollen's pad envelope of "
                       + String(format: "%g", c.limit))
        }
        return out
    }

    // MARK: - poses

    public struct Pose: Equatable, Sendable {
        public var x: Double, y: Double
        /// Heading, radians, odometry's frame.
        public var h: Double
        public init(x: Double, y: Double, h: Double) { self.x = x; self.y = y; self.h = h }
    }

    /// The duck's pose from one `robot.state` frame, or nil when it does not say.
    ///
    /// Pollen's `RobotState.odom` is `{position: [x, y, z], yaw}`. DuckKit's `Odometry.x` and
    /// `.y` read only a two-element position and answer nil for robotd's three, so the first two
    /// are read here. A robotd from before the estimator sends no `odom` at all, which is the case
    /// a card falls back from.
    public static func pose(of state: DuckState?) -> Pose? {
        guard let odom = state?.odom, let p = odom.position, p.count >= 2, let yaw = odom.yaw,
              p[0].isFinite, p[1].isFinite, yaw.isFinite else { return nil }
        return Pose(x: p[0], y: p[1], h: yaw)
    }

    /// An angle in (-pi, pi].
    public static func wrap(_ a: Double) -> Double {
        var a = a
        while a > .pi { a -= 2 * .pi }
        while a <= -.pi { a += 2 * .pi }
        return a
    }

    /// What a Speed card means on a distance card: how fast the duck walks or turns there. Every
    /// speed is one the gait answers to; a Turn card has the one rate that turns the duck in place.
    public static func speed(_ action: String, _ label: String?, spec: Spec = spec) -> Double {
        switch action {
        case "walk_forward": return spec.walk.speed.of(label)
        case "walk_backward": return spec.walk.backSpeed.of(label)
        default: return spec.turn.yawRate.of(label)
        }
    }

    // MARK: - words

    /// Said once per row when Walk and Turn cards cannot close on odometry. The card reader says
    /// the same sentence (`runner.TIMED_NOTE`).
    public static let timedNote = "This duck does not report odometry, so Walk and Turn cards run as timed "
        + "cards, two seconds each, and do not land on board squares."
    /// Said once per row while closed-loop cards are off for real ducks (`spec.enabledOnRobot`),
    /// and wherever a board is shown beside a duck. The card reader says the same sentence
    /// (`cardloop.OFF_NOTE`).
    public static let offNote = "Walk and Turn cards on a duck are timed for now: two seconds each, and the "
        + "duck does not land on board squares. Measured cards are being tested."
    /// Said when the pose stops arriving mid-card (`runner.LOST_NOTE`). The row ends there.
    public static let lostNote = "The duck stopped reporting where it is, so the row stopped there."
    /// Said when robotd reports the duck fell mid-card (`runner.FELL_NOTE`). The row ends there.
    public static let fellNote = "The duck fell, so the row stopped there."

    /// One card as a person reads it before pressing Run.
    public static func spelled(_ action: String, speed: String?, spec: Spec = spec) -> String {
        let rate = DuckCardLoop.speed(action, speed, spec: spec)
        switch action {
        case "walk_forward", "walk_backward":
            return String(format: "%@ one square, %.0f cm on odometry, at vx %.2f",
                          action == "walk_forward" ? "Walk forward" : "Walk back", spec.squareM * 100, rate)
        default:
            return String(format: "Turn %@ a quarter turn on odometry, at vyaw %.2f",
                          action == "turn_left" ? "left" : "right", rate)
        }
    }

    // MARK: - one card

    public enum Answer: Equatable, Sendable {
        case send(vx: Double, vyaw: Double)
        case done(Done)
    }

    public enum Done: String, Equatable, Sendable {
        case reached
        case outOfTime = "out of time"
        /// No progress for the spec's `stall_s`: a duck that cannot do the card at the speeds it may be sent.
        case stuck
        case trimmedOut = "trimmed out"

        /// What a person hears when a card ends some other way than arriving.
        public var words: String? {
            switch self {
            case .reached: return nil
            case .outOfTime: return "ran out of time before it got there"
            case .stuck: return "could not get there at the speeds a duck may be sent"
            case .trimmedOut: return "stopped short of a quarter turn after its trims"
            }
        }
    }

    /// One Walk or Turn card, stepped on odometry samples.
    public struct Card: Sendable {
        public let action: String
        public let board: Pose
        /// Where the duck should be once the card is done, whatever happened.
        public let boardAfter: Pose
        public let rate: Double
        let spec: Spec
        let sign: Double
        var phase = "turn"
        var since = 0.0
        var trimsLeft: Int
        /// The last progress made, and when: what `stuck` is measured from.
        var mark: Double?
        var markT = 0.0

        public init?(action: String, board: Pose, speed: String? = nil, spec: Spec = DuckCardLoop.spec) {
            guard DuckCardLoop.cards.contains(action) else { return nil }
            self.action = action; self.board = board; self.spec = spec
            self.rate = DuckCardLoop.speed(action, speed, spec: spec)
            self.trimsLeft = spec.turn.trims
            if action.hasPrefix("walk") {
                sign = action == "walk_forward" ? 1 : -1
                boardAfter = Pose(x: board.x + sign * spec.squareM * cos(board.h),
                                  y: board.y + sign * spec.squareM * sin(board.h), h: board.h)
            } else {
                sign = action == "turn_left" ? 1 : -1
                boardAfter = Pose(x: board.x, y: board.y, h: DuckCardLoop.wrap(board.h + sign * .pi / 2))
            }
        }

        /// The latest pose and the seconds since the card began: a twist to send, or done.
        public mutating func step(_ pose: Pose, t: Double) -> Answer {
            action.hasPrefix("walk") ? walk(pose, t) : turn(pose, t)
        }

        /// No `enough` more progress for `window` seconds.
        mutating func stalled(_ progress: Double, _ t: Double, enough: Double, window: Double) -> Bool {
            if let m = mark, progress < m + enough { return t - markT >= window }
            mark = progress
            markT = t
            return false
        }

        mutating func walk(_ pose: Pose, _ t: Double) -> Answer {
            let w = spec.walk, b = board
            let dx = pose.x - b.x, dy = pose.y - b.y
            let along = sign * (dx * cos(b.h) + dy * sin(b.h))
            let across = -dx * sin(b.h) + dy * cos(b.h)
            if along >= spec.squareM - (sign > 0 ? w.stopEarlyM : w.backStopEarlyM) { return .done(.reached) }
            if t >= w.maxS { return .done(.outOfTime) }
            if stalled(along, t, enough: w.stallM, window: w.stallS) { return .done(.stuck) }
            var steer = w.headingGain * DuckCardLoop.wrap(b.h - pose.h) - sign * w.crossGain * across
            steer = max(-w.maxYaw, min(w.maxYaw, steer))
            return .send(vx: sign * rate, vyaw: steer)
        }

        mutating func turn(_ pose: Pose, _ t: Double) -> Answer {
            let c = spec.turn
            let e = DuckCardLoop.wrap(boardAfter.h - pose.h)
            let off = abs(e) * 180 / .pi
            let way: Double = e >= 0 ? 1 : -1
            if t >= c.maxS { return .done(.outOfTime) }
            if phase == "turn" || phase == "trim" {
                let trim = phase == "trim"
                if off <= (trim ? c.trimStopEarlyDeg : c.stopEarlyDeg) {
                    phase = "settle"; since = t
                    return .send(vx: 0, vyaw: 0)
                }
                if stalled(-off, t, enough: c.stallDeg, window: c.stallS) { return .done(.stuck) }
                return .send(vx: trim ? c.trimForward : c.forward, vyaw: way * (trim ? c.trimRate : rate))
            }
            if t - since < c.settleS { return .send(vx: 0, vyaw: 0) }
            if off <= c.toleranceDeg { return .done(.reached) }
            if trimsLeft <= 0 { return .done(.trimmedOut) }
            trimsLeft -= 1
            phase = "trim"
            mark = nil                       // a trim's progress counts from its own start
            return .send(vx: c.trimForward, vyaw: way * c.trimRate)
        }
    }
}
