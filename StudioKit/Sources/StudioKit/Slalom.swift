import Foundation

/// Slalom: gates on the floor, and the one limit that decides everything.
///
/// A DUCK CANNOT TURN ON THE SPOT. Commanded yaw saturates at about 14 degrees
/// and stops, so every change of direction is an arc, and an arc has a radius:
/// `walkSpeed / turnRate`. On legs that is 0.106 / 0.34 = **0.31 m**. On skates
/// it is 0.45 / 0.5 = **0.90 m** — three times wider, because the skates go
/// four times faster and turn barely faster at all.
///
/// SO THE SKATES' ADVANTAGE MOSTLY EVAPORATES, AND THAT IS THE GAME. The
/// course below needs a 0.31 m radius, which the legs hold at a full walk —
/// it was cut to fit them exactly. A skater cannot make it at full tilt at any
/// steering angle; it has to throttle back to about 0.155 m/s before its arc
/// fits. That is still quicker than the legs, but the 4.2× it enjoys in a
/// straight line comes down to about 1.5× through gates. Nothing here is tuned
/// to produce that; it falls out of two measured envelopes and one piece of
/// school geometry.
///
/// AND THE SKATES' TURN RATE IS THE SHAKIEST NUMBER IN EITHER SET. What was
/// measured is asymmetric — +0.94 rad/s one way, −0.19 the other — and 0.5 is
/// the gameplay midpoint, labelled as such where it is defined. A real skating
/// duck would find one direction of this course far worse than the other.
///
/// Turn rate does not fall off with speed in this model, and that matches the
/// robot: the policy takes a yaw command independent of its forward command,
/// so slowing down genuinely does tighten the arc.
public struct Slalom: Equatable, Sendable {

    /// Seconds added for going past a gate on the wrong side of a post. It is
    /// a penalty rather than a re-run because a duck that cannot turn on the
    /// spot also cannot go back for a gate without a long loop, and a game
    /// that demands one is a game about waiting.
    public static let missPenalty = 3.0

    public struct Gate: Equatable, Sendable {
        public let center: DuckSoccer.Vec2
        /// The direction that counts as through. Crossing the other way is
        /// not a pass.
        public let heading: Double
        /// Half the gap between the posts.
        public let halfWidth: Double

        public init(center: DuckSoccer.Vec2, heading: Double, halfWidth: Double = 0.20) {
            self.center = center; self.heading = heading; self.halfWidth = halfWidth
        }

        /// The gate's own axes: `normal` points the way through.
        var normal: DuckSoccer.Vec2 { .init(cos(heading), sin(heading)) }
        var across: DuckSoccer.Vec2 { .init(-sin(heading), cos(heading)) }
    }

    /// Five gates, 0.7 m apart, offset ±0.16 m either side of the line.
    ///
    /// THE NUMBERS ARE CHOSEN FROM THE LEGS' RADIUS, not from taste. A slalom
    /// of offset `a` and spacing `d` is about a sine of wavelength `2d`, whose
    /// tightest radius is `(2d / 2π)² / a`; at d = 0.7 and a = 0.16 that is
    /// 0.31 m, which is exactly what the legs can hold flat out. One notch
    /// wider and the course is free; one notch tighter and the legs cannot
    /// clean it either, which would make the whole thing a slow parade.
    public static let course: [Gate] = [
        .init(center: .init(0.7, 0.16), heading: 0),
        .init(center: .init(1.4, -0.16), heading: 0),
        .init(center: .init(2.1, 0.16), heading: 0),
        .init(center: .init(2.8, -0.16), heading: 0),
        .init(center: .init(3.5, 0.0), heading: 0),
    ]

    /// The tightest arc this envelope can hold at a full walk, in metres.
    public static func minimumTurnRadius(_ capabilities: DuckSoccer.Capabilities) -> Double {
        capabilities.walkSpeed / capabilities.turnRate
    }

    /// The fastest this envelope can go and still hold an arc of `radius`.
    /// Never faster than it can actually walk.
    public static func topSpeed(forRadius radius: Double,
                                _ capabilities: DuckSoccer.Capabilities) -> Double {
        min(radius * capabilities.turnRate, capabilities.fastSpeed)
    }

    /// The tightest radius a course demands, from its spacing and offset.
    public static func requiredRadius(_ gates: [Gate]) -> Double {
        guard gates.count >= 2 else { return .infinity }
        var tightest = Double.infinity
        for i in 1..<gates.count {
            // Spacing measured ALONG the course, not centre to centre: the
            // lateral offset is the amplitude, and counting it twice (once in
            // `d`, once in `a`) flatters the course into looking easier.
            let step = gates[i].center - gates[i - 1].center
            let n = gates[i].normal
            let d = abs(step.x * n.x + step.y * n.y)
            let a = abs(step.x * gates[i].across.x + step.y * gates[i].across.y) / 2
            guard a > 1e-6 else { continue }
            let wavelength = 2 * d
            tightest = min(tightest, (wavelength / (2 * .pi)) * (wavelength / (2 * .pi)) / a)
        }
        return tightest
    }

    public let gates: [Gate]
    public let capabilities: DuckSoccer.Capabilities
    public private(set) var duck: FetchRun.Duck
    public private(set) var next = 0
    public private(set) var missed = 0
    public private(set) var elapsed = 0.0

    public init(gates: [Gate] = Slalom.course,
                capabilities: DuckSoccer.Capabilities = .measured,
                start: FetchRun.Duck = .init()) {
        self.gates = gates
        self.capabilities = capabilities
        self.duck = start
    }

    public var isFinished: Bool { next >= gates.count }
    /// Elapsed plus penalties. This is the score.
    public var time: Double { elapsed + Double(missed) * Slalom.missPenalty }
    public var cleared: Int { next - missed }

    /// Drive for `dt`. `forward` and `turn` are stick, each −1…1.
    public mutating func advance(dt: Double, forward: Double, turn: Double) {
        guard !isFinished, dt > 0 else { return }
        elapsed += dt
        let steer = max(-1, min(1, turn))
        let throttle = max(-1, min(1, forward))
        duck.heading += steer * capabilities.turnRate * dt
        let speed = throttle >= 0
            ? throttle * capabilities.walkSpeed
            : throttle * capabilities.backSpeed
        let before = duck.position
        duck.position = before
            + DuckSoccer.Vec2(cos(duck.heading), sin(duck.heading)) * (speed * dt)
        judge(from: before, to: duck.position)
    }

    /// Did that step take us through the next gate's plane, and if so, where?
    private mutating func judge(from a: DuckSoccer.Vec2, to b: DuckSoccer.Vec2) {
        guard next < gates.count else { return }
        let gate = gates[next]
        let n = gate.normal
        let alongA = (a - gate.center).x * n.x + (a - gate.center).y * n.y
        let alongB = (b - gate.center).x * n.x + (b - gate.center).y * n.y
        // Forward crossings only. Reversing back over a gate does not undo it
        // and does not earn it.
        guard alongA < 0, alongB >= 0 else { return }
        let span = alongB - alongA
        let t = span > 1e-9 ? (-alongA) / span : 0
        let at = a + (b - a) * t
        let across = (at - gate.center).x * gate.across.x + (at - gate.center).y * gate.across.y
        if abs(across) > gate.halfWidth { missed += 1 }
        next += 1
    }

    public var summary: String {
        if isFinished {
            let penalty = missed == 0 ? "clean" : "\(missed) missed, +\(Int(Double(missed) * Slalom.missPenalty))s"
            return String(format: "%.1f s — %@", time, penalty)
        }
        return "Gate \(next + 1) of \(gates.count) · \(String(format: "%.1f", time)) s"
    }
}
