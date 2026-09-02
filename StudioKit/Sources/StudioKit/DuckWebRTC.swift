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
    public static let fiveThingsNobodyHereKnows =
        "Five things about this transport are unknown here, and each of them is a question with "
      + "an answer somebody can go and read.\n\n"
      + "1. WHERE THE OFFER LIVES. mediad is named as the thing that speaks WebRTC, and nothing "
      + "in this project has read how a client obtains its session description — whether an HTTP "
      + "endpoint on the robot serves one, whether the phone offers first, or whether a "
      + "rendezvous service sits between them.\n\n"
      + "2. HOW A PHONE PROVES WHO IT IS. There is no authentication step transcribed anywhere "
      + "in this app for this link. DuckAuthority has no authenticated case for exactly this "
      + "reason: nothing here has ever proved anything to a duck.\n\n"
      + "3. WHAT ICE HAS TO REACH. Whether the duck and the phone are expected to be on one LAN, "
      + "whether a STUN server is involved, and whether a TURN relay exists for the case where "
      + "they are not — three different products for the person holding the phone.\n\n"
      + "4. THE BRIDGE'S TOKEN. A studio-to-studio bridge relays this same vocabulary to a duck "
      + "the other phone can reach, and what authorises that relay is not designed. It is the "
      + "same question as (2) with a worse blast radius, because the peer is a program on "
      + "somebody else's phone.\n\n"
      + "5. THE DATACHANNEL'S LABEL AND SHAPE. Whether the JSON-RPC lines travel on a channel "
      + "with a known label, whether it is reliable and ordered — which decides outright whether "
      + "DuckLineSequence measures loss or measures nothing — and whether one channel carries "
      + "both directions."

    /// What a screen says where a Connect button would be.
    public static let whyThereIsNoClient =
        "No WebRTC yet. This is the transport Pollen's contract names for driving a robot, and "
      + "this app has the vocabulary for it and no client behind it — five specific things about "
      + "their signalling path have not been read, and a client written against a guess produces "
      + "calls a duck refuses by name, which looks exactly like a feature the duck does not have."
}

/// Agreeing on how to reach the far end. See `DuckWebRTC` for why nothing
/// implements this.
///
/// THE MEMBERS ARE THE SHAPE OF THE QUESTION, NOT A TRANSCRIPTION OF AN ANSWER.
/// Every one of them corresponds to one of `fiveThingsNobodyHereKnows`: where
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
