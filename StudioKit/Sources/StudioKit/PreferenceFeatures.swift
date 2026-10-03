import Foundation
import DuckKit

/// What a person choosing between two walkers could be choosing ABOUT, measured from the clip
/// they were shown.
///
/// THE SAME SEVEN FEATURES duckbatch's preference model fits (`pairs.py` `FEATURES`, in that
/// order): `lin_err, ang_err, fell, down_frac, action_rate, jitter, wobble`. A pick only
/// teaches anything if the model can see what differed between the two sides, and a
/// `duck-feedback/0` preference record carried who was shown, not what they did. These
/// numbers go into the record beside the choice.
///
/// FIVE ARE MEASURED, TWO ARE STAND-INS, AND THE NAMES SAY WHICH. A bench clip carries the
/// trunk's position and orientation and the fourteen joint angles at the clip's rate — no
/// velocities and no network outputs.
/// - `lin_err`, `ang_err`, `wobble`: the trunk's twist by finite difference of position and
///   orientation, in the body frame, as mjlab's `root_link_lin_vel_b` / `_ang_vel_b` are.
/// - `fell`, `down_frac`: projected gravity from the orientation, down when its z is above
///   −0.5, exactly `pairs.py`'s test.
/// - `action_rate`, `jitter`: `pairs.py` reads the NETWORK'S OUTPUT, which a clip does not
///   have. These are the same first and second differences of the measured JOINT ANGLES —
///   what the servos did, not what they were told. They move together; they are not equal,
///   and `isJointProxy` is in every record so nobody mistakes one for the other.
public struct PreferenceFeatures: Equatable, Sendable {
    public static let names = ["lin_err", "ang_err", "fell", "down_frac",
                               "action_rate", "jitter", "wobble"]
    /// `action_rate` and `jitter` come from joint angles, not network outputs.
    public static let isJointProxy = true

    public let values: [Double]

    public init(values: [Double]) { self.values = values }

    public enum Refusal: Error, Equatable {
        case tooShort(Int)
        case noRate

        public var message: String {
            switch self {
            case .tooShort(let n):
                return "That clip has \(n) frames; measuring how it moved needs at least three."
            case .noRate:
                return "That clip does not say how fast it was recorded, so no speed can be read from it."
            }
        }
    }

    /// Measure a clip against the command it was recorded under.
    ///
    /// `command` is (vx, vy, wz) in the body frame. A per-frame command from the clip's own
    /// telemetry wins when it has one row per frame, because `/record` writes what it sent.
    public static func measure(_ clip: DuckIntentClip, command: (Double, Double, Double))
        throws -> PreferenceFeatures {
        let n = min(clip.frames.count, clip.roots.count)
        guard n >= 3 else { throw Refusal.tooShort(n) }
        guard clip.hz > 0 else { throw Refusal.noRate }
        let dt = 1 / clip.hz
        let perFrame = clip.telemetry.commands.count >= n
            ? clip.telemetry.commands : nil

        var lin = 0.0, ang = 0.0, upN = 0.0, down = 0.0, wob = 0.0
        var fell = 0.0, arate = 0.0, jit = 0.0
        // A twist needs two roots, so it is read on n − 1 steps.
        for t in 1..<n {
            let q0 = Quat(clip.roots[t - 1].quaternion), q1 = Quat(clip.roots[t].quaternion)
            let dWorld = (clip.roots[t].x - clip.roots[t - 1].x,
                          clip.roots[t].y - clip.roots[t - 1].y,
                          clip.roots[t].z - clip.roots[t - 1].z)
            let v = q1.conjugate.rotate((dWorld.0 / dt, dWorld.1 / dt, dWorld.2 / dt))
            let w = q0.bodyRate(to: q1, dt: dt)
            let g = q1.conjugate.rotate((0, 0, -1))
            let isDown = g.2 > -0.5
            var cmd = command
            if let rows = perFrame {
                let r = rows[t]
                cmd = (r.count > 0 ? r[0] : 0, r.count > 1 ? r[1] : 0, r.count > 2 ? r[2] : 0)
            }
            if !isDown {
                lin += ((cmd.0 - v.0) * (cmd.0 - v.0) + (cmd.1 - v.1) * (cmd.1 - v.1)).squareRoot()
                ang += abs(cmd.2 - w.2)
                upN += 1
            }
            if isDown { down += 1; fell = 1 }
            wob += w.0 * w.0 + w.1 * w.1
            arate += meanAbs(clip.frames[t], clip.frames[t - 1])
            if t >= 2 {
                jit += meanAbsSecond(clip.frames[t], clip.frames[t - 1], clip.frames[t - 2])
            }
        }
        let steps = Double(n - 1)
        return PreferenceFeatures(values: [
            lin / max(upN, 1), ang / max(upN, 1), fell, down / steps,
            arate / max(steps, 1), jit / max(steps - 1, 1), (wob / steps).squareRoot(),
        ])
    }

    private static func meanAbs(_ a: [Double], _ b: [Double]) -> Double {
        let k = min(a.count, b.count)
        guard k > 0 else { return 0 }
        return (0..<k).reduce(0) { $0 + abs(a[$1] - b[$1]) } / Double(k)
    }

    private static func meanAbsSecond(_ a: [Double], _ b: [Double], _ c: [Double]) -> Double {
        let k = min(a.count, b.count, c.count)
        guard k > 0 else { return 0 }
        return (0..<k).reduce(0) { $0 + abs(a[$1] - 2 * b[$1] + c[$1]) } / Double(k)
    }
}

/// A unit quaternion (w, x, y, z), MuJoCo's order — only what the features need.
struct Quat {
    let w, x, y, z: Double
    init(_ q: (Double, Double, Double, Double)) {
        let n = (q.0 * q.0 + q.1 * q.1 + q.2 * q.2 + q.3 * q.3).squareRoot()
        let s = n > 0 ? 1 / n : 1
        w = q.0 * s; x = q.1 * s; y = q.2 * s; z = q.3 * s
    }
    init(w: Double, x: Double, y: Double, z: Double) { self.w = w; self.x = x; self.y = y; self.z = z }

    var conjugate: Quat { Quat(w: w, x: -x, y: -y, z: -z) }

    static func * (a: Quat, b: Quat) -> Quat {
        Quat(w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
             x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
             y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
             z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w)
    }

    /// Rotate a vector from the frame this quaternion maps FROM into the one it maps TO.
    func rotate(_ v: (Double, Double, Double)) -> (Double, Double, Double) {
        let r = self * Quat(w: 0, x: v.0, y: v.1, z: v.2) * conjugate
        return (r.x, r.y, r.z)
    }

    /// Body-frame angular velocity carrying this orientation to `next` in `dt`.
    func bodyRate(to next: Quat, dt: Double) -> (Double, Double, Double) {
        var d = conjugate * next
        if d.w < 0 { d = Quat(w: -d.w, x: -d.x, y: -d.y, z: -d.z) }   // the short way round
        let s = (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
        guard s > 1e-12 else { return (0, 0, 0) }
        let angle = 2 * atan2(s, d.w)
        let k = angle / (s * dt)
        return (d.x * k, d.y * k, d.z * k)
    }
}
