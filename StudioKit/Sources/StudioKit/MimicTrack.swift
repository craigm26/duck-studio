import Foundation
import DuckKit

/// A run of retargeted poses, becoming a motion.
///
/// A CAMERA ANSWERS THIRTY TIMES A SECOND AND A MOTION IS NOT THIRTY KEYFRAMES
/// A SECOND. A keyframe is a pose somebody meant; a frame is a pose a model
/// guessed, with the jitter of a guess in it. So this type keeps one keyframe
/// every `keySpacing` seconds, smooths each new pose against the last one it
/// kept, and holds every joint under the rate the motion editor already
/// refuses — `IntentDraft.observedPeakJointRate` — so what it writes is a
/// draft the editor can play rather than one it flags as impossible on its
/// first line.
///
/// IT STARTS AT ZERO ON THE FIRST POSE IT IS GIVEN. A recording remixed to a
/// draft opens on its own first frame, and the editor's `problems` says why:
/// how the robot reaches its opening pose is the player's business. A track
/// that opened with a keyframe at 0 s of the home stance would put a snap from
/// standing to the first real pose at the front of every motion.
///
/// THIRTY SECONDS, AND IT SAYS SO. The bench performs a motion as one batch
/// call with a timeout, and a person mimicking for a minute has three hundred
/// keyframes and a run the bench will not finish. The cap is where the record
/// button stops on its own, not where the motion is silently cut.
public struct MimicTrack: Equatable, Sendable {

    /// Seconds between kept keyframes. Ten a second is well above the rate at
    /// which a person changes what they are doing and well below a camera.
    public static let keySpacing = 0.1
    /// How much of the new pose a kept keyframe takes; the rest is the
    /// keyframe before it. Half is one frame of memory — enough to take the
    /// jitter off a knee, not enough to make a nod arrive late.
    public static let smoothing = 0.5
    /// The longest a track will record.
    public static let maxSeconds = 30.0
    /// The rate a joint is held under, with room under the editor's own limit
    /// so that a keyframe the smoothstep peaks over is still inside it.
    public static let rateCeiling = IntentDraft.observedPeakJointRate * 0.8
    /// Floating-point slack on the spacing comparison.
    static let sameInstant = 1e-6

    public private(set) var keys: [IntentDraft.Key] = []
    private var started: TimeInterval?

    public init() {}

    /// Seconds recorded so far.
    public var seconds: TimeInterval { keys.last?.time ?? 0 }
    public var keyCount: Int { keys.count }
    public var isEmpty: Bool { keys.isEmpty }
    /// True once the cap is reached; `add` keeps nothing after it.
    public var isFull: Bool { seconds >= Self.maxSeconds }

    /// Offer a pose at a clock time. Kept when enough time has passed since
    /// the last keyframe; otherwise dropped. Returns whether it was kept.
    @discardableResult
    public mutating func add(_ pose: [Double], at clock: TimeInterval) -> Bool {
        guard pose.count == DuckModel.jointCount, pose.allSatisfy(\.isFinite) else { return false }
        guard let started else {
            self.started = clock
            keys = [IntentDraft.Key(time: 0, pose: pose)]
            return true
        }
        let t = clock - started
        // A hair under the spacing counts: a camera at exactly thirty frames a
        // second lands its third frame at 0.0999… and would otherwise keep
        // every fourth instead of every third.
        guard t >= seconds + Self.keySpacing - Self.sameInstant, !isFull else { return false }
        let time = min(t, Self.maxSeconds)
        let previous = keys.last!
        let span = time - previous.time
        let allowed = Self.rateCeiling * span / 1.5
        let next = (0..<DuckModel.jointCount).map { joint -> Double in
            let want = previous.pose[joint] + (pose[joint] - previous.pose[joint]) * Self.smoothing
            let delta = want - previous.pose[joint]
            return previous.pose[joint] + min(max(delta, -allowed), allowed)
        }
        keys.append(IntentDraft.Key(time: time, pose: next))
        return true
    }

    /// Start again.
    public mutating func clear() {
        keys = []
        started = nil
    }

    /// What was recorded, as a motion Studio can hold. Nil for a track with
    /// nothing in it, and a one-keyframe track is given a second so the
    /// editor has a span to play — the same shape `IntentDraft.blank` has.
    public func draft(named name: String, provenance: String) -> IntentDraft? {
        guard let first = keys.first else { return nil }
        var draft = IntentDraft(name: name, keys: keys, provenance: provenance)
        if keys.count == 1 {
            draft.keys.append(IntentDraft.Key(time: Self.keySpacing * 5, pose: first.pose))
        }
        return draft
    }

    /// The provenance a mimicked draft carries, naming the source.
    public static func provenance(_ source: MimicSource) -> String {
        "Mimicked from \(source.provenanceWord)"
    }

    /// The name a kept track gets, numbered after the motions already held.
    public static func name(_ source: MimicSource, ordinal: Int) -> String {
        "\(source.namePrefix) \(ordinal)"
    }

    /// The record button's second line while recording.
    public static func recordingSaid(seconds: TimeInterval, keys: Int) -> String {
        String(format: "%.1f s · %d keyframes", seconds, keys)
    }

    /// Why the recording stopped on its own.
    public static let stoppedAtTheCap =
        String(format: "Stopped at %.0f seconds, which is as long as a motion can be and still "
                     + "run as one batch on a bench. Keep it, or record again.", maxSeconds)
}
