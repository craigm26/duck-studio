import Foundation

/// Fetch: drop balls on the floor and time the duck bringing them in.
///
/// THE STEERING LAW IS THE ONE THAT WAS PROVEN ON THE BENCH. `walk_to` in
/// duck-sounds arrives at a ball 8 times out of 8, from anywhere between dead
/// ahead and 40 degrees off the nose, stopping at a median 0.242 m — steering
/// on nothing but a camera bearing. This is that controller: square up if the
/// target is more than 25 degrees off, otherwise walk and turn at the same
/// time, because the duck cannot turn on the spot.
///
/// AND HERE IT IS NOT SEEING ANYTHING. On the bench the bearing comes from a
/// rendered frame through a Hailo. In AR the app already knows where the
/// virtual ball is, so this computes the bearing from coordinates. Same law,
/// different source, and they are different claims — the screen says which one
/// is running rather than letting a demo imply the robot has eyes it is not
/// using.
public struct FetchRun: Equatable, Sendable {

    /// Copied from walk_to, which took them from quackd's composite and the
    /// duck's own measured envelope.
    public static let arriveWithin = 0.25
    public static let squareUpBeyond = 25.0        // degrees
    public static let turnGain = 0.05              // per degree

    public struct Duck: Equatable, Sendable {
        public var position: DuckSoccer.Vec2
        public var heading: Double
        public init(position: DuckSoccer.Vec2 = .init(0, 0), heading: Double = 0) {
            self.position = position; self.heading = heading
        }
    }

    public private(set) var duck = Duck()
    public private(set) var pending: [DuckSoccer.Vec2]
    public private(set) var fetched: [DuckSoccer.Vec2] = []
    public private(set) var elapsed = 0.0
    public let capabilities: DuckSoccer.Capabilities

    public init(balls: [DuckSoccer.Vec2],
                capabilities: DuckSoccer.Capabilities = .measured) {
        self.pending = balls
        self.capabilities = capabilities
    }

    public var target: DuckSoccer.Vec2? { pending.first }
    public var isFinished: Bool { pending.isEmpty }

    /// Bearing to the current ball, degrees, POSITIVE = LEFT — the same
    /// convention the detector and the robot both use.
    public var bearingDegrees: Double? {
        guard let target else { return nil }
        let to = target - duck.position
        let bearing = atan2(to.y, to.x) - duck.heading
        return atan2(sin(bearing), cos(bearing)) * 180 / .pi
    }

    public mutating func advance(dt: Double) {
        guard let target, dt > 0 else { return }
        elapsed += dt
        guard let bearing = bearingDegrees else { return }

        // walk_to's law, verbatim.
        let turn = max(-1, min(1, bearing * Self.turnGain))
        let squaringUp = abs(bearing) > Self.squareUpBeyond
        let speed = squaringUp ? capabilities.walkSpeed : capabilities.fastSpeed

        // IT ARCS EVEN WHILE SQUARING UP. Standing still to turn is the one
        // thing that does not work — commanded yaw saturates at about 14
        // degrees and stops — so "square up first" means slow down, never halt.
        duck.heading += turn * capabilities.turnRate * dt
        duck.position = duck.position
            + DuckSoccer.Vec2(cos(duck.heading), sin(duck.heading)) * (speed * dt)

        if (target - duck.position).length <= Self.arriveWithin {
            fetched.append(pending.removeFirst())
        }
    }

    /// Carry a run's progress into a new one, so dropping another ball does
    /// not teleport the duck back to where it started.
    public mutating func resume(from duck: Duck, fetched: [DuckSoccer.Vec2],
                                elapsed: Double) {
        self.duck = duck
        self.fetched = fetched
        self.elapsed = elapsed
    }

    public var summary: String {
        if isFinished {
            return String(format: "All %d fetched in %.1f s", fetched.count, elapsed)
        }
        return String(format: "%d of %d — %.1f s", fetched.count,
                      fetched.count + pending.count, elapsed)
    }
}
