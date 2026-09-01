import Foundation
import StudioKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whatever writes the draft. Apple's on-device model, a box on your desk, a
/// Pi in the hall, another app on this phone.
///
/// THE DRAFT LANDS IN THE SAME PLACE WHOEVER WROTE IT. Every path here returns
/// a `MotionProposal` or an `AutomationProposal`, and those still have to
/// resolve against the real joints, the real travel and the intents this app
/// actually holds. A model that invents a joint gets a person's refusal. So
/// choosing a model is a choice about privacy, speed and cost — never about
/// whether what comes back can be trusted.
@MainActor
enum DraftEngine {

    struct Answer {
        let json: String
        /// How long the model took, and roughly how fast it ran. A local model
        /// on a small board is SLOW, and a screen that says "1.9 tokens a
        /// second" is telling the truth about why the wait was ninety seconds
        /// — a spinner is not.
        let seconds: Double
        let tokens: Int?
        var tokensPerSecond: Double? {
            guard let tokens, seconds > 0.2 else { return nil }
            return Double(tokens) / seconds
        }
    }

    enum EngineError: LocalizedError {
        case appleUnavailable(String)
        case http(status: Int, body: String)

        var errorDescription: String? {
            switch self {
            case .appleUnavailable(let why): return why
            case .http(let status, let body):
                let preview = body.count > 200 ? String(body.prefix(200)) + "…" : body
                return "The server answered \(status). \(preview)"
            }
        }
    }

    /// Ask whichever endpoint is chosen, and give back raw JSON for
    /// `ChatDraft` to read.
    /// `instructions` overrides the ones the kind would build. Editing a motion
    /// needs the motion in the prompt, and the kind alone cannot see it.
    static func ask(_ endpoint: ModelEndpoint, kind: ChatDraft.Kind,
                    prompt: String, knownIntents: Set<String>,
                    instructions override: String? = nil) async throws -> Answer {
        let instructions = override
            ?? ChatDraft.instructions(for: kind, knownIntents: knownIntents)
        switch endpoint.kind {
        case .appleOnDevice:
            return try await askApple(instructions: instructions, prompt: prompt)
        case .openAICompatible:
            return try await askServer(endpoint, instructions: instructions, prompt: prompt)
        case .downloadedMLX:
            return try await askPhone(endpoint, instructions: instructions, prompt: prompt)
        }
    }

    /// What models a server has, so nobody has to type `gemma4:e4b-it-qat`
    /// from memory.
    static func models(at endpoint: ModelEndpoint) async throws -> [String] {
        var request = URLRequest(url: try endpoint.modelsURL())
        request.timeoutInterval = 20
        sign(&request, with: endpoint)
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data)
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = top["data"] as? [[String: Any]] else { return [] }
        return list.compactMap { $0["id"] as? String }.sorted()
    }

    // MARK: - the two paths

    private static func askApple(instructions: String, prompt: String) async throws -> Answer {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                throw EngineError.appleUnavailable(DraftRouting.appleUnavailable)
            }
            let started = Date()
            let session = LanguageModelSession(instructions: instructions)
            let reply = try await session.respond(to: prompt).content
            return Answer(json: try ChatWire.firstJSONObject(in: reply),
                          seconds: Date().timeIntervalSince(started), tokens: nil)
        }
        #endif
        throw EngineError.appleUnavailable(DraftRouting.appleTooOld)
    }

    /// A model whose weights are on this phone, run in this process.
    ///
    /// SHAPED LIKE `askApple`, WHICH IS THE TEMPLATE FOR A KIND WITH NO
    /// ADDRESS: check it can actually run before starting, time it, and read
    /// the reply with the SAME `ChatWire.firstJSONObject` every other kind
    /// uses — a downloaded model returns JSON in prose exactly as an HTTP
    /// server does, so it must not get its own reader to drift against.
    ///
    /// THREE CHECKS BEFORE IT RUNS, in the order that costs least. Whether MLX
    /// is here at all, then whether iOS is offering enough memory. Loading
    /// several gigabytes to discover the second is how an app gets killed
    /// rather than refusing.
    private static func askPhone(_ endpoint: ModelEndpoint,
                                 instructions: String, prompt: String) async throws -> Answer {
        let runtime = PhoneModelRuntime.shared
        guard runtime.isSupported else {
            throw EngineError.appleUnavailable(PhoneModelInstall.simulatorRefusal)
        }
        // THE THIRD CHECK THE COMMENT ALREADY PROMISED. Without it, after iOS
        // reclaims Library/Caches, drafting silently re-downloads up to two
        // gigabytes mid-draft, over cellular, with no progress bar anywhere.
        guard PhoneModelFiles.bytesOnDisk(endpoint.model) != nil else {
            throw EngineError.appleUnavailable(PhoneModelInstall.notLoaded)
        }

        // `os_proc_available_memory` is what iOS is offering THIS app right
        // now, which is the only honest budget — the phone's RAM is not it.
        //
        // AND ZERO IS NOT A SMALL NUMBER. iOS returns 0 when the process is at
        // or over its limit, so treating it as a budget prints "about 0 MB"
        // and calls a working model too big.
        let budget = Int(os_proc_available_memory())
        guard budget > 0 else { throw EngineError.appleUnavailable(PhoneModel.budgetUnknown) }

        // BOTH LISTS. `catalogue` is the tried one; a model from `untried` or
        // from search is exactly as able to exhaust the memory.
        let resident = runtime.isResident(endpoint.model)
        if let known = PhoneModel.all.first(where: { $0.repository == endpoint.model }),
           !known.fits(budgetBytes: budget, alreadyResident: resident) {
            throw EngineError.appleUnavailable(
                resident ? PhoneModel.tooBigWhileLoaded(known.name, budgetBytes: budget)
                         : PhoneModel.tooBig(known, budgetBytes: budget))
        }
        let started = Date()
        // THE ENDPOINT'S OWN ALLOWANCE, ENFORCED. Every other kind gets its
        // timeout from URLSession; this one had none at all, so a generation
        // that overran was judged late only after it finished.
        let reply = try await runtime.ask(endpoint.model,
                                          instructions: instructions, prompt: prompt,
                                          deadline: endpoint.timeout)
        return Answer(json: try ChatWire.firstJSONObject(in: reply),
                      seconds: Date().timeIntervalSince(started), tokens: nil)
    }

    private static func askServer(_ endpoint: ModelEndpoint,
                                  instructions: String, prompt: String) async throws -> Answer {
        var request = URLRequest(url: try endpoint.chatURL())
        request.httpMethod = "POST"
        request.timeoutInterval = endpoint.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        sign(&request, with: endpoint)
        // THE ENDPOINT'S OWN CEILING WHERE IT HAS ONE. Without this the field
        // exists and is never sent, and a destination whose thinking tokens
        // come out of the same budget answers with nothing at all — the
        // failure this app has already measured once.
        request.httpBody = try ChatWire.requestBody(
            model: endpoint.model, instructions: instructions, prompt: prompt,
            maxTokens: endpoint.maxTokens ?? 900,
            suppressReasoning: endpoint.suppressReasoning)

        let started = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let elapsed = Date().timeIntervalSince(started)
        try check(response, data)
        let reply = try ChatWire.content(from: data)
        return Answer(json: try ChatWire.firstJSONObject(in: reply),
                      seconds: elapsed, tokens: completionTokens(in: data))
    }

    private static func sign(_ request: inout URLRequest, with endpoint: ModelEndpoint) {
        if let key = endpoint.apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode != 200 else { return }
        throw EngineError.http(status: http.statusCode,
                               body: String(data: data, encoding: .utf8) ?? "")
    }

    private static func completionTokens(in data: Data) -> Int? {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = top["usage"] as? [String: Any] else { return nil }
        return usage["completion_tokens"] as? Int
    }
}
