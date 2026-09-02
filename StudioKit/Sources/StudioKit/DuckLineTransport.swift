import Foundation

/// The links that carry a JSON-RPC LINE, as opposed to the one that does not.
///
/// WHY A SECOND TRANSPORT ENUM EXISTS AND WHY IT IS NOT A DUPLICATE OF
/// `SimDuck.LineTransport`. Those two enums answer different questions and only
/// look alike. `SimDuck.LineTransport` asks "may a SIMULATION sit on the far end
/// of this link", and its answer excludes Bluetooth for a reason that is about
/// ducks rather than about bytes — BLE's reach is `hello` plus the pairing PIN
/// and the updater, which are the way back into a robot somebody is standing
/// next to, and a simulation has nothing to be locked out of. This enum asks the
/// narrower question a TRANSPORT has to answer: does one NDJSON line, framed by
/// the newline `framing.rs` names, go down this link at all. Bluetooth answers
/// yes — `DuckLink` already writes exactly those lines over a characteristic —
/// so it is a case here and is not a case there, and the two enums disagree
/// about BLE on purpose.
///
/// THE BENCH IS EXCLUDED FROM BOTH, AND IT IS THE SAME EXCLUSION FOR THE SAME
/// REASON, so this file states it in the same words rather than in new ones:
/// `benchIsNotALine` below IS `SimDuck.LineTransport.benchIsNotALine`, by
/// reference, not by transcription. Two spellings of that paragraph would be two
/// paragraphs to edit apart, and the failure it describes — a JSON-RPC line
/// posted at `/intent` parses as a body with no velocities in it, a zero twist,
/// a duck standing perfectly still while the app reports it walking — is the
/// worst thing this package can produce. One copy, in the file that discovered
/// it.
///
/// WHAT IT IS FOR: `LinePeer` takes one of these. That peer speaks lines and
/// nothing else, so the type of its transport parameter is the enforcement —
/// there is no bench case to hand it, exactly as `SimDuck`'s parameter has none,
/// and for the same reason argued there: the call site that is wrong is the one
/// being written, not the one being run.
public enum DuckLineTransport: String, CaseIterable, Sendable {

    /// Bluetooth Low Energy. `DuckLink` writes these lines over a GATT
    /// characteristic today — it is the only transport in this app that has any
    /// code behind it at all — and what it carries is a deliberate subset:
    /// `hello`, the pairing PIN, the updater. A line goes down it; a 50 Hz
    /// stream of twists does not, which is `DuckMethod.reach(for: .ble)`'s job
    /// to say and not this enum's.
    case ble

    /// Where `duck-ipc-proto` says the continuous intents will travel. No
    /// app-side implementation exists — see `DuckWebRTC`, which is a list of
    /// what nobody here knows rather than a client.
    case webRTC

    /// Another copy of this app, relaying to a duck it can reach and this one
    /// cannot.
    case bridge

    /// Which link this is, for `reach` and for `vet`.
    ///
    /// TOTAL BY CONSTRUCTION rather than by a lookup that could go missing: a
    /// case added here has to be given a `DuckTransportKind` or this switch
    /// stops compiling.
    public var kind: DuckTransportKind {
        switch self {
        case .ble: return .ble
        case .webRTC: return .webRTC
        case .bridge: return .bridge
        }
    }

    /// The same question asked of every transport, answered for every one.
    ///
    /// EXHAUSTIVE OVER `DuckTransportKind` WITH NO `default`, copying
    /// `DuckMethod.reach(for:)`'s discipline and `SimDuck.LineTransport`'s: a
    /// transport added to that enum stops this file compiling until somebody
    /// says whether a line goes down it. A `default: return nil` would answer
    /// "not a line" for every future transport silently, and the symptom would
    /// be a peer nobody could construct for a link that would have worked.
    public init?(_ kind: DuckTransportKind) {
        switch kind {
        case .ble: self = .ble
        case .webRTC: self = .webRTC
        case .bridge: self = .bridge
        case .bench: return nil
        }
    }

    /// Why a transport is not one of these, or nil for the three that are.
    public static func whyNot(_ kind: DuckTransportKind) -> String? {
        switch kind {
        case .ble, .webRTC, .bridge: return nil
        case .bench: return benchIsNotALine
        }
    }

    /// The bench speaks a different wire — `SimDuck.LineTransport`'s sentence,
    /// verbatim and by reference.
    ///
    /// NOT COPIED. A `static let` initialised from the other constant is the
    /// only form of "verbatim" a compiler enforces; a pasted string is verbatim
    /// on the day it is pasted. The test that pins them asserts identity rather
    /// than content, so it cannot pass while the two have drifted.
    public static let benchIsNotALine = SimDuck.LineTransport.benchIsNotALine
}
