import Foundation

/// What this app has actually proved to the thing on the other end of a link.
///
/// TWO CASES, AND THE MISSING THIRD ONE IS THE ENTIRE TYPE. The case somebody
/// looks for first is `authenticated`, and it is not here, because nothing in
/// this app has ever authenticated a caller to a robot. `DuckLink` completes
/// Bluetooth pairing and reads an API version; `BenchPeer` posts to a bench
/// whose bearer token, when there is one, says the caller may use A BENCH and
/// says nothing at all about a duck; the WebRTC and bridge transports do not
/// exist, and `DuckWebRTC.twoThingsStillOpen` lists whose job it would be
/// to say how they authenticate — a list, not an implementation. An
/// `authenticated` case sitting here unfilled is an invitation: the first screen
/// that needed a green tick would set it, and a green tick that means "somebody
/// wrote `.authenticated` in a constructor" is worse than no tick, because it is
/// the tick a person uses to decide whether the duck they are about to drive is
/// theirs.
///
/// SO THIS IS A CLAIM ABOUT THE LINK AND NOT ABOUT THE PERSON. Neither case says
/// anybody is trusted. One says a human being completed a bond with a physical
/// object while standing next to it; the other says nothing on the far end asked
/// who is calling. Those are the only two states any transport in this app can
/// be in today, and when a third arrives it arrives with the code that earns it.
public enum DuckAuthority: String, CaseIterable, Equatable, Sendable {

    /// Bluetooth: somebody paired with a duck they were standing next to.
    ///
    /// THIS IS THE STRONGEST THING THIS APP HAS, AND IT IS PHYSICAL RATHER THAN
    /// CRYPTOGRAPHIC. `btd` answers the pairing PIN and the updater over BLE
    /// precisely because BLE is the recovery path — `DuckMethod`'s own note:
    /// "Both are answered on Bluetooth, where the caller has already bonded and
    /// is standing next to the duck." Range is the credential. It is a real one
    /// for the job it does, and it is not an identity: the bond says a phone was
    /// in the room, not which phone or whose.
    case bondedInPerson

    /// Everything else: the far end has not asked who is calling.
    ///
    /// A BENCH TOKEN IS NOT AN EXCEPTION, IT IS THE EXAMPLE. `BenchEndpoint`
    /// carries whether a bench wants a bearer token, and a bench that checks one
    /// is checking that the caller may run physics on that machine. Nothing in
    /// that exchange is a duck agreeing to be driven, and treating it as one is
    /// how an app ends up telling somebody a robot is theirs because a
    /// simulator's token matched.
    case nothingHasBeenProved

    /// Which of the two a transport is, exhaustively.
    ///
    /// NO `default`, for `DuckMethod.reach(for:)`'s stated reason. A transport
    /// added to `DuckTransportKind` stops this file compiling until somebody
    /// says what it proves, and the honest answer for a link nobody has written
    /// is `nothingHasBeenProved` — which is a sentence somebody typed rather
    /// than a default that answered on their behalf.
    public static func of(_ transport: DuckTransportKind) -> DuckAuthority {
        switch transport {
        case .ble: return .bondedInPerson
        case .webRTC, .bridge, .bench: return .nothingHasBeenProved
        }
    }

    /// Whether a link with this authority may be offered the calls that own
    /// somebody's way back into their robot.
    ///
    /// THE RECOVERY PATH IS THE ONLY THING THIS ENUM GATES, AND THAT IS ENOUGH.
    /// `DuckMethod.mutatesTheRecoveryPath` names the three — the pairing PIN in
    /// both directions and the `update.` family — and the argument for keeping
    /// them off a network link is written there: "a relayed twist costs a duck
    /// walking into a chair, while a relayed system.setPairingPin costs the
    /// owner their only way back in."
    ///
    /// IT IS A SECOND LOCK ON A DOOR THE ROUTING TABLE ALREADY LOCKS, and it is
    /// not decoration. `DeviceCard.Control.of` takes `reach` as a PARAMETER —
    /// deliberately, so a peer that narrowed its reach is answered on what it
    /// actually carries — which means a caller can hand it a reach set naming a
    /// recovery-path method on a link that has proved nothing. The routing table
    /// cannot see that; this can. The test that pins it does exactly that, so
    /// the check is one that can be watched failing rather than one taken on
    /// trust.
    public func mayReach(_ method: DuckMethod) -> Bool {
        guard method.mutatesTheRecoveryPath else { return true }
        return self == .bondedInPerson
    }

    /// What this link has established, for the line under a control that is not
    /// being drawn.
    public var says: String {
        switch self {
        case .bondedInPerson:
            return "Paired over Bluetooth. The credential is that somebody completed a bond with "
                 + "a duck they were standing next to, which is what the pairing PIN and the "
                 + "updater are answered on Bluetooth for. It says a phone was in the room, not "
                 + "whose phone it was."
        case .nothingHasBeenProved:
            return "Nothing on the other end of this link has asked who is calling. Whatever got "
                 + "you to the address is what you have — a bench token, if there is one, says "
                 + "you may run physics on that machine and says nothing about a duck. So the "
                 + "calls that rewrite a pairing PIN or start a firmware write are not offered "
                 + "here: they are the way back into a robot, and this link cannot tell you from "
                 + "anybody else who can reach it."
        }
    }

    /// Why there is no third case, as a sentence a screen can print beside a
    /// link's name.
    public static let noLinkHereHasAuthenticated =
        "No link in this app authenticates a caller to a duck. Bluetooth pairs — a bond made in "
      + "person, which is a real credential and not an identity — and the bench's bearer token, "
      + "where there is one, authorises the use of a simulator rather than a robot. WebRTC and "
      + "the bridge would both need one and neither exists: how a phone proves who it is to "
      + "mediad is the second of the five things this app does not know about that transport. "
      + "There is deliberately no \"authenticated\" state to set, because the first screen that "
      + "wanted a tick would set it."
}
