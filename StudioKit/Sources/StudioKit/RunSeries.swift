import Foundation
import DuckKit

/// The run as a set of curves, rather than as a set of totals.
///
/// A MEDIAN CANNOT SAY WHEN. "Peak tilt 84°" tells you the robot went a long
/// way over and not whether that was the move working or the move failing —
/// `roulade` is supposed to go past 90° and `step_up` is not, and the two look
/// identical in a summary. The curve says which, because the shape of the
/// height trace over four seconds is the difference between a roll and a fall.
///
/// EVERY SERIES IS SAMPLED FROM THE RECORDING ITSELF, one point per tick, with
/// no smoothing. A smoothed curve is a nicer picture and a worse measurement:
/// the interesting features here are the sharp ones — the instant a foot lands,
/// the tick a joint hits its stop — and a filter removes exactly those.
public struct RunSeries: Equatable, Sendable {

    public struct Point: Equatable, Sendable, Identifiable {
        public let time: TimeInterval
        public let value: Double
        public var id: TimeInterval { time }
    }

    /// One curve, with everything a chart needs to draw and label it.
    public struct Track: Equatable, Sendable, Identifiable {
        public let name: String
        public let unit: String
        public let points: [Point]
        /// A line worth drawing across the chart, if the value has a meaningful
        /// threshold — the height a standing robot sits at, the tilt where an
        /// episode would have been terminated.
        public let reference: (value: Double, label: String)?
        /// What the curve means, in one line.
        public let detail: String
        public var id: String { name }

        public var range: ClosedRange<Double> {
            let values = points.map(\.value) + (reference.map { [$0.value] } ?? [])
            let low = values.min() ?? 0, high = values.max() ?? 1
            // A flat curve still needs a band to be drawn in, or the chart
            // collapses to a line at an arbitrary height.
            guard high - low > 1e-9 else { return (low - 1)...(high + 1) }
            let pad = (high - low) * 0.08
            return (low - pad)...(high + pad)
        }

        public static func == (l: Track, r: Track) -> Bool {
            l.name == r.name && l.points == r.points
        }
    }

    public let tracks: [Track]

    public init(clip: DuckIntentClip) {
        let dt = 1.0 / clip.hz
        let roots = clip.roots
        var height: [Point] = [], tilt: [Point] = [], speed: [Point] = []

        for (index, root) in roots.enumerated() {
            let time = Double(index) * dt
            height.append(Point(time: time, value: root.z * 1000))
            tilt.append(Point(time: time,
                              value: RunMetrics.tilt(root.quaternion) * 180 / .pi))
            guard index > 0 else {
                speed.append(Point(time: 0, value: 0))
                continue
            }
            let dx = root.x - roots[index - 1].x
            let dy = root.y - roots[index - 1].y
            speed.append(Point(time: time,
                               value: (dx * dx + dy * dy).squareRoot() / dt * 1000))
        }

        var tracks: [Track] = [
            Track(name: "Trunk height", unit: "mm", points: height,
                  reference: (DuckStance.standingHeight * 1000, "standing"),
                  detail: "Where the trunk is. The standing policy settles at "
                        + "\(Int((DuckStance.standingHeight * 1000).rounded())) mm and sitting settles at 59 mm, "
                        + "so the gap between the curve and the line is the whole story of a crouch, "
                        + "a fall or a climb."),
            Track(name: "Tilt", unit: "°", points: tilt,
                  reference: (45, "on its side"),
                  detail: "The angle between the trunk's up and the world's. Past 45° the robot is "
                        + "going over — which the velocity and kick configs end an episode for, and "
                        + "which sit/stand and roulade delete that termination to allow."),
            Track(name: "Speed", unit: "mm/s", points: speed, reference: nil,
                  detail: "How fast the trunk is travelling across the floor, per tick, unsmoothed."),
        ]

        // The two curves that only exist because the recording carries what the
        // policy emitted. A clip from before format 3 simply has fewer tracks
        // rather than flat lines at zero.
        if !clip.telemetry.actions.isEmpty {
            var effort: [Point] = [], rate: [Point] = []
            for (index, action) in clip.telemetry.actions.enumerated() {
                let time = Double(index) * dt
                effort.append(Point(time: time,
                                    value: action.map { abs($0) }.max() ?? 0))
                guard index > 0 else { rate.append(Point(time: 0, value: 0)); continue }
                let previous = clip.telemetry.actions[index - 1]
                var square = 0.0
                for slot in 0..<min(action.count, previous.count) {
                    let d = action[slot] - previous[slot]
                    square += d * d
                }
                rate.append(Point(time: time, value: square))
            }
            tracks.append(Track(
                name: "Largest action", unit: "", points: effort, reference: nil,
                detail: "The biggest single number the network asked for at that tick, before the "
                      + "gait scales it by \(DuckModel.actionScale) and before the travel stops clamp it."))
            tracks.append(Track(
                name: "Action rate", unit: "", points: rate, reference: nil,
                detail: "The squared change between consecutive decisions — the exact quantity "
                      + "`action_rate_l2` penalises. Spikes are where the policy changed its mind."))
        }

        if !clip.telemetry.twists.isEmpty {
            let turn = clip.telemetry.twists.enumerated().map { index, twist in
                Point(time: Double(index) * dt,
                      value: twist.count >= 6 ? twist[5] * 180 / .pi : 0)
            }
            tracks.append(Track(
                name: "Turn rate", unit: "°/s", points: turn, reference: (0, "straight"),
                detail: "The trunk's yaw rate in its own frame, as recorded — not differenced from "
                      + "the quaternions, which would add the noise of two finite differences."))
        }

        self.tracks = tracks
    }

    /// One joint at one moment: where it is and which way it is moving.
    ///
    /// THE AGGREGATE ROWS CANNOT ANSWER THE QUESTION A SCRUBBER ASKS. "17.8 rad
    /// of travel over the run" is true for the whole clip and useless at
    /// t = 2.6 s, when what you want to know is which servos are driving and
    /// which way — a headspin that falls backwards is diagnosed by seeing the
    /// hip pitches both pushing the same direction at the moment it goes, and
    /// no summary can show that.
    public struct JointMoment: Equatable, Sendable, Identifiable {
        public let name: String
        /// Where the joint is, radians.
        public let angle: Double
        /// How fast it is moving, radians per second, SIGNED — the sign is the
        /// point, it is the "which direction" in "which servos are moving in
        /// which direction". Finite-differenced from the achieved positions.
        public let velocity: Double
        public var id: String { name }

        /// Whether the joint is meaningfully moving at this instant. The bound
        /// is a twentieth of a radian a second — a servo drifting slower than
        /// that reads as holding.
        public var isMoving: Bool { abs(velocity) > 0.05 }
    }

    /// Every policy joint at a moment in a clip, in policy-slot order.
    ///
    /// Velocity is the centred difference of the ACHIEVED positions around the
    /// nearest tick (one-sided at the ends). Achieved, not commanded: the
    /// question on a scrubber is what the robot is doing, and a clamped or
    /// lagging servo is doing something different from what it was told.
    public static func joints(of clip: DuckIntentClip, at time: TimeInterval) -> [JointMoment] {
        let count = clip.frames.count
        guard count > 0 else { return [] }
        let dt = 1.0 / clip.hz
        let tick = min(max(Int((time * clip.hz).rounded()), 0), count - 1)
        let before = max(tick - 1, 0)
        let after = min(tick + 1, count - 1)
        let span = Double(after - before) * dt

        return (0..<DuckModel.policyJointCount).map { slot in
            let joint = DuckModel.jointOfPolicySlot(slot)
            let here = clip.frames[tick]
            let a = clip.frames[before], b = clip.frames[after]
            let velocity = span > 0 && slot < a.count && slot < b.count
                ? (b[slot] - a[slot]) / span
                : 0
            return JointMoment(
                name: DuckModel.jointNames[joint],
                angle: slot < here.count ? here[slot] : 0,
                velocity: velocity)
        }
    }

    /// The value of every track at a moment, for a readout beside the playhead.
    public func readings(at time: TimeInterval) -> [RunMetrics.Reading] {
        tracks.map { track in
            let point = track.points.min {
                abs($0.time - time) < abs($1.time - time)
            }
            return RunMetrics.Reading(
                track.name,
                point.map { String(format: "%.1f %@", $0.value, track.unit) } ?? "—")
        }
    }
}
