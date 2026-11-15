import XCTest
import DuckKit
@testable import StudioKit

// Fakes shared by the build 91 controller tests (PilotGateTests, BrainRunnerTests).

final class ControllerClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = Date(timeIntervalSince1970: 1_000)
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return t }
    func advance(_ s: TimeInterval) { lock.lock(); t += s; lock.unlock() }
}

/// A robotd stand-in that records every call and answers yes.
final class ControllerDuck: DuckPeer, @unchecked Sendable {
    let identity: DuckIdentity
    let transportKind: DuckTransportKind = .bridge
    let reach = DuckMethod.reach(for: .bridge)
    private let lock = NSLock()
    private var _sent: [DuckCall] = []
    var sent: [DuckCall] { lock.lock(); defer { lock.unlock() }; return _sent }
    init(kind: DuckIdentity.Kind = .sim) { identity = DuckIdentity(name: "Pip", kind: kind) }

    var moving: [DuckDrive.Twist] {
        sent.compactMap { if case .move(let t) = $0, t != .still { return t } else { return nil } }
    }
    var moves: Int { sent.filter { if case .move = $0 { return true } else { return false } }.count }
    var stops: Int { sent.filter { $0 == .stop }.count }
    func index(of c: DuckCall) -> Int? { sent.firstIndex(of: c) }

    private func record(_ c: DuckCall) { lock.lock(); _sent.append(c); lock.unlock() }

    func call(_ c: DuckCall) async throws -> DuckReply {
        try vet(c, asNotification: false)
        record(c)
        let body: String
        if case .skills = c { body = #"{"skills":[{"name":"kick_left","duration":0.5}],"built_in":["sit_toggle"]}"# }
        else { body = #"{"accepted":true}"# }
        return DuckReply(id: 1, result: Data(body.utf8), failure: nil)
    }

    func notify(_ c: DuckCall) async throws {
        try vet(c, asNotification: true)
        record(c)
    }

    nonisolated func states() -> AsyncStream<DuckState> { AsyncStream { $0.finish() } }
}
