import Foundation

/// One value out of a `.duck` file's frontmatter, where the schema does not fix its type.
///
/// It exists for exactly one field — `learned_verbs[].metadata`, which quackd types as
/// `dict[str, Any]` — and is deliberately not a general YAML document model. Every other
/// key in the frontmatter has a type the schema pins, so it is decoded straight into a
/// `DuckTask` stored property and never travels through here.
public enum DuckValue: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
    case null
    case list([DuckValue])
    case mapping([String: DuckValue])

    public var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    public var integerValue: Int? { if case .integer(let i) = self { return i }; return nil }
    public var booleanValue: Bool? { if case .boolean(let b) = self { return b }; return nil }
    public var listValue: [DuckValue]? { if case .list(let l) = self { return l }; return nil }
    public var mappingValue: [String: DuckValue]? {
        if case .mapping(let m) = self { return m }
        return nil
    }

    /// Integers read back as numbers too — YAML writes `5`, not `5.0`, for a float field,
    /// and every starter duck writes `max_minutes: 5`.
    public var numberValue: Double? {
        switch self {
        case .double(let d): return d
        case .integer(let i): return Double(i)
        default: return nil
        }
    }
}

/// A `.duck` file — quackd's format for what a robot should ACHIEVE.
///
/// A DIFFERENT LAYER FROM `.duckmove`, AND THE DISTINCTION IS THE POINT. A `.duckmove`
/// says what the joints do: angles, a clock, a trajectory a servo can follow. A `.duck`
/// says nothing about joints at all. It names the verbs an LLM is allowed to call, the
/// budget it may spend calling them, what counts as success, and when to give up — then
/// hands the actual plan to a Markdown body that only an LLM reads. One is a motion; this
/// is a brief.
///
/// The format is quackd's (`rokbenko/quackd`, spec version `duck: 0`), read from
/// `quackd/duckfile/schema.py` and `quackd/duckfile/parser.py` at commit 56d752a
/// (2026-08-28); this implements it, it does not define it. WHERE THE PYTHON IS STRICT,
/// THIS IS STRICT: unknown frontmatter keys are an error there, so they are an error here,
/// because a file this reader accepts and quackd rejects is worse than no reader at all.
///
/// Checked the other way round too, on 2026-08-29: a file this writer produced was loaded
/// by quackd 0.1.0's own `parse_duck_text`, which derived the same battery floor and the
/// same repeat-failure count from it. That is the claim this type is for, and it was
/// measured rather than assumed.
///
/// ## The YAML subset, and why it is a subset
///
/// There is no YAML dependency here — DuckKit and StudioKit have earned their
/// zero-dependency claim and a task file is not worth spending it on. What is implemented
/// is the shape `.duck` frontmatter actually takes, checked against all five starter ducks
/// in the quackd repository: block mappings, block sequences, single-line flow sequences
/// and flow mappings, plain and quoted scalars, `#` comment lines, and plain scalars folded
/// across continuation lines (`ducks/fetch.duck` contains one). Anchors, aliases, tags,
/// multi-document streams, `|` and `>` block scalars, and flow collections spanning several
/// lines are NOT implemented, and a file using them is refused rather than half-read. None
/// of them appears in the format, and guessing at one would mis-drive a robot.
///
/// A folded plain scalar is joined with single spaces, the way YAML folds it. A
/// continuation line containing `: ` would be misread as a new key; that is the one place
/// this subset is narrower than PyYAML in a way a real file could stumble over, and it is
/// written down here rather than discovered later.
public struct DuckTask: Equatable, Sendable {

    // MARK: - the frontmatter

    /// Which verbs the LLM may call, and which need a human to say yes first.
    public struct Verbs: Equatable, Sendable {
        /// Verbs the LLM may call. Anything else is refused. At least one is required.
        public let allow: [String]
        /// A subset of `allow` that prompts a human before executing.
        public let confirm: [String]

        public init(allow: [String], confirm: [String] = []) {
            self.allow = allow
            self.confirm = confirm
        }
    }

    /// Hard stops. The loop ends when any of these is hit, whatever the LLM thinks.
    ///
    /// The defaults and the bounds are quackd's `Budgets` field definitions, not this app's
    /// opinion: 40 steps, 5 minutes, 40 provider calls, bounded 1...1000, greater than 0
    /// and at most 180, and 1...2000 respectively.
    public struct Budgets: Equatable, Sendable {
        public let maxSteps: Int
        public let maxMinutes: Double
        public let maxLLMCalls: Int

        public static let quackdDefaults = Budgets(maxSteps: 40, maxMinutes: 5.0, maxLLMCalls: 40)

        public init(maxSteps: Int = 40, maxMinutes: Double = 5.0, maxLLMCalls: Int = 40) {
            self.maxSteps = maxSteps
            self.maxMinutes = maxMinutes
            self.maxLLMCalls = maxLLMCalls
        }
    }

    /// A learned (ONNX) verb a `.duck` pulls in — quackd's `LearnedVerbRef`.
    ///
    /// NOTE WHAT IS MISSING: there is no `timeout_s` here. The Python `LearnedVerbSpec` has
    /// one, this declaration does not, so a timeout chosen when a policy is exported cannot
    /// be written into a `.duck` and is decided by whoever registers the verb.
    public struct LearnedVerb: Equatable, Sendable {
        public let name: String
        /// Path or URL of the ONNX policy.
        public let policy: String
        /// LLM-facing description. Empty by default in the schema.
        public let description: String
        public let metadata: [String: DuckValue]

        public init(name: String, policy: String,
                    description: String = "", metadata: [String: DuckValue] = [:]) {
            self.name = name
            self.policy = policy
            self.description = description
            self.metadata = metadata
        }
    }

    /// Spec version. Only 0 exists, and `duck: "0"` — the quoted string — is not it.
    public static let specVersion = 0

    public let name: String
    /// One line, human-facing. quackd's key is `description`; renamed here because
    /// `description` on a Swift type means something else entirely.
    public let summary: String
    public let author: String?
    public let verbs: Verbs
    public let budgets: Budgets
    /// Success criteria the LLM must judge itself against. At least one is required.
    public let success: [String]
    /// Abort conditions. Two phrasings are enforced by the executor; every other entry is
    /// prose handed to the LLM. See `batteryAbortPercent` and `repeatFailureAbort`.
    public let abortWhen: [String]
    public let persona: String?
    /// Providers this duck was tested with. NOT ENFORCED — documentation only.
    public let providers: [String]
    public let learnedVerbs: [LearnedVerb]
    /// The Markdown the LLM reads. Free text, and required to be non-empty: a task with no
    /// instructions is a robot with no plan.
    public let body: String

    /// Build a task, refusing anything quackd would refuse.
    ///
    /// Validation lives HERE rather than only in `decode`, so that a task assembled in code
    /// — an exported learned verb, say — cannot be written to a file that quackd then
    /// rejects on the far side. A writer that can emit invalid files is a writer nobody can
    /// trust.
    public init(name: String,
                summary: String,
                author: String? = nil,
                verbs: Verbs,
                budgets: Budgets = .quackdDefaults,
                success: [String],
                abortWhen: [String] = [],
                persona: String? = nil,
                providers: [String] = [],
                learnedVerbs: [LearnedVerb] = [],
                body: String) throws {
        self.name = name
        self.summary = summary
        self.author = author
        self.verbs = verbs
        self.budgets = budgets
        self.success = success
        self.abortWhen = abortWhen
        self.persona = persona
        self.providers = providers
        self.learnedVerbs = learnedVerbs
        self.body = body.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
        try validate()
    }

    // MARK: - refusals

    /// What is wrong, in words somebody can act on. Every case names the offending value,
    /// because "invalid frontmatter" tells an author nothing about which line to open.
    public enum ReadError: Error, Equatable, Sendable {
        case missingFence
        case unterminatedFrontmatter
        case frontmatterIsNotAMapping
        case emptyBody
        case malformedYAML(line: Int, reason: String)
        case unknownKeys([String])
        case missingKey(String)
        case wrongType(key: String, expected: String)
        case notSpecVersionZero(String)
        case invalidName(String)
        case emptyDescription
        case noAllowedVerbs
        case invalidVerbName(String)
        case duplicateVerb(String)
        case confirmNotAllowed([String])
        case noSuccessCriteria
        case budgetOutOfRange(key: String, value: String, allowed: String)

        public var message: String {
            switch self {
            case .missingFence:
                return "This is not a .duck file: it has to start with a --- fence. Blank "
                     + "lines and # comments above it are fine."
            case .unterminatedFrontmatter:
                return "The frontmatter never closes. Add a second --- line after the last "
                     + "setting."
            case .frontmatterIsNotAMapping:
                return "The frontmatter has to be a set of key: value settings."
            case .emptyBody:
                return "There is nothing after the frontmatter. The body is the task "
                     + "instructions the LLM reads, so it cannot be empty."
            case .malformedYAML(let line, let reason):
                return "Line \(line): \(reason)"
            case .unknownKeys(let keys):
                return "The frontmatter has settings quackd does not know: "
                     + "\(keys.sorted().joined(separator: ", ")). Unknown keys are refused "
                     + "rather than ignored, because a misspelled one would silently do "
                     + "nothing at all."
            case .missingKey(let key):
                return "\(key) is required and is missing."
            case .wrongType(let key, let expected):
                return "\(key) has to be \(expected)."
            case .notSpecVersionZero(let found):
                return "duck has to be the number 0 — this file has \(found). Version 0 is "
                     + "the only spec that exists, and the quoted string \"0\" is not the "
                     + "number."
            case .invalidName(let found):
                return "\"\(found)\" is not a usable name. Names are lowercase letters, "
                     + "digits and hyphens, starting with a letter or digit, up to 64 "
                     + "characters — no underscores and no capitals."
            case .emptyDescription:
                return "description is required and cannot be blank: it is the one line a "
                     + "person reads to know what this duck does."
            case .noAllowedVerbs:
                return "verbs.allow is empty. An LLM with no verbs cannot do anything, so "
                     + "list at least one."
            case .invalidVerbName(let found):
                return "\"\(found)\" is not a usable verb name. Verb names are lowercase "
                     + "letters, digits, hyphens and underscores, starting with a letter or "
                     + "digit — walk_to and get_frame are fine, WalkTo is not."
            case .duplicateVerb(let found):
                return "\"\(found)\" is listed twice."
            case .confirmNotAllowed(let extra):
                return "verbs.confirm asks a human to approve verbs that are not allowed: "
                     + "\(extra.joined(separator: ", ")). A verb somebody has to say yes to "
                     + "still has to be one the LLM may call."
            case .noSuccessCriteria:
                return "success is empty. With no criterion the LLM has nothing to judge "
                     + "itself against and will never stop."
            case .budgetOutOfRange(let key, let value, let allowed):
                return "budgets.\(key) is \(value); it has to be \(allowed)."
            }
        }
    }

    // MARK: - reading

    /// Read a `.duck` file.
    ///
    /// The split is quackd's `split_frontmatter`, step for step: skip leading blank and `#`
    /// comment lines, require the next line to be `---`, take the FIRST later line equal to
    /// `---` as the closing fence, and treat everything after it as the body. "First later
    /// line" matters — a body containing a horizontal rule is fine, a frontmatter
    /// containing one is not, and getting that backwards would swallow the instructions
    /// into the YAML.
    public static func decode(_ data: Data) throws -> DuckTask {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ReadError.missingFence
        }
        // Normalised first, so a file written on Windows splits into the same lines that
        // Python's str.splitlines() would give quackd.
        let normalised = text.replacingOccurrences(of: "\r\n", with: "\n")
                             .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalised.split(separator: "\n", omittingEmptySubsequences: false)
                              .map(String.init)

        var start = 0
        while start < lines.count {
            let stripped = lines[start].trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty || stripped.hasPrefix("#") { start += 1 } else { break }
        }
        guard start < lines.count,
              lines[start].trimmingCharacters(in: .whitespaces) == "---" else {
            throw ReadError.missingFence
        }
        guard let end = (start + 1..<lines.count).first(where: {
            lines[$0].trimmingCharacters(in: .whitespaces) == "---"
        }) else {
            throw ReadError.unterminatedFrontmatter
        }

        let frontmatterLines = Array(lines[(start + 1)..<end])
        let body = lines[(end + 1)...].joined(separator: "\n")
                                      .trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReadError.emptyBody
        }

        // The frontmatter's own line numbers, so a refusal points at a line an author can
        // open rather than at an offset into a substring nobody can see.
        var reader = DuckYAML.Reader(lines: frontmatterLines, firstLineNumber: start + 2)
        guard case .mapping(let root) = try reader.parseDocument(), !root.isEmpty else {
            throw ReadError.frontmatterIsNotAMapping
        }

        let known: Set<String> = ["duck", "name", "description", "author", "verbs", "budgets",
                                  "success", "abort_when", "persona", "providers",
                                  "learned_verbs"]
        let unknown = root.keys.filter { !known.contains($0) }
        guard unknown.isEmpty else { throw ReadError.unknownKeys(unknown) }

        guard let duck = root["duck"] else { throw ReadError.missingKey("duck") }
        guard case .integer(specVersion) = duck else {
            throw ReadError.notSpecVersionZero(DuckYAML.describe(duck))
        }

        let name = try requiredString(root, "name")
        let summary = try requiredString(root, "description")

        guard let rawVerbs = root["verbs"] else { throw ReadError.missingKey("verbs") }
        guard let verbsMap = rawVerbs.mappingValue else {
            throw ReadError.wrongType(key: "verbs", expected: "a mapping with allow: and confirm:")
        }
        let unknownVerbKeys = verbsMap.keys.filter { !["allow", "confirm"].contains($0) }
        guard unknownVerbKeys.isEmpty else {
            throw ReadError.unknownKeys(unknownVerbKeys.map { "verbs.\($0)" })
        }
        guard let allowRaw = verbsMap["allow"] else { throw ReadError.missingKey("verbs.allow") }
        let allow = try stringList(allowRaw, key: "verbs.allow")
        let confirm = try verbsMap["confirm"].map { try stringList($0, key: "verbs.confirm") } ?? []

        var budgets = Budgets.quackdDefaults
        if let rawBudgets = root["budgets"] {
            guard let map = rawBudgets.mappingValue else {
                throw ReadError.wrongType(key: "budgets", expected: "a mapping")
            }
            let unknownBudgetKeys = map.keys.filter {
                !["max_steps", "max_minutes", "max_llm_calls"].contains($0)
            }
            guard unknownBudgetKeys.isEmpty else {
                throw ReadError.unknownKeys(unknownBudgetKeys.map { "budgets.\($0)" })
            }
            budgets = Budgets(
                maxSteps: try map["max_steps"].map { try int($0, key: "budgets.max_steps") }
                    ?? Budgets.quackdDefaults.maxSteps,
                // Read as a NUMBER, not an integer: the schema types this as a float and
                // every starter duck writes `max_minutes: 5`. Insisting on one spelling
                // would refuse the format's own files.
                maxMinutes: try map["max_minutes"].map { try number($0, key: "budgets.max_minutes") }
                    ?? Budgets.quackdDefaults.maxMinutes,
                maxLLMCalls: try map["max_llm_calls"].map { try int($0, key: "budgets.max_llm_calls") }
                    ?? Budgets.quackdDefaults.maxLLMCalls)
        }

        guard let successRaw = root["success"] else { throw ReadError.missingKey("success") }
        let success = try stringList(successRaw, key: "success")
        let abortWhen = try root["abort_when"].map { try stringList($0, key: "abort_when") } ?? []
        let providers = try root["providers"].map { try stringList($0, key: "providers") } ?? []

        var learnedVerbs: [LearnedVerb] = []
        if let raw = root["learned_verbs"] {
            guard let entries = raw.listValue else {
                throw ReadError.wrongType(key: "learned_verbs", expected: "a list")
            }
            for entry in entries {
                guard let map = entry.mappingValue else {
                    throw ReadError.wrongType(key: "learned_verbs", expected: "a list of mappings")
                }
                let unknownLearnedKeys = map.keys.filter {
                    !["name", "policy", "description", "metadata"].contains($0)
                }
                guard unknownLearnedKeys.isEmpty else {
                    throw ReadError.unknownKeys(unknownLearnedKeys.map { "learned_verbs.\($0)" })
                }
                let verbName = try requiredString(map, "name", qualified: "learned_verbs.name")
                let policy = try requiredString(map, "policy", qualified: "learned_verbs.policy")
                let blurb = try map["description"].map {
                    try string($0, key: "learned_verbs.description")
                } ?? ""
                var metadata: [String: DuckValue] = [:]
                if let rawMetadata = map["metadata"], case .null = rawMetadata {
                    metadata = [:]
                } else if let rawMetadata = map["metadata"] {
                    guard let mapping = rawMetadata.mappingValue else {
                        throw ReadError.wrongType(key: "learned_verbs.metadata",
                                                  expected: "a mapping")
                    }
                    metadata = mapping
                }
                learnedVerbs.append(LearnedVerb(name: verbName, policy: policy,
                                                description: blurb, metadata: metadata))
            }
        }

        return try DuckTask(
            name: name, summary: summary,
            author: try root["author"].flatMap { try optionalString($0, key: "author") },
            verbs: Verbs(allow: allow, confirm: confirm),
            budgets: budgets, success: success, abortWhen: abortWhen,
            persona: try root["persona"].flatMap { try optionalString($0, key: "persona") },
            providers: providers, learnedVerbs: learnedVerbs, body: body)
    }

    // MARK: - writing

    /// Write the file back out.
    ///
    /// The layout is quackd's own house style, copied from the starter ducks so that a file
    /// this app writes looks like a file a person wrote: schema order, two-space indents,
    /// flow sequences for the verb and provider lists, block sequences for the criteria
    /// somebody has to read one at a time. `ducks/find-and-kick.duck` survives
    /// decode → encode BYTE FOR BYTE, and the test that asserts it is what keeps this
    /// writer honest about the format instead of merely self-consistent.
    ///
    /// Two things do not come back byte-identical, by design. A plain scalar folded across
    /// several source lines is written as one long line, because rewrapping prose at a
    /// column this code cannot know is a worse guess than not wrapping at all. And
    /// `metadata` keys are written in sorted order, because a Swift dictionary has no order
    /// of its own to preserve. Both re-read to the same task.
    public func encode() -> Data {
        var out = "---\n"
        out += "duck: \(DuckTask.specVersion)\n"
        out += "name: \(DuckYAML.blockScalar(name))\n"
        out += "description: \(DuckYAML.blockScalar(summary))\n"
        if let author { out += "author: \(DuckYAML.blockScalar(author))\n" }
        out += "verbs:\n"
        out += "  allow: \(DuckYAML.flowList(verbs.allow))\n"
        out += "  confirm: \(DuckYAML.flowList(verbs.confirm))\n"
        out += "budgets:\n"
        out += "  max_steps: \(budgets.maxSteps)\n"
        out += "  max_minutes: \(DuckYAML.number(budgets.maxMinutes))\n"
        out += "  max_llm_calls: \(budgets.maxLLMCalls)\n"
        out += DuckYAML.blockList("success", success)
        out += DuckYAML.blockList("abort_when", abortWhen)
        if let persona { out += "persona: \(DuckYAML.blockScalar(persona))\n" }
        out += "providers: \(DuckYAML.flowList(providers))\n"
        if learnedVerbs.isEmpty {
            out += "learned_verbs: []\n"
        } else {
            out += "learned_verbs:\n"
            for verb in learnedVerbs {
                out += "  - name: \(DuckYAML.blockScalar(verb.name))\n"
                out += "    policy: \(DuckYAML.blockScalar(verb.policy))\n"
                out += "    description: \(DuckYAML.blockScalar(verb.description))\n"
                if verb.metadata.isEmpty {
                    out += "    metadata: {}\n"
                } else {
                    out += "    metadata:\n"
                    out += DuckYAML.blockMapping(verb.metadata, indent: 6)
                }
            }
        }
        out += "---\n\n"
        out += body
        out += "\n"
        return Data(out.utf8)
    }

    // MARK: - the two conditions the executor actually enforces

    /// The battery floor, when the file states one in the phrasing quackd's executor greps
    /// for; nil when it does not.
    ///
    /// EVERYTHING ELSE IN `abort_when` IS PROSE. quackd enforces exactly two patterns and
    /// hands the rest to the LLM as instructions, which is honest about what is and is not
    /// policed — and this reader reports the same split, so a screen can show an author
    /// which of their abort conditions the machine will actually act on. "Battery below
    /// 15%" is enforced. "Stop if the battery goes below 20% please" is NOT, because the
    /// words between "battery" and "below" defeat the pattern; nor is "Battery below 15
    /// percent", which has no % sign. Those are traps, and surfacing them is the whole
    /// reason this property exists rather than a boolean.
    public var batteryAbortPercent: Double? {
        for line in abortWhen {
            if let value = DuckAbortPatterns.firstCapture(DuckAbortPatterns.battery, in: line) {
                return Double(value)
            }
        }
        return nil
    }

    /// How many consecutive failures of the SAME verb end the run, when the file says so in
    /// the phrasing the executor greps for. "A verb fails 3 times in a row" is not it: the
    /// pattern needs the literal word "same".
    public var repeatFailureAbort: Int? {
        for line in abortWhen {
            if let value = DuckAbortPatterns.firstCapture(DuckAbortPatterns.repeats, in: line) {
                return Int(value)
            }
        }
        return nil
    }

    /// The `abort_when` entries nothing enforces, and which are therefore handed to the LLM.
    public var advisoryAbortConditions: [String] {
        abortWhen.filter {
            DuckAbortPatterns.firstCapture(DuckAbortPatterns.battery, in: $0) == nil
                && DuckAbortPatterns.firstCapture(DuckAbortPatterns.repeats, in: $0) == nil
        }
    }

    // MARK: - validation

    /// The slug rule, `^[a-z0-9][a-z0-9-]{0,63}$`, spelled out rather than compiled: it is
    /// four character tests, and a regular expression for it would be slower to read than
    /// the rule it encodes.
    static func isSlug(_ value: String) -> Bool {
        guard (1...64).contains(value.count) else { return false }
        for (offset, character) in value.enumerated() {
            let isLowerAlphanumeric = character.isASCII
                && ((character.isLetter && character.isLowercase) || character.isNumber)
            if offset == 0 {
                guard isLowerAlphanumeric else { return false }
            } else {
                guard isLowerAlphanumeric || character == "-" else { return false }
            }
        }
        return true
    }

    /// A verb name is the slug rule applied AFTER `_` becomes `-`, which is exactly what
    /// makes `walk_to` and `get_frame` legal while `WalkTo` stays illegal.
    static func isVerbName(_ value: String) -> Bool {
        isSlug(value.replacingOccurrences(of: "_", with: "-"))
    }

    private func validate() throws {
        guard DuckTask.isSlug(name) else { throw ReadError.invalidName(name) }
        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReadError.emptyDescription
        }
        guard !verbs.allow.isEmpty else { throw ReadError.noAllowedVerbs }
        for list in [verbs.allow, verbs.confirm] {
            var seen = Set<String>()
            for verb in list {
                guard DuckTask.isVerbName(verb) else { throw ReadError.invalidVerbName(verb) }
                guard seen.insert(verb).inserted else { throw ReadError.duplicateVerb(verb) }
            }
        }
        // Subset by EXACT string. `walk-to` in confirm does not cover `walk_to` in allow,
        // even though both are legal verb names and normalise to the same slug, because the
        // executor looks a verb up by the name it was written with.
        let extra = verbs.confirm.filter { !verbs.allow.contains($0) }
        guard extra.isEmpty else { throw ReadError.confirmNotAllowed(extra) }
        guard !success.isEmpty else { throw ReadError.noSuccessCriteria }
        guard (1...1000).contains(budgets.maxSteps) else {
            throw ReadError.budgetOutOfRange(key: "max_steps", value: "\(budgets.maxSteps)",
                                             allowed: "between 1 and 1000")
        }
        guard budgets.maxMinutes > 0, budgets.maxMinutes <= 180 else {
            throw ReadError.budgetOutOfRange(key: "max_minutes",
                                             value: DuckYAML.number(budgets.maxMinutes),
                                             allowed: "more than 0 and at most 180")
        }
        guard (1...2000).contains(budgets.maxLLMCalls) else {
            throw ReadError.budgetOutOfRange(key: "max_llm_calls", value: "\(budgets.maxLLMCalls)",
                                             allowed: "between 1 and 2000")
        }
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReadError.emptyBody
        }
    }

    // MARK: - typed reads that keep the key in the message

    private static func requiredString(_ map: [String: DuckValue], _ key: String,
                                       qualified: String? = nil) throws -> String {
        guard let raw = map[key] else { throw ReadError.missingKey(qualified ?? key) }
        return try string(raw, key: qualified ?? key)
    }

    private static func string(_ value: DuckValue, key: String) throws -> String {
        // A scalar that happens to look like a number is still text where the schema says
        // text: `name: 2024` names a duck, it does not count anything.
        switch value {
        case .string(let s): return s
        case .integer(let i): return "\(i)"
        case .double(let d): return DuckYAML.number(d)
        case .boolean(let b): return b ? "true" : "false"
        default: throw ReadError.wrongType(key: key, expected: "text")
        }
    }

    private static func optionalString(_ value: DuckValue, key: String) throws -> String? {
        if case .null = value { return nil }
        return try string(value, key: key)
    }

    private static func stringList(_ value: DuckValue, key: String) throws -> [String] {
        // A BARE STRING IS NOT A ONE-ELEMENT LIST. `providers: openai` is refused rather
        // than helpfully wrapped, because quackd refuses it — and a file that loads here and
        // fails there is precisely the failure this reader exists to prevent.
        guard let items = value.listValue else {
            throw ReadError.wrongType(key: key,
                                      expected: "a list, written [a, b] or one - per line")
        }
        return try items.map { try string($0, key: key) }
    }

    private static func int(_ value: DuckValue, key: String) throws -> Int {
        guard let i = value.integerValue else {
            throw ReadError.wrongType(key: key, expected: "a whole number")
        }
        return i
    }

    private static func number(_ value: DuckValue, key: String) throws -> Double {
        guard let d = value.numberValue else {
            throw ReadError.wrongType(key: key, expected: "a number")
        }
        return d
    }
}

// MARK: - the two enforced phrasings

/// quackd's `BATTERY_ABORT_RE` and `REPEAT_FAIL_ABORT_RE`, character for character.
///
/// COPIED, NOT REINTERPRETED. These two patterns are the entire machine-enforced half of
/// `abort_when`. A Swift paraphrase that was subtly looser would tell an author their
/// battery floor is armed when quackd's own grep is going to miss it, which is the worst
/// possible thing a safety reader can do.
enum DuckAbortPatterns {
    static let battery = compile(#"battery\s+(?:below|under|<)\s*(\d+(?:\.\d+)?)\s*%"#)
    static let repeats = compile(#"same\s+verb\s+fails\s+(\d+)\s+times?\s+in\s+a\s+row"#)

    /// Both patterns are literals in this file and both compile. The force is a
    /// compile-time fact rather than a runtime hope, and an Optional here would push a
    /// meaningless nil into every call site.
    private static func compile(_ source: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: source, options: [.caseInsensitive])
    }

    /// The first capture group of the first match, or nil. FIRST wins, matching quackd's
    /// loop: a file listing two battery floors is governed by the one written first.
    static func firstCapture(_ expression: NSRegularExpression, in line: String) -> String? {
        let text = line as NSString
        guard let match = expression.firstMatch(in: line, options: [],
                                                range: NSRange(location: 0, length: text.length)),
              match.numberOfRanges > 1 else { return nil }
        return text.substring(with: match.range(at: 1))
    }
}

// MARK: - the YAML subset

/// Reading and writing the slice of YAML that `.duck` frontmatter uses. See the subset note
/// on `DuckTask` for what is deliberately absent, and why.
enum DuckYAML {

    // MARK: reading

    struct Reader {
        /// Content lines only, each with the indentation it was found at and the file line
        /// it came from, so a refusal can name a line an author can go and open.
        private struct Line {
            var indent: Int
            var text: String
            let number: Int
        }

        private var lines: [Line] = []
        private var cursor = 0

        init(lines rawLines: [String], firstLineNumber: Int) {
            for (offset, raw) in rawLines.enumerated() {
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                let indent = raw.prefix { $0 == " " }.count
                lines.append(Line(indent: indent, text: trimmed, number: firstLineNumber + offset))
            }
        }

        mutating func parseDocument() throws -> DuckValue {
            guard !lines.isEmpty else { return .mapping([:]) }
            let value = try parseBlock(indent: lines[0].indent)
            guard cursor == lines.count else {
                throw DuckTask.ReadError.malformedYAML(
                    line: lines[cursor].number,
                    reason: "unexpected indentation — this line does not belong to anything "
                          + "above it")
            }
            return value
        }

        private mutating func parseBlock(indent: Int) throws -> DuckValue {
            if isSequenceItem(lines[cursor].text) {
                return .list(try parseSequence(indent: indent))
            }
            return .mapping(try parseMapping(indent: indent))
        }

        private mutating func parseMapping(indent: Int) throws -> [String: DuckValue] {
            var out: [String: DuckValue] = [:]
            while cursor < lines.count, lines[cursor].indent == indent,
                  !isSequenceItem(lines[cursor].text) {
                let line = lines[cursor]
                guard let split = splitKey(line.text) else {
                    throw DuckTask.ReadError.malformedYAML(
                        line: line.number, reason: "expected a `key: value` setting")
                }
                cursor += 1
                if split.rest.isEmpty {
                    out[split.key] = try parseNestedValue(parentIndent: indent)
                } else {
                    out[split.key] = try scalar(fold(split.rest, parentIndent: indent),
                                                line: line.number)
                }
            }
            return out
        }

        private mutating func parseSequence(indent: Int) throws -> [DuckValue] {
            var out: [DuckValue] = []
            while cursor < lines.count, lines[cursor].indent == indent,
                  isSequenceItem(lines[cursor].text) {
                let line = lines[cursor]
                let afterDash = String(line.text.dropFirst()).drop { $0 == " " }
                let dashWidth = line.text.count - afterDash.count
                let rest = String(afterDash)
                if rest.isEmpty {
                    cursor += 1
                    guard cursor < lines.count, lines[cursor].indent > indent else {
                        throw DuckTask.ReadError.malformedYAML(
                            line: line.number, reason: "a `-` with nothing after it")
                    }
                    out.append(try parseBlock(indent: lines[cursor].indent))
                } else if splitKey(rest) != nil, !rest.hasPrefix("{"), !rest.hasPrefix("[") {
                    // `- name: moonwalk` opens a mapping whose remaining keys line up under
                    // `name`. Rewriting the dash away and re-entering the mapping parser at
                    // that column is the whole trick, and it is why `lines` is mutable.
                    let keyIndent = indent + dashWidth
                    lines[cursor].indent = keyIndent
                    lines[cursor].text = rest
                    out.append(.mapping(try parseMapping(indent: keyIndent)))
                } else {
                    cursor += 1
                    out.append(try scalar(fold(rest, parentIndent: indent), line: line.number))
                }
            }
            return out
        }

        private mutating func parseNestedValue(parentIndent: Int) throws -> DuckValue {
            guard cursor < lines.count, lines[cursor].indent > parentIndent else {
                // `key:` with nothing under it is null, exactly as YAML reads it.
                return .null
            }
            return try parseBlock(indent: lines[cursor].indent)
        }

        /// Join a plain scalar to the more-indented continuation lines that follow it, the
        /// way `ducks/fetch.duck` wraps a long success criterion across two lines.
        ///
        /// Quoted and flow scalars are never folded: a `[` continuing onto the next line is
        /// outside this subset, and failing on the missing bracket says so plainly.
        private mutating func fold(_ first: String, parentIndent: Int) -> String {
            guard let opener = first.first, !"\"'[{".contains(opener) else { return first }
            var text = first
            while cursor < lines.count, lines[cursor].indent > parentIndent,
                  !isSequenceItem(lines[cursor].text), splitKey(lines[cursor].text) == nil {
                text += " " + lines[cursor].text
                cursor += 1
            }
            return text
        }

        private func isSequenceItem(_ text: String) -> Bool {
            text == "-" || text.hasPrefix("- ")
        }

        /// Split `key: value`. The colon has to be followed by a space or end the line —
        /// that is what keeps an `https://…` inside a value from looking like a key.
        private func splitKey(_ text: String) -> (key: String, rest: String)? {
            guard let colon = text.firstIndex(of: ":") else { return nil }
            let after = text.index(after: colon)
            if after != text.endIndex, text[after] != " " { return nil }
            let key = String(text[text.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !key.hasPrefix("-") else { return nil }
            let rest = String(text[after...]).trimmingCharacters(in: .whitespaces)
            return (key, rest)
        }
    }

    // MARK: scalars

    static func scalar(_ raw: String, line: Int) throws -> DuckValue {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("[") {
            guard text.hasSuffix("]") else {
                throw DuckTask.ReadError.malformedYAML(
                    line: line, reason: "a [ list that does not close on the same line")
            }
            let inner = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if inner.isEmpty { return .list([]) }
            return .list(try splitTopLevel(inner, line: line).map { try scalar($0, line: line) })
        }
        if text.hasPrefix("{") {
            guard text.hasSuffix("}") else {
                throw DuckTask.ReadError.malformedYAML(
                    line: line, reason: "a { mapping that does not close on the same line")
            }
            let inner = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if inner.isEmpty { return .mapping([:]) }
            var out: [String: DuckValue] = [:]
            for piece in try splitTopLevel(inner, line: line) {
                guard let colon = piece.firstIndex(of: ":") else {
                    throw DuckTask.ReadError.malformedYAML(
                        line: line, reason: "\"\(piece)\" is not a key: value pair")
                }
                let key = String(piece[piece.startIndex..<colon])
                    .trimmingCharacters(in: .whitespaces)
                let value = String(piece[piece.index(after: colon)...])
                out[unquote(key) ?? key] = try scalar(value, line: line)
            }
            return .mapping(out)
        }
        if let unquoted = unquote(text) { return .string(unquoted) }

        // A plain scalar ends at an unquoted " #", which is where YAML starts a comment.
        var plain = text
        if let hash = plain.range(of: " #") {
            plain = String(plain[..<hash.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        switch plain {
        case "", "null", "Null", "NULL", "~": return .null
        case "true", "True", "TRUE": return .boolean(true)
        case "false", "False", "FALSE": return .boolean(false)
        default: break
        }
        // Shape-checked before Double() is allowed near it, because Double("infinity")
        // succeeds — and the word "Infinity" in a success criterion is prose, not a number.
        if looksNumeric(plain) {
            if let i = Int(plain) { return .integer(i) }
            if let d = Double(plain) { return .double(d) }
        }
        return .string(plain)
    }

    static func looksNumeric(_ text: String) -> Bool {
        var seenDigit = false, seenDot = false, seenExponent = false
        var index = text.startIndex
        if index < text.endIndex, text[index] == "-" || text[index] == "+" {
            index = text.index(after: index)
        }
        while index < text.endIndex {
            let character = text[index]
            if character.isNumber && character.isASCII {
                seenDigit = true
            } else if character == "." && !seenDot && !seenExponent {
                seenDot = true
            } else if (character == "e" || character == "E") && seenDigit && !seenExponent {
                seenExponent = true
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "-" || text[next] == "+" { index = next }
                seenDigit = false
            } else {
                return false
            }
            index = text.index(after: index)
        }
        return seenDigit
    }

    private static func unquote(_ text: String) -> String? {
        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") {
            var out = ""
            var escaped = false
            for character in text.dropFirst().dropLast() {
                if escaped {
                    switch character {
                    case "n": out.append("\n")
                    case "t": out.append("\t")
                    default: out.append(character)
                    }
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else {
                    out.append(character)
                }
            }
            return out
        }
        if text.count >= 2, text.hasPrefix("'"), text.hasSuffix("'") {
            return String(text.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return nil
    }

    /// Split a flow collection's body on the commas that are not inside a nested collection
    /// or a quoted string.
    private static func splitTopLevel(_ text: String, line: Int) throws -> [String] {
        var out: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        for character in text {
            if let open = quote {
                current.append(character)
                if character == open { quote = nil }
                continue
            }
            switch character {
            case "\"", "'":
                // A QUOTE ONLY OPENS A SCALAR AT ITS START. YAML treats an apostrophe in
                // the middle of a plain scalar as an apostrophe, and the training caution
                // this app writes — "reproduced from the project's main line" — is exactly
                // that. Treating it as an opening quote swallowed the rest of the list.
                if current.trimmingCharacters(in: .whitespaces).isEmpty { quote = character }
                current.append(character)
            case "[", "{": depth += 1; current.append(character)
            case "]", "}": depth -= 1; current.append(character)
            case "," where depth == 0:
                out.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            default: current.append(character)
            }
        }
        guard quote == nil, depth == 0 else {
            throw DuckTask.ReadError.malformedYAML(line: line,
                                                   reason: "unbalanced quotes or brackets")
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { out.append(last) }
        return out
    }

    static func describe(_ value: DuckValue) -> String {
        switch value {
        case .string(let s): return "the text \"\(s)\""
        case .integer(let i): return "\(i)"
        case .double(let d): return number(d)
        case .boolean(let b): return b ? "true" : "false"
        case .null: return "nothing"
        case .list: return "a list"
        case .mapping: return "a mapping"
        }
    }

    // MARK: writing

    /// A whole-numbered Double is written without a fraction, so a budget of five minutes
    /// comes back out as `max_minutes: 5` — which is what the starter ducks contain, and
    /// what the byte-for-byte round trip needs.
    static func number(_ value: Double) -> String {
        if value == value.rounded(), value.magnitude < 1e15 { return String(Int(value)) }
        return String(value)
    }

    static func blockScalar(_ text: String) -> String { quoteIfNeeded(text, inFlow: false) }

    static func flowList(_ items: [String]) -> String {
        items.isEmpty
            ? "[]"
            : "[" + items.map { quoteIfNeeded($0, inFlow: true) }.joined(separator: ", ") + "]"
    }

    static func blockList(_ key: String, _ items: [String]) -> String {
        if items.isEmpty { return "\(key): []\n" }
        return "\(key):\n" + items.map { "  - \(quoteIfNeeded($0, inFlow: false))\n" }.joined()
    }

    static func blockMapping(_ mapping: [String: DuckValue], indent: Int) -> String {
        let pad = String(repeating: " ", count: indent)
        var out = ""
        // Sorted, because a Swift dictionary has no order of its own and an unordered
        // writer would produce a different file on every run of the same code.
        for key in mapping.keys.sorted() {
            guard let value = mapping[key] else { continue }
            switch value {
            case .mapping(let nested) where !nested.isEmpty:
                out += "\(pad)\(key):\n" + blockMapping(nested, indent: indent + 2)
            case .list(let items) where !items.isEmpty && items.allSatisfy(isScalar):
                out += "\(pad)\(key): [" + items.map(inlineScalar).joined(separator: ", ") + "]\n"
            default:
                out += "\(pad)\(key): \(inlineScalar(value))\n"
            }
        }
        return out
    }

    private static func isScalar(_ value: DuckValue) -> Bool {
        switch value {
        case .list, .mapping: return false
        default: return true
        }
    }

    /// A metadata number keeps its decimal point — `0.0`, not `0`.
    ///
    /// The budget fields drop it (`max_minutes: 5`) to match the starter ducks, but
    /// metadata is untyped on both sides: written as `0`, a float reads back as an integer
    /// and the file no longer round-trips to the same value. A command's idle `[0, 0, 0]` is
    /// exactly that case.
    private static func preciseNumber(_ value: Double) -> String { String(value) }

    private static func inlineScalar(_ value: DuckValue) -> String {
        switch value {
        case .string(let s): return quoteIfNeeded(s, inFlow: true)
        case .integer(let i): return "\(i)"
        case .double(let d): return preciseNumber(d)
        case .boolean(let b): return b ? "true" : "false"
        case .null: return "null"
        case .list(let items):
            return items.isEmpty
                ? "[]" : "[" + items.map(inlineScalar).joined(separator: ", ") + "]"
        case .mapping(let map):
            return map.isEmpty
                ? "{}"
                : "{" + map.keys.sorted().map { "\($0): \(inlineScalar(map[$0] ?? .null))" }
                    .joined(separator: ", ") + "}"
        }
    }

    /// Quote only when a plain scalar would be read back as something else.
    ///
    /// The starter ducks are entirely plain — `Search the area for a ball, walk to it, kick
    /// it.` needs no quotes in a block context even with its commas — and keeping them plain
    /// is what makes a written file look like a hand-written one. In a FLOW context a comma
    /// ends the item, which is why the two contexts get different answers to the same
    /// question.
    private static func quoteIfNeeded(_ text: String, inFlow: Bool) -> String {
        if text.isEmpty { return "\"\"" }
        let indicators: Set<Character> = ["-", "?", ":", ",", "[", "]", "{", "}", "#", "&",
                                          "*", "!", "|", ">", "'", "\"", "%", "@", "`"]
        var needsQuoting = false
        if let first = text.first, indicators.contains(first) { needsQuoting = true }
        if text.contains(": ") || text.hasSuffix(":") { needsQuoting = true }
        if text.contains(" #") { needsQuoting = true }
        if text.contains("\n") || text.contains("\t") { needsQuoting = true }
        if text != text.trimmingCharacters(in: .whitespaces) { needsQuoting = true }
        if inFlow, text.contains(",") || text.contains("[") || text.contains("]")
            || text.contains("{") || text.contains("}") { needsQuoting = true }
        switch text {
        case "null", "Null", "NULL", "~", "true", "True", "TRUE", "false", "False", "FALSE":
            needsQuoting = true
        default: break
        }
        if looksNumeric(text) { needsQuoting = true }
        guard needsQuoting else { return text }
        var escaped = ""
        for character in text {
            switch character {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\t": escaped += "\\t"
            default: escaped.append(character)
            }
        }
        return "\"\(escaped)\""
    }
}
