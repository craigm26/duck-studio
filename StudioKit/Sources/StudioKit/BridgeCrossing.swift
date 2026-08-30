import Foundation

/// Bow Bridge, at duck scale: get across without going in the lake.
///
/// WHY A BRIDGE IS THE RIGHT GAME FOR THIS ROBOT. The duck cannot turn on the
/// spot — commanded yaw saturates at about 14 degrees and stops — so every
/// correction is an ARC, and an arc on a deck half a metre wide is a real
/// decision. It also cannot creep: below a forward command of about 0.25 the
/// walking policy marches in place, so "edge along carefully" is not available
/// either. A narrow crossing is therefore built out of exactly the two things
/// the machine is worst at, which is what makes it worth playing rather than
/// worth watching.
///
/// THE ARCH IS A RAMP, NOT STEPS. Bow Bridge rises to its centre; the deck here
/// is a smooth curve for the same reason the obstacle course has no stairs —
/// the duck tops out at a 10 mm step (measured, `step_up` 0/16 on flat ground),
/// so anything with a lip is not a course, it is a wall.
///
/// DETERMINISTIC AND CLOCK-FREE, like every engine here: the caller supplies
/// `dt`, so a crossing replays identically in a test and at 60 Hz on a phone.
public struct BridgeCrossing: Equatable, Sendable {

    public struct Deck: Equatable, Sendable {
        /// End to end, metres. Sixteen duck-lengths at 4 m.
        public let length: Double
        /// Half the walkable width. The balustrade sits just outside it.
        public let halfWidth: Double
        /// How much the centre of the arch rises above the ends.
        public let rise: Double

        public init(length: Double = 4.0, halfWidth: Double = 0.25, rise: Double = 0.22) {
            self.length = length; self.halfWidth = halfWidth; self.rise = rise
        }

        /// Deck height at a distance along the bridge — a cosine arch, so the
        /// gradient is zero at both ends and there is no lip to climb.
        public func height(at x: Double) -> Double {
            guard length > 0 else { return 0 }
            let u = min(max(x / length, 0), 1)
            return rise * 0.5 * (1 - cos(2 * .pi * u))   // 0 at both ends, `rise` at the middle
        }

        /// The steepest gradient the arch reaches, which is what decides
        /// whether the walking policy can climb it at all.
        public var steepestGradient: Double { .pi * rise / length }
    }

    /// What the duck can do, from the measured envelope.
    public struct Envelope: Equatable, Sendable {
        public let walk: Double          // m/s at command 0.25
        public let fast: Double          // m/s at command 0.35
        public let turn: Double          // rad/s while walking
        public init(walk: Double = 0.106, fast: Double = 0.150, turn: Double = 0.34) {
            self.walk = walk; self.fast = fast; self.turn = turn
        }
        /// Measured on the canon plant. See duck-trajectories.json.
        public static let measured = Envelope()
    }

    public enum Outcome: Equatable, Sendable {
        case crossing
        case across(seconds: Double)
        case inTheLake(seconds: Double)
    }

    public let deck: Deck
    public let envelope: Envelope
    /// Along the bridge, and across it. `y` is 0 down the middle.
    public private(set) var x = 0.0
    public private(set) var y = 0.0
    /// Radians, 0 pointing along the bridge.
    public private(set) var heading = 0.0
    public private(set) var elapsed = 0.0
    public private(set) var outcome: Outcome = .crossing

    public init(deck: Deck = Deck(), envelope: Envelope = .measured) {
        self.deck = deck
        self.envelope = envelope
    }

    public var height: Double { deck.height(at: x) }
    public var progress: Double { min(max(x / deck.length, 0), 1) }

    /// One step. `forward` and `steer` are −1…1, the stick as the player holds it.
    ///
    /// STEERING ONLY WORKS WHILE WALKING, which is not a rule invented for the
    /// game — it is the robot. A stationary duck turns 14 degrees and stops, so
    /// a player who lets go of forward cannot pivot out of trouble.
    public mutating func advance(dt: Double, forward: Double, steer: Double) {
        guard outcome == .crossing, dt > 0 else { return }
        elapsed += dt

        let want = min(max(forward, 0), 1)          // no reversing on a bridge
        // The dead band, honestly modelled: below the walking command the
        // policy marches in place and covers no ground.
        let speed = want < 0.35 ? 0 : (want < 0.75 ? envelope.walk : envelope.fast)
        if speed > 0 {
            heading += min(max(steer, -1), 1) * envelope.turn * dt
        }
        x += cos(heading) * speed * dt
        y += sin(heading) * speed * dt

        if abs(y) > deck.halfWidth {
            outcome = .inTheLake(seconds: elapsed)
        } else if x >= deck.length {
            outcome = .across(seconds: elapsed)
        } else if x < -0.5 {
            outcome = .inTheLake(seconds: elapsed)   // backed off the near end
        }
    }

    /// How close to the edge, 0 at the middle and 1 at the rail — what a
    /// warning ring on screen should read.
    public var edgeProximity: Double {
        min(abs(y) / deck.halfWidth, 1)
    }

    public var summary: String {
        switch outcome {
        case .crossing:
            return String(format: "%.0f%% across", progress * 100)
        case .across(let seconds):
            return String(format: "Across in %.1f s", seconds)
        case .inTheLake(let seconds):
            return String(format: "In the lake after %.1f s", seconds)
        }
    }
}
