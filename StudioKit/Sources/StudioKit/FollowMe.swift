import Foundation

/// Follow me: the duck keeps station on a person, and you find out how slowly
/// you have to walk.
///
/// THE PERCEPTION HERE IS REAL, which is why this mode exists. Everything else
/// in the lab feeds the steering law coordinates the app already knows. Here
/// the thing being followed is the phone, and ARKit's camera pose is a
/// measurement of where a person actually is in the room — not a simulation of
/// one. The law on top of it is `walk_to`'s, which arrived at a target 8 times
/// out of 8 on the bench.
///
/// AND THE ANSWER IS: MUCH MORE SLOWLY THAN YOU WALK. A person strolls at about
/// 1.4 m/s. The duck walks at 0.106. It is thirteen times slower than you are,
/// so "follow me" is a game about how patient you are willing to be, and the
/// mode says so instead of quietly speeding the duck up to make itself fun.
///
/// IT ALSO CANNOT CREEP. Below a forward command of about 0.25 the policy
/// marches in place and covers no ground, so there is no slow-follow: the duck
/// either walks at 0.106 m/s or stands still. Following someone who is barely
/// moving therefore looks like stop, start, stop, start — that stutter is the
/// robot, not the renderer.
public struct FollowMe: Equatable, Sendable {

    /// How close it tries to sit. Roughly two body radii plus a margin — near
    /// enough to read as company, far enough not to be underfoot.
    public static let standoff = 0.45
    /// It sets off again once you are this much further away than the
    /// standoff. Without the gap it would chatter between walk and stop every
    /// tick, which is a rendering artefact rather than a robot.
    public static let hysteresis = 0.10
    /// Beyond this it has lost you.
    public static let losesYouBeyond = 2.5
    /// Above this bearing it prioritises coming round, the same threshold the
    /// bench controller uses.
    public static let squareUpBeyond = FetchRun.squareUpBeyond

    /// An unhurried human walking pace, for the comparison the mode is about.
    /// Not measured here — it is the standard figure, and it is used only to
    /// print a ratio.
    public static let humanPace = 1.4

    public static func paceRatio(_ capabilities: DuckSoccer.Capabilities) -> Double {
        humanPace / capabilities.walkSpeed
    }

    public let capabilities: DuckSoccer.Capabilities
    public private(set) var duck: FetchRun.Duck
    public private(set) var person: DuckSoccer.Vec2
    public private(set) var elapsed = 0.0
    /// Seconds spent within reach of station.
    public private(set) var inStation = 0.0
    /// Seconds spent having lost you altogether.
    public private(set) var lost = 0.0
    /// Whether the last tick actually covered ground. The stutter, exposed so
    /// a view can animate walking rather than guessing from positions.
    public private(set) var isWalking = false

    public init(capabilities: DuckSoccer.Capabilities = .measured,
                duck: FetchRun.Duck = .init(),
                person: DuckSoccer.Vec2 = .init(1.0, 0)) {
        self.capabilities = capabilities
        self.duck = duck
        self.person = person
    }

    public var range: Double { (person - duck.position).length }

    /// Signed bearing to the person, degrees, positive to the duck's left.
    public var bearingDegrees: Double {
        let to = person - duck.position
        let raw = atan2(to.y, to.x) - duck.heading
        return atan2(sin(raw), cos(raw)) * 180 / .pi
    }

    public var hasLostYou: Bool { range > FollowMe.losesYouBeyond }

    /// Advance one tick. `person` is where the phone is now — in AR that is a
    /// measured camera pose, not a guess.
    public mutating func advance(dt: Double, person: DuckSoccer.Vec2) {
        guard dt > 0 else { return }
        self.person = person
        elapsed += dt

        let distance = range
        // Walk or stand — there is no third option, because the policy has no
        // usable command between them.
        let wantsToMove = isWalking
            ? distance > FollowMe.standoff
            : distance > FollowMe.standoff + FollowMe.hysteresis
        isWalking = wantsToMove

        if wantsToMove {
            let bearing = bearingDegrees
            let turn = max(-1, min(1, bearing * FetchRun.turnGain))
            // IT TURNS ONLY WHILE WALKING, because that is the only way it
            // turns. A duck asked to pivot on the spot saturates at about 14
            // degrees and stops.
            duck.heading += turn * capabilities.turnRate * dt
            let speed = abs(bearing) > FollowMe.squareUpBeyond
                ? capabilities.walkSpeed * 0.7   // come round rather than overshoot
                : capabilities.walkSpeed
            duck.position = duck.position
                + DuckSoccer.Vec2(cos(duck.heading), sin(duck.heading)) * (speed * dt)
        }

        let now = range
        if now <= FollowMe.standoff + 0.25 { inStation += dt }
        if now > FollowMe.losesYouBeyond { lost += dt }
    }

    public var summary: String {
        if hasLostYou {
            return String(format: "Lost you — %.1f m away. Slow down.", range)
        }
        let share = elapsed > 0 ? inStation / elapsed * 100 : 0
        return String(format: "%.2f m away · in station %.0f%% of %.0f s", range, share, elapsed)
    }
}
