import Foundation
import DuckKit
import DuckEvidence

/// Where to send a policy or a motion, and what to say about it.
///
/// WHAT THIS DOES NOT DO: post anything. iOS hands a file to whichever app the
/// person picks in the share sheet, and that app posts it if they press send.
/// Nothing here has an account, a token, or the ability to publish on somebody's
/// behalf, and a screen that implied otherwise would be describing a capability
/// this app has deliberately not taken. So a destination is two things: a link
/// that opens the right place, and a message worth pasting.
///
/// THE MESSAGE IS WHERE THE CARE GOES. Anyone can name a file
/// `alpha_walking.onnx`; the only claim a recipient can check without trusting
/// the sender is the parameter fingerprint. So the drafted message leads with
/// the digest and states the standing HONESTLY — a policy this app does not
/// recognise is described as unrecognised, never omitted and never softened,
/// because the person pasting it is about to ask strangers to run it.
public enum CommunityShare {

    public struct Destination: Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        /// What people actually do there, so somebody can pick the right one.
        public let purpose: String
        /// The address to open. Nothing is sent to it by this app.
        public let url: URL
        /// The system icon to draw.
        public let symbol: String
    }

    /// The Microduck channel on Pollen's Discord — where the robot's owners
    /// actually talk, and the place a shared `.onnx` or `.duckintent` is most
    /// likely to be useful to somebody.
    public static let discord = Destination(
        id: "discord",
        name: "Microduck on Discord",
        purpose: "Pollen's community channel. Attach the file to a message there.",
        url: URL(string: "https://discord.com/channels/519098054377340948/1542918066768183297")!,
        symbol: "bubble.left.and.bubble.right")

    /// Pollen's own repository. Not a place to post a file — an issue thread is
    /// the wrong shape for a binary — but the right place to raise something
    /// about a policy they released.
    public static let upstream = Destination(
        id: "github",
        name: "pollen-robotics/microduck",
        purpose: "Where the released policies live. Good for a question about one, not for posting a file.",
        url: URL(string: "https://github.com/pollen-robotics/microduck/issues")!,
        symbol: "chevron.left.forwardslash.chevron.right")

    public static let x = Destination(
        id: "x",
        name: "Post on X",
        purpose: "Opens a draft post. Attach the file yourself — a link cannot carry one.",
        url: URL(string: "https://x.com/compose/post")!,
        symbol: "at")

    public static let destinations: [Destination] = [discord, upstream, x]

    // MARK: - what to say

    /// The message to send with a policy.
    ///
    /// Leads with the fingerprint because that is the only thing a recipient can
    /// check, and states the standing in the manifest's own vocabulary —
    /// released or unrecognised, never "trusted" or "safe", neither of which
    /// this app can establish about anything.
    ///
    /// A NICKNAME IS LABELLED AS ONE THE ONE TIME IT LEAVES THE PHONE. A title
    /// somebody typed means something to them and nothing to a recipient, and a
    /// message leading with it as if it were the file's name is this app
    /// exporting a private label as a public fact. So a renamed policy says
    /// both: what it is called here, and what the file actually is — and the
    /// fingerprint below is still the only part anybody can check.
    public static func message(forPolicy entry: PolicyLibrary.Entry,
                               standing: DuckOfficialPolicies.Standing) -> String {
        var lines: [String]
        if entry.titleSource == .typed {
            lines = ["\(entry.title) — a Microduck policy.",
                     "That is what I call it here. The file is \(entry.exportFileName), and the "
                   + "fingerprint below is the part anybody can check."]
        } else {
            lines = ["\(entry.exportFileName) — a Microduck policy."]
        }
        switch entry.identity {
        case .parameters(let fingerprint):
            lines.append("Parameter fingerprint (SHA-256 over the trained numbers, in a fixed order): "
                       + fingerprint)
            switch standing {
            case .released(let release):
                lines.append("These weights match Pollen's released \(release.filename). \(release.purpose)")
            case .unrecognised:
                lines.append("These weights are not one of the nine Pollen have released. That is not an "
                           + "accusation — somebody's own training run lands here, and so does a release "
                           + "newer than my app — but check the fingerprint against your own copy before "
                           + "you run it on a robot.")
            }
        case .fileOnly:
            // A file that will not parse has no parameters to fingerprint, so
            // there is nothing checkable to say and the message must not
            // pretend otherwise.
            lines.append("This file does not load as a policy here, so there is no fingerprint to give "
                       + "you and nothing about it that you can check from this message.")
        }
        lines.append("Shared from Microduck Studio.")
        return lines.joined(separator: "\n\n")
    }

    /// The message to send with a recorded motion.
    ///
    /// Carries the two things a recipient needs and cannot get from the file's
    /// name: which network produced it, by digest, and how often it actually
    /// works. A motion measured at 0 of 16 is worth sending — it is a useful
    /// negative result — and sending it without that number is not.
    public static func message(forIntent export: IntentExport,
                               outcome: DuckIntentSuccess.Outcome?) -> String {
        var lines = ["\(export.name) — a recorded Microduck motion, "
                   + String(format: "%.1f s at %.0f Hz.", export.frames.count == 0 ? 0
                            : Double(export.frames.count - 1) / export.hz, export.hz)]
        if let fingerprint = export.policyFingerprint {
            lines.append("Recorded from \(export.policyName), parameter fingerprint \(fingerprint). "
                       + "Check that against your own copy — the filename proves nothing.")
        } else {
            lines.append("Recorded from \(export.policyName). I could not include a fingerprint, so "
                       + "that filename is a hint and not a claim.")
        }
        lines.append("It starts \(export.startsFrom) and ends \(export.endsIn), measured from the "
                   + "trunk rather than asserted.")
        if let outcome {
            lines.append("Rolled out \(outcome.rollouts) times with the drop height, footpad friction, "
                       + "a shove and the trunk's centre of mass varied over Pollen's own training "
                       + "ranges: it \(outcome.achieves == 0 ? "never" : "\(outcome.achieves) times out of \(outcome.rollouts)") "
                       + "met \"\(outcome.criterion)\".")
        } else {
            lines.append("I have not rolled this out repeatedly, so I cannot tell you how often it "
                       + "works — only that it did this once.")
        }
        if !export.hasRecordedPath {
            lines.append("No trunk path in this file, so it will replay on the spot.")
        }
        lines.append("Shared from Microduck Studio.")
        return lines.joined(separator: "\n\n")
    }

    /// The message for an authored motion, which is a different kind of thing
    /// and must not be sent looking like a recording.
    public static func message(forDraft draft: IntentDraft) -> String {
        [
            "\(draft.name) — an AUTHORED Microduck motion: "
            + "\(draft.keys.count) keyframes over \(String(format: "%.1f s", draft.duration)), "
            + "interpolated with smoothstep.",
            IntentDraft.disclaimer,
            draft.provenance,
            "Shared from Microduck Studio.",
        ].joined(separator: "\n\n")
    }

    /// The line under the destination list.
    public static let cannotPostNote =
        "Nothing is posted for you. Picking a destination opens it; the file goes wherever you "
      + "attach it. This app has no account anywhere and no way to publish on your behalf."
}
