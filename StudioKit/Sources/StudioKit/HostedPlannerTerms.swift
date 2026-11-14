import Foundation

// MARK: - the two vendors

/// The vendors a person can bring their own key for. Two, on purpose.
///
/// Google Gemini is not here and must not be added for this app: the Gemini API terms require
/// account holders to be 18 or older and bar apps "likely to be accessed by individuals under the
/// age of 18" (aistudio.google.com/docs/terms, read 2026-11-13). Gemini Robotics-ER is off for
/// the same reason.
public enum HostedVendor: String, CaseIterable, Equatable, Hashable, Sendable, Codable {
    case anthropic, openai

    /// The brain id the evidence and terms rows are pinned to.
    public var providerId: String { "byok.\(rawValue)" }

    /// The vendor's name in plain text. No logo anywhere: neither vendor has approved one.
    public var name: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        }
    }

    /// The model this app asks by default. Its exact id is what an EvidenceRow keys on.
    public var defaultModel: String {
        switch self {
        case .anthropic: return AnthropicPlanner.defaultModel
        case .openai: return OpenAIPlanner.defaultModel
        }
    }

    /// The model's own name, as the vendor writes it. Feature names never say "GPT"; the card
    /// names the actual model (OpenAI brand guidelines).
    public var modelName: String {
        switch self {
        case .anthropic: return "Claude Haiku 5.5"
        case .openai: return "GPT-6 Luna"
        }
    }

    /// Where to get a key.
    public var keyPage: String {
        switch self {
        case .anthropic: return "platform.claude.com"
        case .openai: return "platform.openai.com"
        }
    }

    /// The start every key from this vendor has. A paste that does not start this way is refused
    /// before it is saved, so a key for the other vendor is not sent to the wrong one.
    public var keyPrefix: String {
        switch self {
        case .anthropic: return "sk-ant-"
        case .openai: return "sk-"
        }
    }

    public var terms: TermsRow {
        switch self {
        case .anthropic: return HostedTerms.anthropic
        case .openai: return HostedTerms.openai
        }
    }

    /// The card label (section 4).
    public var label: String { "Hosted by \(name), your key" }

    /// The planner's card, with no evidence row. There is none for either vendor yet, so the
    /// offer rule hides both cards. That is correct until a measured run exists.
    public func info(model: String? = nil, evidence: EvidenceRow? = nil) -> PlannerInfo {
        PlannerInfo(id: providerId, modelVersion: model ?? defaultModel, label: label,
                    runsOn: .hosted(vendor: name), key: .byok(provider: rawValue), trainedOn: [],
                    decisionDeadline: HostedPlanner.decisionDeadline, framesSent: .none,
                    evidence: evidence, terms: terms, realDuck: .off)
    }

    /// The key as typed, trimmed and checked for shape. Nothing is sent to check it.
    public func cleaned(_ typed: String) -> Result<String, HostedKeyProblem> {
        switch DuckDream.cleaned(typed) {
        case .failure: return .failure(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : .badCharacters)
        case .success(let key):
            guard key.hasPrefix(keyPrefix) else { return .failure(.wrongVendor(self)) }
            if self == .openai, key.hasPrefix(HostedVendor.anthropic.keyPrefix) { return .failure(.wrongVendor(self)) }
            return .success(key)
        }
    }
}

public enum HostedKeyProblem: Error, Equatable, Sendable {
    case empty, badCharacters, wrongVendor(HostedVendor)

    public var says: String {
        switch self {
        case .empty: return "Paste a key first."
        case .badCharacters:
            return "That key holds a space, a line break or a character such as a curly quote. Copy it again, whole."
        case .wrongVendor(let v): return "That does not look like an \(v.name) key. \(v.name) keys start with \(v.keyPrefix)"
        }
    }
}

// MARK: - the terms rows

/// What each vendor's terms say for this app, read by a person on 2026-11-13
/// (scratch/brains-terms/terms-rows.md). `TermsRow` has no "conditional" answer. A conditional
/// answer is written `.allowed` only when this app meets the condition, and the condition is
/// listed in `conditions`. An answer the pages do not give is `.unknown` or nil, never inferred.
public enum HostedTerms {
    public static let checked = "2026-11-13"

    /// Anthropic. Hidden even with a passing evidence row, because BYOK in a third-party app is
    /// not addressed: the Commercial Terms govern API keys and say the services are "not for
    /// consumer use". One email to Anthropic settles it; until then the answer is unknown.
    public static let anthropic = TermsRow(
        providerId: HostedVendor.anthropic.providerId, checked: checked,
        source: "anthropic.com/legal/aup; anthropic.com/legal/commercial-terms; "
            + "privacy.claude.com article 7996866; support.claude.com article 9307344",
        // Conditional: a walking robot in a home is a "mobile robot in a place where people may
        // be present". Met by the conditions below.
        physicalControl: .allowed,
        byokInThirdPartyApp: .unknown,
        imageRetention: "Up to 30 days for abuse checks. Content flagged under the Usage Policy is kept up to 2 years.",
        trainsOnImages: false,
        // The Commercial Terms, which govern API keys, state no minimum age.
        minimumAge: nil)

    /// OpenAI. Every field has an answer, so a passing evidence row would show the card.
    public static let openai = TermsRow(
        providerId: HostedVendor.openai.providerId, checked: checked,
        source: "openai.com/policies/usage-policies (effective 2026-11-20); openai.com/policies/services-agreement; "
            + "openai.com/policies/row-terms-of-use; developers.openai.com/api/docs/guides/your-data; openai.com/brand",
        // No robot rule found. "Product safety components" is listed as a sensitive area; whether
        // a toy robot's motion counts is not said.
        physicalControl: .allowed,
        // Conditional: no buying, selling or transferring keys with a third party. Met because the
        // key stays on this device and goes only to OpenAI.
        byokInThirdPartyApp: .allowed,
        imageRetention: "Up to 30 days for abuse checks. A picture flagged as child abuse material is kept for review.",
        trainsOnImages: false,
        // Rest of World Terms of Use: 13, with a parent's permission under 18. The Services
        // Agreement that governs the API states no age.
        minimumAge: 13)

    /// The conditions the terms set, and how this app meets each one. Shown to nobody as a
    /// claim; kept so the row and its reasons stay together.
    public static func conditions(_ v: HostedVendor) -> [String] {
        switch v {
        case .anthropic:
            return [
                "High-risk physical actions: a person who can see the duck must be able to stop it at any time. Met by Stop on every screen and the copy on the card.",
                "The duck must stop or hold still when that person intervenes or the link to the service drops. Met by the stop path and the robot's deadman.",
                "Speed and force limits must be enforced by the equipment or an independent controller, not by model output. Met by DuckEnvelopeGate and the robot's own limits.",
                "Products serving minors: AI disclosure, a public COPPA statement, extra safeguards, and Anthropic's child-safety system prompt if one is provided.",
                "Users must be told that factual statements in outputs should be checked.",
            ]
        case .openai:
            return [
                "Minors need consent from a parent or guardian. Met by the adult holding the key and the card's line for children.",
                "No buying, selling or transferring API keys with a third party. Met because the key stays in this device's Keychain and goes only to api.openai.com.",
                "Set store to false so the Responses API keeps no application state. Done on every request.",
                "No \"GPT\" in feature names, no OpenAI logo, no \"GPT-powered\". The card names the model.",
            ]
        }
    }

    /// What the pages leave open. Each one keeps an answer unknown or is a question for Craig.
    public static func openQuestions(_ v: HostedVendor) -> [String] {
        switch v {
        case .anthropic:
            return [
                "Whether a parent's own key in a family hobby app counts as consumer use, which the Commercial Terms exclude.",
                "Minimum account age under the Commercial Terms.",
                "Whether the household-device exclusion covers the duck.",
            ]
        case .openai:
            return [
                "Whether family members sharing one device count as multiple users sharing credentials.",
                "Whether a toy robot's motion is a product safety component.",
                "The US Terms of Use could not be loaded; the Rest of World terms were read instead.",
            ]
        }
    }
}

// MARK: - the words

/// Every sentence the BYOK key screen and a future planner card show. Kept in the kit so the
/// tests can read them. Plain text, no vendor logos, never "safe".
public enum HostedPlannerWords {
    public static let heading = "Hosted planners"
    public static let rowTitle = "Hosted planners, your key"
    public static let rowDetail = "Paste or forget a key for Anthropic or OpenAI."
    public static let noKey = "No key is saved for this planner. Add one in Settings, Models, Hosted planners."
    public static let saveKey = "Save the key"
    public static let forgetKey = "Forget the key"
    public static let notOfferedYet =
        "Not offered on Play or Auto yet. A planner shows there only after it is measured on the practice duck."

    public static func keyPlaceholder(_ v: HostedVendor) -> String { "Your \(v.name) API key (\(v.keyPrefix)...)" }
    public static func savedHere(_ v: HostedVendor, hint: String) -> String { "This device holds \(v.name) key \(hint)." }
    public static func forgotten(_ v: HostedVendor) -> String {
        "The key is gone from this device. This does not cancel it. To cancel it, delete it at \(v.keyPage)."
    }

    /// "Decisions come from an AI model (Anthropic, Claude Haiku 5.5), not a person."
    public static func aiDisclosure(_ v: HostedVendor) -> String {
        "Decisions come from an AI model (\(v.name), \(v.modelName)), not a person."
    }

    public static func keyStays(_ v: HostedVendor) -> String {
        "Your key stays on this device and is sent only to \(v.name). Microduck Studio is not affiliated with or endorsed by \(v.name)."
    }

    public static func retention(_ v: HostedVendor) -> String {
        "\(v.name) keeps what you send, including camera pictures, for up to 30 days for abuse checks. It does not train on it by default."
    }

    public static func whatIsSent(_ v: HostedVendor) -> String {
        "Each decision sends \(v.name) the goal, the duck's position and its last few steps. "
            + "A camera picture goes only if you allowed the camera."
    }

    public static let adultWatches =
        "An adult must watch the duck and can stop it at any time. The duck stops if the connection drops. "
        + "Speed and joint limits are set by the duck, not by the AI."

    public static let forChildren =
        "For children: a parent or guardian holds the key and agrees to the child using it."

    public static let canBeWrong = "The AI can be wrong. Check what it suggests."

    public static func bills(_ v: HostedVendor) -> String { "\(v.name) bills your key for each decision." }

    /// The card's lines, in order. The children's privacy statement link is added when it exists.
    public static func card(_ v: HostedVendor) -> [String] {
        [aiDisclosure(v), keyStays(v), retention(v), whatIsSent(v), adultWatches, forChildren, canBeWrong, bills(v)]
    }

    public static var all: [String] {
        var out = [heading, rowTitle, rowDetail, noKey, saveKey, forgetKey, notOfferedYet]
        for v in HostedVendor.allCases {
            out += card(v) + [keyPlaceholder(v), savedHere(v, hint: "…abcd"), forgotten(v)]
            out += [HostedKeyProblem.wrongVendor(v).says]
        }
        out += [HostedKeyProblem.empty.says, HostedKeyProblem.badCharacters.says]
        return out
    }
}
