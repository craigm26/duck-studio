import Foundation

/// The shape of a WebRTC client, written down so that the five things nobody
/// here knows have somewhere to be listed.
///
/// NOTHING CONFORMS TO THIS AND A TEST ENFORCES THAT. `DuckWebRTC.Signalling`
/// has no implementation in this package, in the app target, or anywhere else,
/// and `DuckWebRTCTests` fails if one appears without this file's list being
/// answered first. That is the opposite of the usual reason to write a protocol:
/// it is here to hold a shape still while the unknowns underneath it are read
/// off a repository nobody in this project has opened, and a conformance written
/// against a guessed contract is the failure mode `DuckLink` already paid for
/// once — "a name copied from a web mirror produces a call the robot refuses by
/// name, and a refusal by name looks exactly like a feature the robot does not
/// have."
///
/// WHY IT IS WORTH WRITING BEFORE IT CAN BE FILLED IN. `duck-ipc-proto` names
/// WebRTC as where the continuous intents will travel, and `DuckMethod.reach(for:
/// .webRTC)` already gives that link the whole robot surface and none of the
/// recovery path. So every screen in this app is being written against a
/// transport that will exist, and the questions this file lists are the ones
/// that decide whether the answer is a week or a quarter. Listing them is
/// cheaper than discovering them one at a time with a duck on the desk.
///
/// THE HOUSE RULE THIS SATISFIES: a blocked surface ships as an explicit "not
/// yet", never as an inert control. `whyThereIsNoClient` is the sentence a
/// screen prints where a Connect button would go, and it names what is missing
/// rather than apologising.
public enum DuckWebRTC {

    /// The one thing a WebRTC client has to do before it can do anything: agree
    /// with the far end on how to reach it.
    ///
    /// A TYPEALIAS RATHER THAN A NESTED PROTOCOL. Nesting a protocol inside a
    /// type needs a compiler this package does not require — the manifest says
    /// tools 5.9 — and a build that fails on somebody's older Xcode is a worse
    /// outcome than a two-line indirection. `DuckWebRTC.Signalling` is the name
    /// to write; `DuckWebRTCSignalling` is where it lives.
    public typealias Signalling = DuckWebRTCSignalling

    /// The five things this app does not know about Pollen's WebRTC path, in
    /// the order somebody implementing it would hit them.
    ///
    /// EACH ONE IS A QUESTION WITH AN ADDRESS, NOT A SHRUG. They are answerable
    /// — by reading `mediad`, by reading whatever serves its offer, by watching
    /// one session — and writing them as five separate unknowns rather than as
    /// "WebRTC is not implemented" is what makes them assignable.
    /// FOUR OF THE FIVE ARE ANSWERED, AND THE ANSWERS ARE READ RATHER THAN
    /// GUESSED. `pollen-robotics/microduck` is public: `duck-ipc-proto` is a
    /// crate in it, `docs/design/remote-webrtc.md` documents the transport, and
    /// `mediad/webclient/index.html` is a working client that speaks the
    /// signalling protocol by hand. `DuckSignalling` is the transcription.
    ///
    /// This list is kept, shortened, because the shape of it was the useful
    /// part: a question with an address is assignable and "not implemented" is
    /// not. What remains is genuinely open, and one of the two is open in
    /// Pollen's own document rather than only in ours.
    public static let whatIsKnownNow =
        "The signalling path is no longer a guess. mediad runs the signalling server in its own "
      + "process on port 8443, bound on every interface; a client asks who is producing, starts a "
      + "session with the producer, and ANSWERS the offer the robot makes; SDP and candidates "
      + "travel as one `peer` message with the payload flattened beside the session id; and the "
      + "robot API arrives on a reliable, ordered datachannel called `control` carrying the same "
      + "JSON-RPC one object per line that the Unix socket carries. There is no authentication "
      + "step because the first version of that transport has no gate, which their own design "
      + "note states and defends."

    public static let twoThingsStillOpen =
        "Two things are still open. Reaching a duck that is NOT on this network needs a "
      + "signalling path over the internet, a STUN server and a TURN relay — Pollen's own note "
      + "carries that as an open question rather than a design, so it is not ours to guess at "
      + "either. And a studio-to-studio bridge — this app relaying to a duck another phone can "
      + "reach — still has nothing that authorises the relay, which is the same question with a "
      + "worse blast radius, because the peer is a program on somebody else's phone."

    /// What a screen says where a Connect button would be.
    public static let whyThereIsNoClient =
        "No WebRTC client here yet, and what is missing is now a peer connection rather than a "
      + "contract. The signalling and the control channel are transcribed from the client the "
      + "robot itself serves, and the messages are tested; what this app does not yet link "
      + "against is something that can hold a peer connection and answer an offer. Until it "
      + "does, the robot's own console is the camera and the bridge is the controls."
}

/// Agreeing on how to reach the far end. See `DuckWebRTC` for why nothing
/// implements this.
///
/// THE MEMBERS ARE THE SHAPE OF THE QUESTION, NOT A TRANSCRIPTION OF AN ANSWER.
/// Every one of them corresponds to something in `whatIsKnownNow`: where
/// the offer comes from, what authorises the exchange, what candidates have to
/// be traded, and what the resulting channel is called. Whoever fills this in
/// will change these signatures, and that is expected — what must not happen is
/// a conformance that keeps the signatures and guesses the semantics.
///
/// `Sendable` AND `AnyObject` FOR `DuckPeer`'S REASON: a signalling client owns
/// a connection, so it is a reference and it crosses tasks.
public protocol DuckWebRTCSignalling: AnyObject, Sendable {

    /// Where this client believes the far end's offer comes from, in words a
    /// person can check against a packet capture. NOT a URL: whether it is even
    /// an HTTP fetch is unknown 1.
    var offerCameFrom: String { get }

    /// Trade session descriptions with the far end and come back with the
    /// answer, as SDP. Unknowns 1 and 2 both live inside this call.
    func exchange(offer: String) async throws -> String

    /// Hand over one ICE candidate. Unknown 3 is what these have to reach.
    func add(candidate: String) async throws

    /// The label of the datachannel the JSON-RPC lines travel on, and whether
    /// it is ordered — unknown 5, and the one that decides what
    /// `DuckLineSequence` can claim.
    var channel: (label: String, ordered: Bool) { get }
}
