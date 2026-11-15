import Foundation
import DuckKit

/// Whether a pilot or a runner may still write motion. `StopPath` is the one the app uses: shut
/// by every Stop, opened only by `StopPath.rearm()`, which only a person's own action calls.
public protocol MotionLatch: AnyObject, Sendable {
    var admits: Bool { get }
}

extension StopPath: MotionLatch {}

/// A duck as a pilot or a runner sees it: after a Stop, nothing that moves it gets through until a
/// person re-arms (docs/plans/brains-layer.md 6.1, step 2).
///
/// WHY A WRAPPER AND NOT A CHANGE TO `LinePeer`. The latch is for pilots and runners: "After
/// `.stop`, `ControlArbiter` and `LinePeer` refuse `.move` from any pilot or runner until an
/// explicit re-arm by a person in Studio." The person's own sticks are not a runner, and the app
/// does not re-arm on a stick touch while nothing runs, so a latch inside `LinePeer` would leave
/// the sticks dead after every Stop. Every runner in the kit that moves a duck for a model
/// (`BrainRunner`, and the drive and plan legs it calls) is handed this wrapper instead of the
/// connection itself, and the Stop path does not change.
///
/// WHAT IS REFUSED WHILE THE LATCH IS SHUT. Every `robot.move`, still or not, and everything
/// else that can start the duck moving or make it do something: head, look, a skill, enable,
/// init, relax, a sound, a Dream ask. `robot.stop` always goes through, and so do the calls that
/// only read (hello, state, subscribe, skills, policies) and the Dream calls that end or check a
/// session.
///
/// THE REFUSAL IS THROWN, NOT SWALLOWED. A runner that tried to move after a Stop learns it at
/// once, and nothing reaches the wire.
public final class LatchedPeer: DuckPeer, @unchecked Sendable {

    public let inner: any DuckPeer
    public let latch: any MotionLatch

    public init(_ inner: any DuckPeer, latch: any MotionLatch) {
        self.inner = inner
        self.latch = latch
    }

    /// Why a call did not go out.
    public enum Refused: Error, Equatable, Sendable {
        /// The latch is shut: a Stop happened and no person has re-armed since.
        case latched(DuckMethod)

        public var message: String { LatchWords.refused }
    }

    public var transportKind: DuckTransportKind { inner.transportKind }
    public var identity: DuckIdentity { inner.identity }
    public var reach: Set<DuckMethod> { inner.reach }

    /// Whether this call may go out while the latch is shut.
    public static func passesWhileLatched(_ c: DuckCall) -> Bool {
        switch c {
        case .stop, .hello, .state, .subscribe, .skills, .policies:
            return true
        case .dream(let d):
            return d.verb == .end || d.verb == .status || d.verb == .keyCheck || d.verb == .keyClear
        case .move, .head, .look, .enable, .initPose, .relax, .installPolicy, .doSkill, .sound:
            return false
        }
    }

    private func check(_ c: DuckCall) throws {
        if !latch.admits && !Self.passesWhileLatched(c) { throw Refused.latched(c.method) }
    }

    public func call(_ c: DuckCall) async throws -> DuckReply {
        try check(c)
        return try await inner.call(c)
    }

    public func notify(_ c: DuckCall) async throws {
        try check(c)
        try await inner.notify(c)
    }

    public func states() -> AsyncStream<DuckState> { inner.states() }

    public func lastCommand() async -> DuckDrive.Twist? { await inner.lastCommand() }
}

/// The latch's sentences.
public enum LatchWords {
    public static let refused = "Stopped. Nothing moves the duck until you start it again."
    public static let all = [refused]
}
