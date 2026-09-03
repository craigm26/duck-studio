import Foundation

/// The signalling protocol a Microduck's `mediad` speaks, transcribed from the
/// client the robot itself serves.
///
/// WHERE THIS CAME FROM, AND WHY THAT MATTERS. `DuckWebRTC` used to be a list
/// of what nobody here knew, and a test failed if anything conformed to it,
/// because a client written against a guessed contract is worse than none.
/// The contract is not guessed any more: `pollen-robotics/microduck` is public,
/// `docs/design/remote-webrtc.md` says `mediad` runs the signalling server in
/// its own process on port 8443, and `mediad/webclient/index.html` is a
/// reference client that speaks the protocol BY HAND — no library between it
/// and the wire — so every message below is transcribed from a working
/// implementation rather than from a summary of one. That page's own comment
/// says which shapes matter: "Getting these wrong is the thing that costs an
/// afternoon."
///
/// WHAT IS HERE AND WHAT IS NOT. These are the messages and their shapes,
/// which is the part that can be tested on a machine with no WebRTC stack at
/// all — this file has no dependency on one and never will. Opening a peer
/// connection, answering an offer and holding a data channel belong to
/// whatever the app links against; what they must SAY is here.
public enum DuckSignalling {

    /// The port `mediad` binds. It binds on all interfaces deliberately: the
    /// design note says loopback would send every session through a relay and
    /// defeat a local mode.
    public static let port = 8443

    public static func url(host: String) -> URL? {
        URL(string: "ws://\(host):\(port)")
    }

    // MARK: - what the robot sends

    public enum Inbound: Equatable, Sendable {
        /// The server has assigned this client an id. The reference client
        /// answers it with `list` and nothing else.
        case welcome(peerId: String)
        /// Who is producing. `mediad` registers as a producer when its
        /// pipeline reaches PLAYING, so an EMPTY list is a pipeline that did
        /// not start rather than a robot without a camera — which is a
        /// different thing to tell somebody.
        case producers([Producer])
        case sessionStarted(sessionId: String, peerId: String)
        /// A session's SDP. The producer offers and the client answers: it
        /// knows what it is sending.
        case sdp(sessionId: String, type: String, sdp: String)
        case ice(sessionId: String, candidate: String, sdpMLineIndex: Int)
        case endSession(sessionId: String)
        /// Noise the reference client skips in its log, kept as a case so a
        /// reader is not surprised by it.
        case peerStatusChanged
        /// Something this app does not know. NOT AN ERROR: the server may
        /// learn messages after this was written, and a client that threw on
        /// one would break on an upgrade it did not need to care about.
        case unknown(type: String)
    }

    /// A producer, and the `meta` `mediad/src/producer.rs` fills in. The meta
    /// names the robot BEFORE a session exists, which is what lets a screen
    /// say which duck it found before any video arrives.
    public struct Producer: Equatable, Sendable {
        public let id: String
        public let name: String?
        public let release: String?
        public let apiVersion: String?

        public init(id: String, name: String? = nil,
                    release: String? = nil, apiVersion: String? = nil) {
            self.id = id; self.name = name
            self.release = release; self.apiVersion = apiVersion
        }
    }

    // MARK: - what this app sends

    /// `list` takes no fields. Sent as the answer to `welcome`.
    public static func list() -> Data { line(["type": "list"]) }

    public static func startSession(with producer: String) -> Data {
        line(["type": "startSession", "peerId": producer])
    }

    /// The answer to the producer's offer.
    public static func answer(sessionId: String, sdp: String) -> Data {
        line(["type": "peer", "sessionId": sessionId,
              "sdp": ["type": "answer", "sdp": sdp]])
    }

    /// A candidate of ours. `sdpMLineIndex` is required; the reference client
    /// sends both fields flattened under `ice` and nothing else.
    public static func candidate(sessionId: String, candidate: String,
                                 sdpMLineIndex: Int) -> Data {
        line(["type": "peer", "sessionId": sessionId,
              "ice": ["candidate": candidate, "sdpMLineIndex": sdpMLineIndex]])
    }

    // MARK: - reading

    public static func read(_ data: Data) -> Inbound {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = top["type"] as? String else { return .unknown(type: "") }
        switch type {
        case "welcome":
            return .welcome(peerId: top["peerId"] as? String ?? "")
        case "list":
            let rows = top["producers"] as? [[String: Any]] ?? []
            return .producers(rows.compactMap { row in
                guard let id = row["id"] as? String else { return nil }
                let meta = row["meta"] as? [String: Any] ?? [:]
                return Producer(id: id,
                                name: meta["name"] as? String,
                                release: meta["release"] as? String,
                                apiVersion: meta["api_version"].map { "\($0)" })
            })
        case "sessionStarted":
            return .sessionStarted(sessionId: top["sessionId"] as? String ?? "",
                                   peerId: top["peerId"] as? String ?? "")
        case "peer":
            // ONE MESSAGE TYPE, TWO PAYLOADS, FLATTENED BESIDE THE SESSION ID.
            // This is the shape the reference client warns about.
            let session = top["sessionId"] as? String ?? ""
            if let sdp = top["sdp"] as? [String: Any] {
                return .sdp(sessionId: session,
                            type: sdp["type"] as? String ?? "",
                            sdp: sdp["sdp"] as? String ?? "")
            }
            if let ice = top["ice"] as? [String: Any] {
                return .ice(sessionId: session,
                            candidate: ice["candidate"] as? String ?? "",
                            sdpMLineIndex: ice["sdpMLineIndex"] as? Int ?? 0)
            }
            return .unknown(type: "peer")
        case "endSession":
            return .endSession(sessionId: top["sessionId"] as? String ?? "")
        case "peerStatusChanged":
            return .peerStatusChanged
        default:
            return .unknown(type: type)
        }
    }

    // MARK: - the control channel

    /// The data channel the robot API arrives on: reliable and ordered, and
    /// the one this app cares about. `teleop` is the other one and carries
    /// input and high-rate telemetry unreliably.
    public static let controlChannel = "control"
    public static let teleopChannel = "teleop"

    /// TWO RULES A CLIENT MUST OBEY ON THAT CHANNEL, both from the design
    /// note's §5, and both easy to break by writing the obvious thing.
    ///
    /// Replies are NOT correlated to requests: a subscription is a stream of
    /// notifications on an open connection, and every one has to reach the
    /// client, so a reader that pairs answers to ids by construction drops
    /// them. And one channel is one ordered lane — every daemon serves one
    /// request at a time per connection — so a second call sent before the
    /// first is answered hangs, which is a recorded bug and not a theory.
    public static let repliesAreNotCorrelated =
        "The robot answers on a stream rather than in pairs: a subscription sends notifications "
      + "for as long as it is open, and none of them is a reply to anything. A reader that "
      + "matches answers to questions drops them."

    public static let oneLaneOneRequest =
        "One channel is one lane and the robot serves one request at a time on it. A second call "
      + "sent before the first is answered waits behind it, which is why this app sends one and "
      + "waits."

    public static let everySentence: [String] = [repliesAreNotCorrelated, oneLaneOneRequest]

    private static func line(_ body: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }
}
