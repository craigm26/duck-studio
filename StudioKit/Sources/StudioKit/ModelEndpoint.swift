import Foundation

/// Where a draft comes from — Apple's on-device model, a box on your desk, a
/// Raspberry Pi in the hall, or another app on this phone.
///
/// THE POINT IS THAT IT DOES NOT MATTER. Whatever writes the draft, the draft
/// lands in `MotionProposal` or `AutomationProposal` and goes through exactly
/// the resolution a hand-typed one does: joints have to exist, angles have to
/// be inside the travel, intents have to be ones this app holds. A model that
/// invents a joint gets the same refusal a person would. So the choice of model
/// is a choice about privacy, speed and cost — not about whether the app can be
/// trusted with what comes back.
///
/// ANYTHING SPEAKING `/v1/chat/completions` WORKS: Ollama, LM Studio,
/// llama.cpp's server, vLLM, an OpenAI-compatible proxy. That includes servers
/// running on the phone itself, which is why localhost is a first-class case
/// rather than a curiosity.
public struct ModelEndpoint: Equatable, Sendable, Codable, Identifiable {

    public enum Kind: String, Sendable, Codable {
        /// Apple Intelligence. No URL, no network, no configuration.
        case appleOnDevice
        /// Anything with an OpenAI-compatible chat endpoint.
        case openAICompatible
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    /// The base, INCLUDING the version segment: `http://pi.local:11434/v1`.
    /// Ollama, LM Studio and llama.cpp all serve `/v1` and all append
    /// `/chat/completions` to it, so keeping the version in the base is what
    /// lets one field cover every one of them.
    public var baseURL: String
    /// The model id as that server names it — `gemma4:e4b-it-qat`,
    /// `qwen3.5:4b`, whatever `/v1/models` lists.
    public var model: String
    /// Optional bearer token. Local servers ignore it; proxies want it.
    public var apiKey: String?
    /// Seconds to wait.
    ///
    /// THE DEFAULT IS DELIBERATELY ENORMOUS, AND IT IS SET BY MEASUREMENT.
    /// A 7.5B Gemma at Q4 on a CPU-only Raspberry Pi 5 took **766 seconds** to
    /// write one 200-token motion draft — about a quarter of a token a second.
    /// The first version of this field defaulted to 300 s and would have
    /// failed that request, which is worse than useless: it looks like a
    /// broken server rather than a slow one, and sends people off to debug an
    /// address that was correct all along.
    ///
    /// The remedy for the wait is a smaller model, not a shorter timeout, and
    /// the screen says so after a test run.
    public var timeout: Double

    /// Ask the server not to let the model think first.
    ///
    /// ON BY DEFAULT BECAUSE THE FAILURE IS TOTAL. A reasoning model asked for
    /// a motion spends its entire token budget in its scratchpad and answers
    /// with an empty string — measured at 725 seconds and nothing to show for
    /// it. `reasoning_effort: "none"` is the standard parameter and local
    /// servers honour it. A hosted service that rejects the value is the one
    /// case for turning this off.
    public var suppressReasoning: Bool

    public init(id: UUID = UUID(), name: String, kind: Kind,
                baseURL: String = "", model: String = "",
                apiKey: String? = nil, timeout: Double = 900,
                suppressReasoning: Bool = true) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.timeout = timeout
        self.suppressReasoning = suppressReasoning
    }

    /// Apple's, which needs nothing configured.
    public static let onDevice = ModelEndpoint(
        name: "Apple on-device", kind: .appleOnDevice)

    // MARK: - refusals

    public enum Refusal: Error, Equatable, Sendable {
        case emptyName
        case notAURL(String)
        case missingVersionPath(String)
        case plaintextToThePublicInternet(host: String)
        case emptyModel

        public var message: String {
            switch self {
            case .emptyName:
                return "Give it a name you will recognise in a list."
            case .notAURL(let text):
                return "\"\(text)\" is not an address. It looks like http://192.168.1.20:11434/v1"
            case .missingVersionPath(let text):
                return "\(text) has no /v1 on the end. Ollama, LM Studio and llama.cpp all serve "
                     + "their OpenAI-compatible API under /v1, and without it the request lands "
                     + "on the wrong route and comes back 404."
            case .plaintextToThePublicInternet(let host):
                return "\(host) is not on your own network, and http sends what you type across "
                     + "the internet in the clear. Use https for anything off your LAN. A local "
                     + "address — localhost, 192.168.x, 10.x, a .local name, or a Tailscale "
                     + "100.x — is fine over http, because it never leaves your network."
            case .emptyModel:
                return "Name the model as the server names it. Ask the server for its list — "
                     + "/v1/models — if you are not sure."
            }
        }
    }

    /// Whether a host is somewhere on your own network.
    ///
    /// TAILSCALE COUNTS, and that matters here: a Pi reached at 100.x over a
    /// tailnet is as private as one at 192.168.x, and 100.64.0.0/10 is the
    /// carrier-grade NAT range Tailscale hands out. Refusing it would push
    /// people onto plaintext-to-the-internet or onto nothing.
    public static func isLocalHost(_ host: String) -> Bool {
        let name = host.lowercased()
        if name == "localhost" || name == "127.0.0.1" || name == "::1" { return true }
        if name.hasSuffix(".local") || name.hasSuffix(".internal") { return true }
        let parts = name.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (parts[0], parts[1]) {
        case (10, _): return true
        case (192, 168): return true
        case (172, 16...31): return true
        case (100, 64...127): return true          // Tailscale / CGNAT
        case (169, 254): return true               // link-local
        default: return false
        }
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw Refusal.emptyName }
        guard kind == .openAICompatible else { return }
        guard !model.trimmingCharacters(in: .whitespaces).isEmpty else { throw Refusal.emptyModel }
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw Refusal.notAURL(baseURL)
        }
        guard url.path.contains("/v1") else { throw Refusal.missingVersionPath(trimmed) }
        if scheme == "http", !ModelEndpoint.isLocalHost(host) {
            throw Refusal.plaintextToThePublicInternet(host: host)
        }
    }

    /// Where the chat request goes.
    public func chatURL() throws -> URL {
        try validate()
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + "/chat/completions") else {
            throw Refusal.notAURL(baseURL)
        }
        return url
    }

    /// Where its model list lives, for the "what have you got?" button.
    public func modelsURL() throws -> URL {
        try validate()
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + "/models") else { throw Refusal.notAURL(baseURL) }
        return url
    }

    /// Where what you type will end up, in one sentence, for the screen.
    ///
    /// A PERSON DESERVES TO KNOW THIS BEFORE THEY TYPE. "Drafted by AI" says
    /// nothing about whether the sentence left the building.
    public var privacyNote: String {
        switch kind {
        case .appleOnDevice:
            return "Nothing you type leaves this phone."
        case .openAICompatible:
            let host = URL(string: baseURL)?.host ?? baseURL
            if host == "localhost" || host == "127.0.0.1" {
                return "Goes to another app on this phone. Nothing leaves the device."
            }
            return ModelEndpoint.isLocalHost(host)
                ? "Goes to \(host) on your own network. Nothing leaves it."
                : "Goes to \(host) over the internet."
        }
    }
}
