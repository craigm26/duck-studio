import Foundation
import Combine
import StudioKit
import DuckKit

/// The one open link to a real robot, held for as long as the app runs.
///
/// WHY IT IS NOT A `@State` ON THE SCREEN THAT OPENS IT. It was: `RobotBridgeView`
/// owned a `BridgeClient` in a `@State` and closed it in `onDisappear`, which is
/// correct for a screen whose only job is to put one file on a disk and leave.
/// It is wrong the moment a second screen drives the same robot: connecting on
/// the Robot tab and then walking to Control would have destroyed the
/// connection on the way, and the Control tab would have had to dial its own —
/// two sockets to one `robotd`, whose command slot is last-writer-wins, which
/// `intents.rs` says produces "a robot that obeys neither".
///
/// SO THERE IS EXACTLY ONE, OWNED WHERE THE APP IS. A link to a robot is a
/// thing that exists in the world — a socket, a duck standing on a floor — and
/// it should outlive every screen that can see it, exactly as `EvalRunner` does
/// and for the same reason: leaving a screen should be leaving a screen.
///
/// IT NEVER DIALS ANYTHING BY ITSELF. Nothing here reconnects, retries, or
/// remembers an address to try at launch. A robot that starts walking because
/// an app came back from the background is the failure this whole family of
/// code is written to avoid, and the only way to be sure of it is for every
/// connection to begin with somebody pressing Connect.
@MainActor final class BridgeLink: ObservableObject {

    /// The connection, or nil. `private(set)` because the two doors in and out
    /// are `connect` and `disconnect`, and a screen that could assign this
    /// could drop a live socket without closing it.
    @Published private(set) var client: BridgeClient?

    /// What the bridge said about itself when it accepted the relay: its
    /// version, its deadman, and whether it can install a policy.
    @Published private(set) var greeting: BridgeHandshake.Greeting?

    /// Where this is pointed, for a screen that wants to name the robot it is
    /// about to drive.
    @Published private(set) var host = ""

    /// What `robot.subscribe` answered — which networks this robot is running.
    /// Nil until it has been asked, which is a different thing from a robot
    /// that answered nothing. See `DuckSubscription.notAskedYet`.
    @Published private(set) var subscription: DuckSubscription?

    /// The newest `robot.state` this link has heard, or nil if none has
    /// arrived.
    ///
    /// THE NEWEST AND NOT A HISTORY. `DuckState` carries `receivedAt`, so
    /// anything that wants to know whether this is stale asks the value rather
    /// than a timer running beside a label — and a screen showing a
    /// three-second-old "walking" is describing a robot that may have been on
    /// its side for two and a half of them.
    @Published private(set) var lastState: DuckState?

    /// How many states have arrived. FOR A READOUT AND FOR A DIAGNOSIS, not for
    /// a decision: a subscription that was accepted and has published nothing
    /// is a specific, findable fault, and it is invisible if the only evidence
    /// is a label that stayed empty.
    @Published private(set) var statesHeard = 0

    private var pump: Task<Void, Never>?

    var isConnected: Bool { client != nil }

    /// The peer, as the vocabulary rather than as a socket. THE TYPE THE DRIVE
    /// LOOP TAKES: `any DuckPeer`, so nothing on the Control tab has to know
    /// this is a bridge rather than a bench.
    var peer: (any DuckPeer)? { client?.peer }

    /// How fast this app must send twists to keep this particular robot's
    /// deadmen fed. Derived from what the bridge reported, never assumed.
    var interval: TimeInterval {
        BridgeDrive.interval(bridgeDeadmanMilliseconds: greeting?.deadmanMilliseconds)
    }

    /// The three-timer sentence, with this bridge's own number in it.
    var deadmanSaid: String {
        BridgeDrive.deadmanChainSaid(bridgeDeadmanMilliseconds: greeting?.deadmanMilliseconds)
    }

    // MARK: - opening and closing

    /// Open a link, and start listening to whatever the robot says.
    ///
    /// THE ORDER IS THE ONE `DuckPeer.states()` INSISTS ON: take the stream,
    /// then start the thing that fills it. `states()` is deliberately not
    /// `async` so that is a sequence rather than a race — a subscribe sent
    /// before anybody was reading would put the first states nowhere.
    func connect(host: String, port: Int, token: String) async throws {
        disconnect()
        let made = try await BridgeClient.connect(host: host, port: port,
                                                  token: token, named: host)
        client = made
        greeting = made.greeting
        self.host = host
        listen(to: made.peer)
    }

    /// Ask the robot to start pushing its state, and record what it is running.
    ///
    /// SEPARATE FROM `connect` ON PURPOSE. Connecting is a thing a person did;
    /// subscribing is a thing a screen wants. The install screen has no use for
    /// a 10 Hz stream and should not turn one on, and the drive screen needs it
    /// before the first twist — so the screen that wants it asks for it, once,
    /// and a second ask is harmless because `robot.subscribe` is idempotent per
    /// connection.
    @discardableResult
    func subscribeToState() async throws -> DuckSubscription {
        guard let peer = client?.peer else { throw LinkGone.notConnected }
        let reply = try await peer.call(.subscribe(hz: DuckSubscription.watchingRateHz))
        if let refusal = reply.failure {
            throw LinkGone.refused(refusal.says)
        }
        let read = try DuckSubscription.read(reply)
        subscription = read
        return read
    }

    /// Close it, and say so. EVERY PARKED CALLER IS RESUMED by `LinePeer.close`
    /// rather than left waiting on an answer that is not coming.
    func disconnect() {
        pump?.cancel()
        pump = nil
        client?.close()
        client = nil
        greeting = nil
        subscription = nil
        lastState = nil
        statesHeard = 0
        host = ""
    }

    /// What can go wrong before a byte moves.
    enum LinkGone: Error, Equatable {
        case notConnected
        case refused(String)

        var message: String {
            switch self {
            case .notConnected:
                return BridgeDrive.connectFirst
            case .refused(let why):
                return why
            }
        }
    }

    // MARK: - listening

    private func listen(to peer: LinePeer) {
        let stream = peer.states()
        pump = Task { [weak self] in
            for await state in stream {
                guard let self else { return }
                self.lastState = state
                self.statesHeard += 1
            }
            // THE STREAM ENDING IS THE LINK ENDING, and it is said rather than
            // gone quiet: a `for await` that simply stops producing looks
            // exactly like a duck standing still.
            guard let self, self.client != nil else { return }
            self.disconnect()
        }
    }
}
