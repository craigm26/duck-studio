import Foundation

/// A driver's answers put back onto the commands its teacher gave, before the pilot plays them.
///
/// WHY. Behaviour cloning averages. The scripted expert (`BallExpert`) only ever says forward 0 or
/// at least `walkStart` (0.25 m/s), a turn of 0 or at least `minTurn` (0.1 rad/s), and never
/// sideways, because the sim duck's walker does not step from rest below about 0.22 m/s and a tiny
/// turn shows nothing. The v4 driver learned the shape of that but softened it: its stand was
/// forward 0.00 to 0.05 (not 0), its approach and search speeds drifted into the walker's dead band,
/// and its search turn was 0.2 to 0.5 of the expert's. Snapping maps each row back onto the
/// expert's command set:
/// - forward under `forwardZeroBelow` is 0 (stand), from there to `forwardStart` is `forwardStart`
///   (walk at the least speed the walker starts for), and above that it is kept, up to the stick;
/// - a turn smaller than `turnZeroBelow` either way is 0, larger is kept, up to the stick;
/// - sideways is 0 unless `keepSideways`.
///
/// WHERE IT COMES FROM. `policy.json` may carry a `snap` block; a driver without one gets the
/// numbers pinned for its weights in `known` (v4, published before snapping existed), and any
/// other driver is played as it answers.
public struct DriverSnap: Decodable, Equatable, Sendable {
    public let forwardZeroBelow: Double
    public let forwardStart: Double
    public let turnZeroBelow: Double
    public let keepSideways: Bool

    enum CodingKeys: String, CodingKey {
        case forwardZeroBelow = "forward_zero_below", forwardStart = "forward_start"
        case turnZeroBelow = "turn_zero_below", keepSideways = "keep_sideways"
    }

    public init(forwardZeroBelow: Double, forwardStart: Double, turnZeroBelow: Double, keepSideways: Bool = false) {
        self.forwardZeroBelow = forwardZeroBelow; self.forwardStart = forwardStart
        self.turnZeroBelow = turnZeroBelow; self.keepSideways = keepSideways
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        forwardZeroBelow = try c.decode(Double.self, forKey: .forwardZeroBelow)
        forwardStart = try c.decode(Double.self, forKey: .forwardStart)
        turnZeroBelow = try c.decode(Double.self, forKey: .turnZeroBelow)
        keepSideways = try c.decodeIfPresent(Bool.self, forKey: .keepSideways) ?? false
    }

    /// The expert's command set: stand or walk at `BallExpert.walkStart`, no turn under
    /// `BallExpert.minTurn`, no sideways. 0.12 is about half of walkStart: nearer 0 than 0.25.
    public static let expert = DriverSnap(forwardZeroBelow: 0.12, forwardStart: BallExpert.walkStart,
                                          turnZeroBelow: BallExpert.minTurn)

    /// Drivers published before `snap` existed, by the SHA-256 of their `model.safetensors`.
    public static let known: [String: DriverSnap] = [
        // craigm26/duck-driver-walk-to-ball-v4 @ 3dfbade (round 3, val L1 0.139).
        "7e00bdb27c7668604f8eef335dc12aabba4902b1b80cc10c7ec3f7e377b476c2": .expert,
    ]

    /// Whether these numbers make sense for the sticks: finite, in order, inside the stick limits.
    public var isValid: Bool {
        let all = [forwardZeroBelow, forwardStart, turnZeroBelow]
        return all.allSatisfy(\.isFinite)
            && forwardZeroBelow >= 0 && forwardZeroBelow <= forwardStart && forwardStart <= DuckDrive.maxForward
            && turnZeroBelow >= 0 && turnZeroBelow <= DuckDrive.maxTurn
    }

    /// One row on the expert's command set, clamped to the sticks.
    public func apply(_ t: DuckDrive.Twist) -> DuckDrive.Twist {
        let vx: Double
        if t.vx < forwardZeroBelow { vx = 0 }
        else if t.vx < forwardStart { vx = forwardStart }
        else { vx = min(t.vx, DuckDrive.maxForward) }
        let vyaw = abs(t.vyaw) < turnZeroBelow ? 0 : min(max(t.vyaw, -DuckDrive.maxTurn), DuckDrive.maxTurn)
        let vy = keepSideways ? min(max(t.vy, -DuckDrive.maxSideways), DuckDrive.maxSideways) : 0
        return DuckDrive.Twist(vx: vx, vy: vy, vyaw: vyaw)
    }
}
