import Foundation

/// What a typed name has to be, and what to say when it is not.
///
/// THE RULE IS SHORT BECAUSE THE NAME DECIDES NOTHING. A title is not a file
/// name, not a key, not a bench's word for anything and not what leaves the
/// phone, so the only two things that can be wrong with one are that it is
/// empty — a row you cannot tell from the next one — and that it is longer than
/// this app stores.
public enum PolicyTitleRule {

    /// The number this app keeps. It is a STORAGE limit and the refusal says so
    /// in those words: how much a row can show is a width under Dynamic Type,
    /// and at accessibility sizes a row shows far fewer than sixty characters.
    /// A message claiming otherwise would be wrong on most phones.
    public static let maxLength = 60

    public static let explainer =
        "A name is yours and stays on this phone. The file, its fingerprint, and anything you "
      + "share are unchanged."

    /// `Error` IS NOT DECORATION HERE. `Result`'s failure type is constrained
    /// to `Error`, and `check` returns a `Result` — the plan wrote the enum as
    /// `Equatable, Sendable` and the signature as `Result<String, Refusal>`,
    /// which cannot both be true. Adding the conformance is the smaller of the
    /// two changes: it costs no sentence and no signature.
    public enum Refusal: Error, Equatable, Sendable {
        case empty
        case tooLong

        /// - Parameter current: what the policy is called right now, so the
        ///   refusal ends somewhere rather than leaving the person wondering
        ///   what they are looking at.
        public func message(keeping current: String) -> String {
            switch self {
            case .empty:
                return "A policy with no name is a row you cannot tell from the next one. "
                     + "It is still called \u{201C}\(current)\u{201D}."
            case .tooLong:
                return "That name is longer than the \(PolicyTitleRule.maxLength) characters this app keeps. "
                     + "It is still called \u{201C}\(current)\u{201D}."
            }
        }
    }

    /// Trims, then judges.
    ///
    /// NO CHARACTER-CLASS RULE. A title is never a file name any more — the
    /// split is the whole point of this track — so a slash or a colon costs
    /// nothing and refusing one would be this app enforcing a filesystem
    /// constraint on a string that never reaches a filesystem.
    public static func check(_ typed: String) -> Result<String, Refusal> {
        let cleaned = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return .failure(.empty) }
        guard cleaned.count <= maxLength else { return .failure(.tooLong) }
        return .success(cleaned)
    }
}
