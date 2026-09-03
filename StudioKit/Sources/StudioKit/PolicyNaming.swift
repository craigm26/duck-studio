import Foundation
import DuckKit

/// The small questions about a policy's NAME, answered once.
///
/// EVERY ONE OF THESE WAS AN APP-SIDE LITERAL OR AN APP-SIDE PREDICATE, and
/// each of them decided something: whether a verdict names a file or says "this
/// file", which action scale a bench applies, what a row shows when nothing was
/// recorded. A predicate about a name that lives in a view is a predicate no
/// test can reach.
public enum PolicyNaming {

    /// Whether a name is a bare 64-character digest — which is what
    /// `PolicyLibrary.persist` writes on disk, and therefore what every policy
    /// imported before nameplates existed comes back called.
    ///
    /// WITH OR WITHOUT `.onnx`, because both spellings occur: the file on disk
    /// carries the extension and the stem does not.
    public static func isDigestName(_ name: String) -> Bool {
        let stem = title(fromFileName: name)
        guard stem.count == 64 else { return false }
        // LOWERCASE HEX AND NOTHING ELSE. `Character.isHexDigit` also says yes
        // to `A`, to `Ａ`, and to the Arabic-Indic digits; the thing being
        // recognised here is specifically what `SHA256…%02x` writes.
        return stem.allSatisfy { lowercaseHex.contains($0) }
    }

    private static let lowercaseHex = Set("0123456789abcdef")

    /// What a sentence about this file should call it.
    ///
    /// A VERDICT NAMES THE FILE, and when the file's name is a digest the
    /// verdict has nothing to name — "4f2a…3.onnx is a Microduck policy" is a
    /// sentence about a hash. "This file" is the honest subject.
    public static func subject(for name: String) -> String {
        isDigestName(name) ? "This file" : name
    }

    /// The name minus one trailing `.onnx`, which is the only extension this
    /// app puts on a policy.
    public static func title(fromFileName name: String) -> String {
        guard name.lowercased().hasSuffix(".onnx") else { return name }
        return String(name.dropLast(5))
    }

    /// Which of the nine a FILE NAME claims to be — the guess a bench falls
    /// back to when a policy came with no manifest.
    ///
    /// THE `BEST_` SPELLING IS FOR FILES, NOT FOR US. This app used to vendor
    /// four of the nine under upstream's training-run names, and somebody who
    /// imported `BEST_alpha_stand.onnx` from the older prototype still has that
    /// file. Dropping the alternative would silently de-rate their policy to
    /// walking's action scale.
    public static func kind(forFileName name: String) -> DuckPolicyKind? {
        DuckPolicyKind.allCases.first { $0.fileName == name || "BEST_" + $0.fileName == name }
    }

    /// The two words the File name row shows when no file name was ever
    /// recorded. A tested kit string rather than an app-side literal, because
    /// it is a claim about what this phone knows.
    public static let fileNameUnknown = "not kept"

    public static let fileNameNotKept =
        "This phone stored the policy under its fingerprint and did not keep what the file was "
      + "called. Anything brought in from now on keeps its name."

    /// WHERE A POLICY CAME FROM CANNOT BE RECOVERED AFTER THE FACT. Anything
    /// persisted before nameplates existed was written with no record of its
    /// host, and this app will not guess one out of a manifest's training
    /// repository — so the provenance pill stays the honest grey and this says
    /// why.
    ///
    /// A KIT STRING BECAUSE IT IS A CLAIM ABOUT WHAT THIS APP KNOWS, and the
    /// scope of the claim — from this build onward, and not retroactively — is
    /// exactly the part a sentence written in a view would quietly lose.
    public static let arrivalNotRecorded =
        "This policy was on the phone before Microduck Studio started writing down where a file "
      + "came from, so where it arrived from is not recoverable. Anything brought in from now on "
      + "keeps it."

    public static let recordingsNeedAFileName =
        "Recordings are matched to a policy by the file name they were recorded from, and this "
      + "phone did not keep this one's — so none can be listed here. Matching by fingerprint is "
      + "not built yet."
}
