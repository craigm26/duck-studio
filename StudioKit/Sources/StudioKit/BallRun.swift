import Foundation
import DuckKit

/// Where a Walk to the ball run starts on the practice duck: the same starts M1 was measured on.
///
/// THE DRIVER ONLY KNOWS THIS. Its takes and every M1 run began the same way (`scripts/m1_trial.py`,
/// `setup`): the world reset, `alpha_walking` on the servos (a reset leaves the standing policy, and
/// a duck on that does not walk for any command), then the ball at a bearing anywhere around the duck
/// and 0.5 to 1.4 m away, drawn by the same rule from a seed. The fixed ball in `DreamPracticeWorld`
/// is for a bench with no ball: a bench that has one reports it, the head camera draws it there, and
/// the stage moves its own ball to the same spot, so what a person sees is what the driver sees.
///
/// THE SETTLE IS M1'S PRE-ROLL. M1 stood the duck for `DriverTrial.preRoll` with no command before the
/// first ask. The bench only moves inside a request, so the same 1.2 s is asked for here, in one `/stop`.
public struct BallRunStart: Equatable, Sendable {
    /// Degrees, positive to the duck's left, the convention `POST /ball` uses.
    public let bearing: Double
    public let range: Double

    public static let walker = "alpha_walking.onnx"
    public static let settle = DriverTrial.preRoll
    /// Pictures in the window before the first ask, as M1 had after its pre-roll: one a `cameraPeriod`.
    public static let picturesFirst = Int((DriverTrial.preRoll / DriverTrial.cameraPeriod).rounded()) + 1
    /// The longest a run waits for those pictures; a first draw on a phone builds the renderer.
    public static let picturesWithin: TimeInterval = 8

    /// `record_ball_takes.py`'s rule, so a seed is the same start as in `m1_trial.py`.
    public init(seed: UInt64) {
        var rng = SplitMix64(seed: seed &* 7919 &+ 1)
        bearing = -180 + 360 * rng.next()
        range = 0.5 + 0.9 * rng.next()
    }

    public enum Words {
        public static let needsPlainFloor =
            "Walk to the ball needs the plain floor: the driver has never seen stairs. Pick the bench's own world in Scene."
        public static let cameraTooSlow = "The practice camera did not start in time. Try again."
    }

    /// Why this world will not do, or nil. Steps the head camera does not draw and the driver never
    /// trained on are in the duck's way, unseen. A world that only moved the ball is fine.
    public static func refusal(world: DuckWorld?) -> String? {
        guard let world, world.isSet, !world.steps.isEmpty else { return nil }
        return Words.needsPlainFloor
    }
}

extension DuckDrive {
    /// Put the ball `range` metres from the duck at `bearing` degrees, positive left: the bench's
    /// own trial door, `POST /ball`. It answers a state block carrying the ball.
    public static func placeBall(_ address: DuckBench.Address, bearing: Double, range: Double) throws -> DuckBench.Call {
        DuckBench.Call(method: "POST", url: URL(string: "\(address.base)/ball")!,
                       body: try JSONSerialization.data(withJSONObject: ["bearing": bearing, "range": range]))
    }
}

extension BenchPeer {
    /// Lays a run's start: reset, the walker, the ball, then the settle. THE SETTLE GOES THROUGH
    /// `/stop` so this peer keeps the answer: `live` then carries the placed ball, and the head
    /// camera, which draws `live`, shows it from the first picture. Throws the bench's own refusal.
    public func layOut(_ start: BallRunStart) async throws {
        _ = try DuckDrive.readLive(try await ask(try DuckDrive.reset(address)))
        _ = try DuckDrive.readLive(try await ask(try DuckDrive.load(address, policy: BallRunStart.walker)))
        _ = try DuckDrive.readLive(try await ask(try DuckDrive.placeBall(address, bearing: start.bearing, range: start.range)))
        try await settle(BallRunStart.settle)
    }
}

/// Watches a run from the bench's ground truth, the way M1 scored one.
///
/// FOR THE SENTENCE AFTER A RUN AND FOR ENDING IT, NEVER FOR STEERING: the driver sees only pictures,
/// and the bench's own comment says the ball in its state is for scoring. The definitions are
/// `m1_trial.py`'s: REACHED is the root inside `BallExpert.reach` at any moment; PARKED is ending
/// within 0.40 m with the root moved at most 0.02 m in the last second.
public struct BallRunWatch: Equatable, Sendable {
    public static let parkedWithin = BallExpert.reach + 0.05
    public static let stillMetres = 0.02
    public static let stillSeconds = 1.0

    public enum Outcome: Equatable, Sendable {
        case parked(reachedAfter: Double?, metres: Double)
        case reached(after: Double)
        case missed(closest: Double)
        case fell
        case notStarted
    }

    private var started: Double?
    private var reachedAt: Double?
    private var closest: Double?
    private var fell = false
    private var parkedAt: Double?
    private var trail: [(t: Double, x: Double, y: Double)] = []

    public init() {}

    public static func == (a: BallRunWatch, b: BallRunWatch) -> Bool {
        a.started == b.started && a.reachedAt == b.reachedAt && a.closest == b.closest
            && a.fell == b.fell && a.parkedAt == b.parkedAt
    }

    /// Takes one state; true once the run is finished, parked at the ball or on its side.
    public mutating func see(_ live: DuckDrive.Live) -> Bool {
        guard let ball = live.ball else { return false }
        let t = live.t, root = live.stance.root
        if started == nil { started = t }
        let metres = Self.apart(ball.x - root.x, ball.y - root.y)
        closest = min(closest ?? metres, metres)
        if metres <= BallExpert.reach, reachedAt == nil { reachedAt = t }
        if !live.upright { fell = true; return true }
        trail.append((t, root.x, root.y))
        trail.removeAll { $0.t < t - Self.stillSeconds - 0.25 }
        guard let first = trail.first, t - first.t >= Self.stillSeconds, metres <= Self.parkedWithin else { return false }
        let moved = trail.map { Self.apart($0.x - root.x, $0.y - root.y) }.max() ?? 0
        guard moved <= Self.stillMetres else { return false }
        parkedAt = metres
        return true
    }

    private static func apart(_ x: Double, _ y: Double) -> Double { (x * x + y * y).squareRoot() }

    public var outcome: Outcome {
        guard let started, let closest else { return .notStarted }
        if fell { return .fell }
        let after = reachedAt.map { $0 - started }
        if let parkedAt { return .parked(reachedAfter: after, metres: parkedAt) }
        if let after { return .reached(after: after) }
        return .missed(closest: closest)
    }

    public enum Words {
        public static func parked(_ seconds: Double) -> String { String(format: "Reached the ball in %.1f s and stopped.", seconds) }
        public static func parkedShort(_ metres: Double) -> String { String(format: "Stopped %.2f m from the ball.", metres) }
        public static func reachedNoStop(_ seconds: Double) -> String { String(format: "Reached the ball in %.1f s but did not stop.", seconds) }
        public static func missed(_ metres: Double) -> String { String(format: "Did not reach the ball. Closest: %.2f m.", metres) }
        public static let fell = "The duck fell over on the way."
        public static func answered(_ ms: Int) -> String { "Each answer took \(ms) ms (p50)." }
    }

    /// The line after a run. `pilotSaid` is the pilot's last word, kept when it ended for a reason of
    /// its own (too hot, too slow); a Stop or the time limit is told by where the duck got to.
    public func line(pilotSaid: String?, p50: Int?) -> String {
        var first: String?
        switch outcome {
        case .parked(let after?, _): first = Words.parked(after)
        case .parked(nil, let metres): first = Words.parkedShort(metres)
        case .reached(let after): first = Words.reachedNoStop(after)
        case .missed(let closest): first = Words.missed(closest)
        case .fell: first = Words.fell
        case .notStarted: first = nil
        }
        if let pilotSaid, pilotSaid != DuckDream.Words.stopped, pilotSaid != DuckDream.Words.timeUp { first = pilotSaid }
        return [first ?? pilotSaid, p50.map(Words.answered)].compactMap { $0 }.joined(separator: " ")
    }
}

/// The Walk to the ball card in Auto: its lines and its buttons, so all of it is tested here.
public struct DriverCard: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case get, cancel, tryAgain, go, delete
    }

    public let lines: [String]
    /// 0 to 1 while downloading.
    public let progress: Double?
    public let actions: [Action]

    public enum Words {
        public static let provenance = AutoGoal.walkToBall.provenance
        public static func get(_ size: String) -> String { "Get (\(size))" }
        public static let cancel = "Cancel"
        public static let tryAgain = "Try again"
        public static let delete = "Delete"
        public static func getting(_ percent: Int) -> String { "Getting the driver: \(percent)%" }
        public static let checking = "Checking it on this phone."
        /// The fresh-seed number, and what it still does wrong.
        public static func honest(_ r: DriverRelease) -> String {
            "Simulator test: reached \(r.freshReached) of \(r.freshRuns), stopped at \(r.freshParked). "
                + "It can bump the ball."
        }
        public static func all(_ r: DriverRelease) -> [String] {
            [provenance, get(r.size), cancel, tryAgain, delete, getting(40), checking, honest(r),
             BallRunStart.Words.needsPlainFloor, BallRunStart.Words.cameraTooSlow,
             BallRunWatch.Words.parked(9.5), BallRunWatch.Words.parkedShort(0.38),
             BallRunWatch.Words.reachedNoStop(9.5), BallRunWatch.Words.missed(0.6),
             BallRunWatch.Words.fell, BallRunWatch.Words.answered(9)]
        }
    }

    public func title(_ action: Action, release: DriverRelease) -> String {
        switch action {
        case .get: return Words.get(release.size)
        case .cancel: return Words.cancel
        case .tryAgain: return Words.tryAgain
        case .go: return AutoGoal.Words.go
        case .delete: return Words.delete
        }
    }

    /// - Parameters:
    ///   - cameraNote: why this device cannot draw the practice camera, or nil.
    ///   - lastRun: the line from the last run, kept until the next.
    public init(phase: DriverInstall.Phase, duck: DuckIdentity.Kind?, release: DriverRelease = .walkToBall,
                cameraNote: String? = nil, lastRun: String? = nil) {
        var lines: [String] = []
        var actions: [Action] = []
        progress = phase.fraction
        switch phase {
        case .absent:
            lines.append(Words.honest(release))
            if duck == .real { lines.append(AutoGoal.Words.practiceOnlyForNow) }
            actions = [.get]
        case .getting:
            lines.append(Words.getting(Int(((phase.fraction ?? 0) * 100).rounded())))
            actions = [.cancel]
        case .checking:
            lines.append(Words.checking)
            actions = [.cancel]
        case .failed(let why):
            lines.append(why)
            actions = [.tryAgain]
        case .installed:
            let goal = AutoGoal.walkToBall
            if let lastRun { lines.append(lastRun) } else { lines.append(Words.honest(release)) }
            if let reason = goal.availability(on: duck, driverInstalled: true).reason {
                lines.append(reason)
            } else if let cameraNote {
                lines.append(cameraNote)
            } else {
                actions.append(.go)
            }
            actions.append(.delete)
        }
        lines.append(Words.provenance)
        self.lines = lines
        self.actions = actions
    }
}
