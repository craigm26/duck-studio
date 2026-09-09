import Foundation
import Network
import StudioKit

/// A TCP line to a Microduck bridge, handed to `LinePeer` as its wire.
///
/// I/O ONLY. The greeting is `BridgeHandshake`'s, the vocabulary is
/// `DuckCall`'s, the framing and correlation are `LinePeer`'s; this opens an
/// `NWConnection`, writes the bridge's hello, reads the one greeting line
/// back, and then moves bytes both ways until somebody closes it. Nothing
/// here parses a robot's answer.
///
/// THE BRIDGE'S HELLO GOES FIRST AND IS NOT THE ROBOT'S. `LinePeer.call(.hello)`
/// is robotd's `hello`; the bridge wants its own token line before it relays
/// anything, and answers it with a greeting that names the bridge, the
/// deadman and whether `policy.install` is on. So this reads that greeting
/// itself, before the peer sees a byte.
final class BridgeClient: @unchecked Sendable {
    let connection: NWConnection
    let greeting: BridgeHandshake.Greeting
    let peer: LinePeer
    private var reading: Task<Void, Never>?
    private let feed: AsyncStream<Data>.Continuation

    private init(connection: NWConnection, greeting: BridgeHandshake.Greeting,
                 identity: DuckIdentity, feed: AsyncStream<Data>.Continuation,
                 inbound: AsyncStream<Data>) {
        self.connection = connection
        self.greeting = greeting
        self.feed = feed
        // THE REACH IS NARROWED, AND `studio.state` IS WHY.
        //
        // `DuckMethod.reach(for: .bridge)` is written for the bridge the
        // routing table imagined — "another copy of this app relaying to a duck
        // it can reach" — and that peer would answer `studio.state`, because it
        // is a copy of this app. THIS bridge is not that: it relays to a real
        // `robotd`, byte for byte, and `robotd` answers no method that asks
        // what it is doing. Leaving `state` in reach would put a control on the
        // Control tab's link panel reading "carried" for a call that comes back
        // as a refusal by name — and a refusal by name is indistinguishable
        // from a robot that does not have the feature.
        //
        // `DuckPeer` permits exactly this and forbids the opposite: a peer may
        // narrow what it carries when it knows this particular duck answers
        // less, and `LinePeer` intersects rather than trusting the argument, so
        // nothing here can widen the table.
        peer = LinePeer(identity: identity, over: .bridge, inbound: inbound,
                        reach: DuckMethod.reach(for: .bridge).subtracting([.state])) { stamped in
            try await BridgeClient.send(stamped.line, over: connection)
        }
    }

    /// Open, greet, and hand back a client whose peer is reading.
    static func connect(host: String, port: Int, token: String,
                        named name: String) async throws -> BridgeClient {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host),
                                           port: NWEndpoint.Port(integerLiteral: UInt16(clamping: port)))
        let connection = NWConnection(to: endpoint, using: .tcp)
        try await ready(connection)
        try await send(BridgeHandshake.hello(token: token), over: connection)
        let (line, remainder) = try await firstLine(over: connection)
        let greeting = try BridgeHandshake.read(line)
        var continuation: AsyncStream<Data>.Continuation!
        let inbound = AsyncStream<Data> { continuation = $0 }
        let client = BridgeClient(connection: connection, greeting: greeting,
                                  identity: DuckIdentity(name: name, kind: .real),
                                  feed: continuation, inbound: inbound)
        if !remainder.isEmpty { continuation.yield(remainder) }
        client.reading = Task { [weak client] in
            guard let client else { return }
            await client.peer.read()
        }
        client.pump()
        return client
    }

    func close() {
        reading?.cancel()
        feed.finish()
        connection.cancel()
        Task { await peer.close() }
    }

    // MARK: - the wire

    private func pump() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self else { return }
            if let data, !data.isEmpty { self.feed.yield(data) }
            if done || error != nil { self.feed.finish(); return }
            self.pump()
        }
    }

    private static func ready(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            connection.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true; continuation.resume()
                case .failed(let error):
                    resumed = true; continuation.resume(throwing: error)
                case .cancelled:
                    resumed = true
                    continuation.resume(throwing: NWError.posix(.ECANCELED))
                default: break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    private static func send(_ data: Data, over connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    /// The greeting, byte by byte until its newline, and whatever came after
    /// it in the same read — which belongs to the peer.
    private static func firstLine(over connection: NWConnection) async throws -> (Data, Data) {
        var buffer = Data()
        while buffer.count < 4096 {
            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, done, error in
                    if let error { continuation.resume(throwing: error); return }
                    if let data, !data.isEmpty { continuation.resume(returning: data); return }
                    continuation.resume(throwing: NWError.posix(done ? .ECONNRESET : .EAGAIN))
                }
            }
            buffer.append(chunk)
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                let rest = buffer[buffer.index(after: newline)...]
                return (Data(line), Data(rest))
            }
        }
        throw BridgeHandshake.Refusal.notJSON
    }
}
