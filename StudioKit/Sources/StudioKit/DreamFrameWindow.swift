import Foundation

/// The pictures Dream-1 is sent: one kept every 0.2 s by the camera's own clock, the last 9, oldest first.
///
/// DREAM LABS' RULE, PORTED, NOT INVENTED (dreamlabs-client 1.0.14, `dream/_window.py`). The model
/// was trained on frames 0.2 s apart, so a camera that delivers faster has ticks dropped, by
/// timestamp, never by count:
/// - the first tick of a run is kept, and the next is due one period after it;
/// - a later tick is kept once it is within a slack of its due time. The slack is half the median
///   gap between the last 8 distinct timestamps, at most half a period;
/// - the next due time is anchored on the schedule, so jitter never drifts it. A tick kept half a
///   period or more late (the camera stalled) restarts the schedule from itself.
///
/// FEWER THAN 9 AT THE START, AS THE REFERENCE CLIENT SENDS. Its `build_observation` sends the
/// frames kept so far, never padded.
///
/// A camera slower than 5 fps (the duck's mediad `/frame` runs at about 4) has every tick kept.
public struct DreamFrameWindow: Sendable {
    public static let size = DreamPilot.window
    public static let period: TimeInterval = 0.2
    static let slackTicks = 8

    public private(set) var frames: [String] = []
    private var recent: [TimeInterval] = []
    private var due: TimeInterval?

    public init() {}

    /// Takes one camera tick; whether its frame was kept. A timestamp earlier than the last is dropped.
    @discardableResult
    public mutating func add(_ frame: String, at time: TimeInterval) -> Bool {
        guard !frame.isEmpty, time.isFinite else { return false }
        if let last = recent.last {
            if time < last { return false }
            if time > last { recent.append(time) }
        } else {
            recent.append(time)
        }
        if recent.count > Self.slackTicks { recent.removeFirst(recent.count - Self.slackTicks) }
        let gaps = zip(recent, recent.dropFirst()).map { $1 - $0 }
        let slack = gaps.isEmpty ? 0 : min(Self.median(gaps) / 2, Self.period / 2)
        if let due, time < due - slack { return false }
        let anchor = due.flatMap { time < $0 + Self.period / 2 ? $0 : nil } ?? time
        due = anchor + Self.period
        frames.append(frame)
        if frames.count > Self.size { frames.removeFirst(frames.count - Self.size) }
        return true
    }

    public mutating func clear() { self = DreamFrameWindow() }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }
}
