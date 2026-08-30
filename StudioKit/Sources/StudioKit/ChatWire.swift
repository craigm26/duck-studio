import Foundation

/// Talking to an OpenAI-compatible server, and getting usable JSON back out of
/// whatever it says.
///
/// THE HARD PART IS NOT THE REQUEST, IT IS THE REPLY. Apple's on-device model
/// is handed a `@Generable` type and returns that type. A local model is handed
/// a description and returns prose, or fenced markdown, or a paragraph of
/// reasoning followed by the JSON, or all three. Qwen wraps its reasoning in
/// `<think>` tags. Gemma likes a "Here's the JSON:" preamble. Every one of
/// those is a perfectly good answer wearing a costume, and throwing them away
/// as malformed would make small local models look far worse than they are.
///
/// So this is deliberately generous about what it accepts and strict about what
/// it produces: pull the first balanced JSON object out of the reply, hand it to
/// the proposal types, and let THEM refuse. The choke-point does not move.
public enum ChatWire {

    // MARK: - the request

    /// The body of a `/v1/chat/completions` call.
    ///
    /// `response_format` is sent because the servers that honour it give much
    /// better output, and the ones that do not ignore an unknown key rather
    /// than failing. Temperature is low: this is a structured-extraction task,
    /// not a creative one, and a chatty sample is a refused draft.
    public static func requestBody(model: String, instructions: String, prompt: String,
                                   temperature: Double = 0.2,
                                   maxTokens: Int = 900,
                                   suppressReasoning: Bool = true) throws -> Data {
        var body: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "max_tokens": maxTokens,
            "stream": false,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": prompt],
            ],
        ]
        // WITHOUT THIS, A REASONING MODEL RETURNS NOTHING AT ALL, and it is
        // not a hypothetical: qwen3.5:2b on a Pi spent 725 seconds and the
        // whole 900-token budget thinking, then answered with an empty string
        // and finish_reason "length". `reasoning_effort: "none"` is the
        // standard OpenAI parameter for it and Ollama honours it — the same
        // request comes back instantly with an answer and no reasoning block.
        // `chat_template_kwargs.enable_thinking` and Ollama's own `think` flag
        // were both tried first and neither did anything through this route.
        //
        // A hosted service may reject the value, which is why it can be turned
        // off per endpoint; the refusal names the switch.
        if suppressReasoning { body["reasoning_effort"] = "none" }
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    // MARK: - the reply

    public enum WireError: Error, Equatable, Sendable {
        case notJSON
        case serverSaid(String)
        case noChoices
        case noJSONInReply(String)
        /// The model answered with nothing and a reasoning block: it spent the
        /// whole token budget thinking.
        case spentItAllThinking
        /// Cut off at the token limit mid-answer.
        case cutOffAtTokenLimit(String)

        public var message: String {
            switch self {
            case .notJSON:
                return "That server did not answer with JSON. Check the address ends in /v1."
            case .serverSaid(let text):
                return "The server refused: \(text)"
            case .noChoices:
                return "The server answered, but with no completion in it."
            case .noJSONInReply(let text):
                guard !text.isEmpty else {
                    return "The model replied with nothing at all."
                }
                let preview = text.count > 160 ? String(text.prefix(160)) + "…" : text
                return "The model replied without any JSON in it. It said: \(preview)"
            case .spentItAllThinking:
                return "That model thought until it ran out of room and never answered. It is a "
                     + "reasoning model, and reasoning is switched off by default for exactly "
                     + "this — check that \"suppress reasoning\" is on for this endpoint, or "
                     + "pick a model that does not think."
            case .cutOffAtTokenLimit(let text):
                let preview = text.count > 120 ? String(text.prefix(120)) + "…" : text
                return "The answer was cut off at the token limit. It got as far as: \(preview)"
            }
        }
    }

    /// The assistant's text, out of an OpenAI-shaped response.
    ///
    /// IT LOOKS IN THE REASONING BLOCK WHEN THE CONTENT IS EMPTY. A thinking
    /// model that wrote perfectly good JSON in its scratchpad and then ran out
    /// of room before repeating it has still answered the question, and
    /// throwing that away to be strict about which field it arrived in would
    /// be losing work for nothing.
    public static func content(from data: Data) throws -> String {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WireError.notJSON
        }
        // Errors come back in an `error` object on every server that has one.
        if let error = top["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "\(error)"
            throw WireError.serverSaid(message)
        }
        guard let choices = top["choices"] as? [[String: Any]], let first = choices.first else {
            throw WireError.noChoices
        }
        let cutOff = (first["finish_reason"] as? String) == "length"
        if let message = first["message"] as? [String: Any] {
            // Some servers put a refusal where the content goes.
            if let refusal = message["refusal"] as? String { throw WireError.serverSaid(refusal) }
            if let text = message["content"] as? String, !text.isEmpty {
                if cutOff, (try? firstJSONObject(in: text)) == nil {
                    throw WireError.cutOffAtTokenLimit(text)
                }
                return text
            }
            // Empty content. Ollama files the thinking under `reasoning`;
            // other servers use `reasoning_content`.
            let reasoning = (message["reasoning"] as? String)
                ?? (message["reasoning_content"] as? String)
            if let reasoning, !reasoning.isEmpty {
                if (try? firstJSONObject(in: reasoning)) != nil { return reasoning }
                throw WireError.spentItAllThinking
            }
            if cutOff { throw WireError.cutOffAtTokenLimit("") }
            return ""
        }
        if let text = first["text"] as? String { return text }   // legacy completions
        throw WireError.noChoices
    }

    /// The first balanced JSON object in a reply, with the costumes removed.
    ///
    /// Strips `<think>` blocks first — a reasoning model's scratchpad routinely
    /// contains draft JSON, and taking the first object without stripping picks
    /// up the model's rejected first attempt instead of its answer.
    public static func firstJSONObject(in reply: String) throws -> String {
        var text = reply
        for tag in ["think", "thinking", "reasoning"] {
            text = strip(tag: tag, from: text)
        }
        // A fenced block, if there is one: its contents are the answer.
        if let fenced = fencedBlock(in: text), let object = balancedObject(in: fenced) {
            return object
        }
        if let object = balancedObject(in: text) { return object }
        throw WireError.noJSONInReply(reply.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Everything between the first ``` and the next one, ignoring the language
    /// tag on the opening fence.
    static func fencedBlock(in text: String) -> String? {
        guard let open = text.range(of: "```") else { return nil }
        let afterTicks = text[open.upperBound...]
        // Drop the language tag, which runs to the end of that line.
        let bodyStart = afterTicks.firstIndex(of: "\n").map { afterTicks.index(after: $0) }
            ?? afterTicks.startIndex
        let body = afterTicks[bodyStart...]
        guard let close = body.range(of: "```") else { return String(body) }
        return String(body[..<close.lowerBound])
    }

    /// Scan for `{` and return through its matching `}`, respecting strings and
    /// escapes so a brace inside a name does not end the object early.
    static func balancedObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" && inString {
                escaped = true
            } else if character == "\"" {
                inString.toggle()
            } else if !inString {
                if character == "{" { depth += 1 }
                if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(text[start...index])
                    }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// Remove `<tag>…</tag>`, including an unclosed one — a reply cut off by a
    /// token limit mid-thought has an opening tag and no closing one, and
    /// keeping the remainder would feed the scratchpad to the parser.
    static func strip(tag: String, from text: String) -> String {
        var result = text
        while let open = result.range(of: "<\(tag)>", options: .caseInsensitive) {
            if let close = result.range(of: "</\(tag)>", options: .caseInsensitive,
                                        range: open.upperBound..<result.endIndex) {
                result.replaceSubrange(open.lowerBound..<close.upperBound, with: "")
            } else {
                result.removeSubrange(open.lowerBound..<result.endIndex)
            }
        }
        return result
    }
}
