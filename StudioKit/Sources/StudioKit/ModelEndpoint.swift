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

    public enum Kind: String, Sendable, Codable, CaseIterable {
        /// Apple Intelligence. No URL, no network, no configuration.
        case appleOnDevice
        /// Anything with an OpenAI-compatible chat endpoint.
        case openAICompatible
        /// Weights downloaded from Hugging Face and run in this process by MLX.
        ///
        /// THE RAW VALUE IS PERSISTED AND THEREFORE PERMANENT — a stored
        /// endpoint carries `"kind":"downloadedMLX"` — so it is named for the
        /// FORMAT rather than for "on this phone". Two of the three kinds are
        /// on this phone: Apple's model, and the `localhost:8080` preset where
        /// another app is serving one. A name that said "onPhone" would be the
        /// least distinguishing thing it could be called.
        case downloadedMLX
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

    /// This host does not answer for itself — it forwards to a model somewhere
    /// else.
    ///
    /// WITHOUT THIS THE PRIVACY NOTE LIES. A Claude bridge runs on your own Pi,
    /// so every test of the address says "on your own network, nothing leaves
    /// it" — and every word typed into it goes to Anthropic. The app cannot
    /// tell the difference by looking at an address, so it has to be told, and
    /// the preset that creates one sets it.
    public var relay: Bool

    /// What it forwards to, named — when the preset that made this endpoint
    /// knew. nil otherwise, and nil is the ordinary case.
    ///
    /// NAMING A DESTINATION THE APP CANNOT SEE WAS THE BUG. Every relay used to
    /// be told it forwards to Anthropic, because a Claude bridge was the only
    /// bridge that existed when that sentence was written — so somebody running
    /// a LiteLLM proxy on their own Pi in front of some other service read a
    /// privacy note naming a company their words never reach. The flag above
    /// says THAT it forwards, which the app is told; this says WHERE, which the
    /// app cannot learn by looking at an address. There is deliberately no
    /// field for typing one: a name typed by hand is a guess, and the note
    /// would then state that guess as fact.
    ///
    /// OPTIONAL, AND IT HAS TO BE. A non-optional with a default throws
    /// `DecodingError.keyNotFound` for every endpoint already stored by a build
    /// that predates this field — which, one bad row at a time, is exactly the
    /// silent total loss `decodeList` below exists to end. An Optional decodes
    /// as nil and costs nobody their list.
    public var relayNote: String?

    public init(id: UUID = UUID(), name: String, kind: Kind,
                baseURL: String = "", model: String = "",
                apiKey: String? = nil, timeout: Double = 900,
                suppressReasoning: Bool = true, relay: Bool = false,
                relayNote: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.timeout = timeout
        self.suppressReasoning = suppressReasoning
        self.relay = relay
        self.relayNote = relayNote
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
        /// A downloaded model names a Hugging Face repository, not an address.
        case notARepository(String)
        case relayOnADownloadedModel
        case notAnAddress(String)

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
            case .notAnAddress(let kind):
                return "A \(kind) model has no address to call. Something asked this app for one, "
                     + "which is a bug in this build rather than anything you did."
            case .relayOnADownloadedModel:
                return "A model running on this phone cannot forward anything anywhere, so it "
                     + "cannot be a relay. Untick that."
            case .notARepository(let text):
                return text.trimmingCharacters(in: .whitespaces).isEmpty
                    ? "Name the model to download, as \"namespace/repository\" — for example "
                    + "mlx-community/Qwen3-1.7B-4bit."
                    : "\"\(text)\" is not a Hugging Face repository. It should be "
                    + "\"namespace/repository\", like mlx-community/Qwen3-1.7B-4bit."
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
    ///
    /// ONE RULE, AND THE BENCH USES IT TOO. `DuckBench` kept its own copy of
    /// this test and that copy was NARROWER — no 100.64/10, no `.internal`, no
    /// `::1` — so the same tailnet host was private enough to send a sentence
    /// to and not private enough to send a policy to. That is not a defensible
    /// distinction, and it blocked the case this family is actually built for:
    /// a phone, a bench and a GPU box all on one tailnet, none of them on the
    /// same Wi-Fi. Two copies of a security predicate is one copy too many;
    /// this is the one.
    public static func isLocalHost(_ host: String) -> Bool {
        let name = host.lowercased()
        if name == "localhost" || name == "127.0.0.1" || name == "::1" { return true }
        if name.hasSuffix(".local") || name.hasSuffix(".internal") { return true }
        // A MAGICDNS NAME IS A TAILNET NAME. Tailscale's own suffix is
        // `.ts.net`, and a host reached by one resolves to 100.64/10 — the
        // range two lines below. Accepting the name as well as the number
        // spares somebody having to look the number up to use their own
        // machine.
        if name.hasSuffix(".ts.net") { return true }
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

    /// SWITCHED, NOT GUARDED. Both of these read
    /// `guard kind == .openAICompatible else { return }`, which passed every
    /// other kind through with NO checks at all — so a third kind would have
    /// been accepted with an empty repository id and then failed at load, far
    /// from the screen that could have said why. An exhaustive switch makes a
    /// fourth kind a compile error here instead.
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw Refusal.emptyName }
        switch kind {
        case .appleOnDevice:
            return
        case .downloadedMLX:
            let repository = model.trimmingCharacters(in: .whitespaces)
            let halves = repository.split(separator: "/", omittingEmptySubsequences: false)
            guard halves.count == 2, !halves[0].isEmpty, !halves[1].isEmpty else {
                throw Refusal.notARepository(model)
            }
            // A DOWNLOADED MODEL CANNOT FORWARD ANYWHERE, and `privacyNote`'s
            // relay branch is the most alarming sentence in this app to have
            // fire falsely.
            guard !relay else { throw Refusal.relayOnADownloadedModel }
        case .openAICompatible:
            // The model is checked BEFORE the address, and the order is pinned
            // by test: an endpoint with neither is missing a model name first.
            guard !model.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw Refusal.emptyModel
            }
            try validateAddress()
        }
    }

    /// Everything the ADDRESS has to satisfy, with nothing in it about the name
    /// or the model.
    ///
    /// SPLIT OUT BECAUSE THE WHOLE CHECK WAS CIRCULAR. `modelsURL()` — the
    /// address of the list a server keeps of its own models — used to run the
    /// full `validate()`, so asking a server what models it has was refused
    /// with "Name the model as the server names it. Ask the server for its
    /// list — /v1/models — if you are not sure." That is the app sending
    /// somebody to do the very thing it has just refused to do, and it made
    /// both "Ask what models it has" and "Check this address" unusable at the
    /// only moment they are wanted: on a new endpoint, before anything is
    /// known. Nothing about a bearer token, a name or a model id is needed to
    /// know whether an address is reachable.
    ///
    /// THE PLAINTEXT REFUSAL IS IN HERE, NOT IN THE OTHER HALF. It is the one
    /// rule that must hold for every request this app makes, including a
    /// check, so it has to live on the address side of the split.
    public func validateAddress() throws {
        switch kind {
        case .appleOnDevice, .downloadedMLX: return
        case .openAICompatible: break
        }
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

    // MARK: - reading the saved list back

    /// What came back out of storage: the endpoints that could be read, and how
    /// many could not.
    ///
    /// WHY THIS TYPE EXISTS AT ALL. The saved list used to come back through
    /// one `try? JSONDecoder().decode([ModelEndpoint].self, …)`, and a JSON
    /// array decodes all-or-nothing: ONE unreadable element throws for the
    /// whole array, `try?` turns that throw into nil, and every endpoint a
    /// person had configured vanished — with Apple's on-device model silently
    /// selected in their place and not one word said about it. That is the
    /// exact silent failure this app is built against, and it is reachable from
    /// any future field added to this struct the wrong way.
    public struct Salvage: Equatable, Sendable {
        public var endpoints: [ModelEndpoint]
        /// How many stored entries could not be read.
        ///
        /// nil MEANS SOMETHING DIFFERENT FROM ZERO: the stored list could not
        /// be read as a list at all, so nobody can say how many were in it.
        /// Reporting that as 0 would be the app claiming a number it does not
        /// have.
        public var unreadable: Int?

        public init(endpoints: [ModelEndpoint], unreadable: Int?) {
            self.endpoints = endpoints
            self.unreadable = unreadable
        }

        /// The line for the Models screen, or nil when everything was read.
        ///
        /// PAST TENSE, BECAUSE THE READER MAY BE SEEING THIS LONG AFTERWARDS.
        /// The count is persisted so the notice survives a person who never
        /// opens the Models screen — which was the point of storing it — and
        /// the salvaged list is flushed back over the stored one on the next
        /// save. So by the time these words are read the list is readable
        /// again, and a sentence in the present tense ("could not be read...
        /// this has started again") describes a state that no longer holds. It
        /// would be a small lie, told by the one feature here whose whole
        /// purpose is not losing things quietly.
        public var note: String? {
            guard let unreadable else {
                return "The saved list of models could not be read, and this list was started "
                     + "again from Apple's on-device model. Add your own addresses back and they "
                     + "will save as before."
            }
            switch unreadable {
            case 0:
                return nil
            case 1:
                return "1 saved model could not be read and was left out of this list. "
                     + "Everything else survived — add it again with the address and model name "
                     + "that server uses."
            default:
                return "\(unreadable) saved models could not be read and were left out of "
                     + "this list. Everything else survived — add them again with the addresses "
                     + "and model names those servers use."
            }
        }
    }

    /// Read the saved list one element at a time, keeping what can be read.
    ///
    /// THE LOOP HAS A TRAP IN IT AND THE TRAP IS SILENT. A failed
    /// `container.decode` does NOT advance an unkeyed container's cursor — it
    /// throws before the increment — so the obvious `while !isAtEnd { if let x
    /// = try? … }` spins on the first bad element forever and hangs the app on
    /// launch. The cursor has to be stepped past the bad element deliberately,
    /// which is what `decodeNil` and `Skipped` are for, and the `break` at the
    /// bottom is the last guarantee that this function terminates even if both
    /// of those ever stop working.
    public static func decodeList(from data: Data) -> Salvage {
        struct Reader: Decodable {
            var salvage: Salvage

            /// Decodes from anything at all, so the cursor can be stepped over
            /// an element `ModelEndpoint` refused.
            struct Skipped: Decodable {
                init(from decoder: Decoder) throws {}
            }

            init(from decoder: Decoder) throws {
                var container = try decoder.unkeyedContainer()
                var kept: [ModelEndpoint] = []
                var lost = 0
                while !container.isAtEnd {
                    if let one = try? container.decode(ModelEndpoint.self) {
                        kept.append(one)
                        continue
                    }
                    lost += 1
                    // A null steps the cursor only through decodeNil, which
                    // returns false without moving for anything that is not one.
                    if (try? container.decodeNil()) == true { continue }
                    if (try? container.decode(Skipped.self)) != nil { continue }
                    break
                }
                salvage = Salvage(endpoints: kept, unreadable: lost)
            }
        }
        guard let reader = try? JSONDecoder().decode(Reader.self, from: data) else {
            return Salvage(endpoints: [], unreadable: nil)
        }
        return reader.salvage
    }

    /// Where the chat request goes.
    public func chatURL() throws -> URL {
        try validate()
        // A KIND WITH NO ADDRESS MUST FAIL LOUDLY HERE. `validate()` now
        // returns cleanly for a downloaded model, so without this the empty
        // baseURL would produce the relative URL "/chat/completions" and the
        // mistake would surface as a network error somewhere else entirely.
        guard kind == .openAICompatible else { throw Refusal.notAnAddress(kind.rawValue) }
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + "/chat/completions") else {
            throw Refusal.notAURL(baseURL)
        }
        return url
    }

    /// Where its model list lives, for the "what have you got?" button and for
    /// the address check.
    ///
    /// ADDRESS ONLY. Both of its callers exist to be used before a model has
    /// been named — see the note on `validateAddress()`.
    public func modelsURL() throws -> URL {
        try validateAddress()
        // A KIND WITH NO ADDRESS MUST FAIL LOUDLY HERE. `validate()` now
        // returns cleanly for a downloaded model, so without this the empty
        // baseURL would produce the relative URL "/chat/completions" and the
        // mistake would surface as a network error somewhere else entirely.
        guard kind == .openAICompatible else { throw Refusal.notAnAddress(kind.rawValue) }
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
        case .downloadedMLX:
            // NOT APPLE'S SENTENCE, THOUGH IT NEARLY IS. The difference worth
            // stating is that this one arrived over the network: the weights
            // were fetched once, and a person who has just spent two gigabytes
            // of their data allowance deserves that acknowledged rather than
            // being told, flatly, that nothing leaves the phone.
            return "Runs on this phone. Nothing you type leaves it — the weights were "
                 + "downloaded from Hugging Face once, and nothing is sent while it drafts."
        case .openAICompatible:
            let host = URL(string: baseURL)?.host ?? baseURL
            if relay {
                // WHAT THIS SAYS DEPENDS ON WHAT THE APP WAS TOLD, and the
                // difference is the whole point of `relayNote`. Named, it names
                // the destination. Unnamed, it says the one true thing left:
                // that the words go somewhere this app cannot see. It says
                // nothing either way about keys or billing — the stored copy of
                // an endpoint has its key stripped to the Keychain, so a
                // sentence about whether a key travels would be composed from a
                // field that is nil whether or not one exists.
                // whitespacesAndNewlines, NOT whitespaces. `CharacterSet
                // .whitespaces` excludes newlines, so a relayNote of "\n"
                // survived the guard and produced "…forwards it to \n." — a
                // sentence naming a destination that is a line break.
                let forwards = relayNote?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !forwards.isEmpty else {
                    return "Goes to \(host) on your own network, which forwards it somewhere "
                         + "else. The words leave your network, and this app cannot see where "
                         + "they land."
                }
                return "Goes to \(host) on your own network, which forwards it to \(forwards). "
                     + "The words leave your network, and this app cannot see what happens to "
                     + "them there."
            }
            if host == "localhost" || host == "127.0.0.1" {
                return "Goes to another app on this phone. Nothing leaves the device."
            }
            return ModelEndpoint.isLocalHost(host)
                ? "Goes to \(host) on your own network. Nothing leaves it."
                : "Goes to \(host) over the internet."
        }
    }
}
