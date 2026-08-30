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
///
/// A QUOTED KEY IN A BLOCK MAPPING IS THE OTHER PLACE. This reader splits `key: value`
/// before it unquotes anything, so `"a: b": 1` — legal PyYAML — is read as the key `"a`
/// here. A quoted key in a FLOW mapping is fine, because that branch does unquote, and the
/// writer leans on exactly that: the only author-chosen names in the format are
/// `learned_verbs[].metadata`'s, and one of those that a block line cannot carry — it starts
/// with a space or a `#`, or holds a colon or a comma — sends its whole mapping into flow
/// form, quoted, instead of being mangled or turned away.
///
/// ## What `validate()` still refuses, measured rather than described
///
/// A name with no form at all is refused; `DuckYAML.nameFits` decides which those are by
/// writing the name and reading it back rather than by reasoning about the parser, and
/// `testTheTrueSetOfMetadataNamesThisWriterRefuses` pins the answer as a table. Two traits
/// have names, a third is a residue the fallback sentence covers, and NONE OF THE THREE CAN
/// COME OUT OF A FILE:
///
/// - a name holding a CARRIAGE RETURN, anywhere in the metadata. `decode` normalises `\r`
///   before the parser runs and `unquote` does not decode a `\r` escape, so no `.duck` this
///   reader accepts can hand one back — the refusal only ever meets a name built in code.
/// - a name whose `{ } [ ]` brackets DO NOT CLOSE EACH OTHER, and only where it sits inside
///   a `[ ]` or another `{ }`. `a}b` is written and read back one level up; nested, the
///   enclosing `{` is already open by the time `splitTopLevel` reaches the name, so the
///   name's own brackets have to balance. A hand-written file carrying one — `outer:
///   [{"a}b": 1}]` — is not refused by this check either: `splitTopLevel` cannot read it at
///   all and says so on the line, before there is a name to refuse.
/// - and a RESIDUE with no name of its own, again only when nested: a name whose brackets
///   balance by COUNT but whose running depth returns to zero at a comma, so
///   `splitTopLevel` cuts the entry in half at that comma. `},{` and `}a,{` are the shape.
///   These get the fallback sentence — "this writer has no form that reads it back
///   unchanged" — which is the honest answer for a family too small and too strange to name
///   a character for. They are unreachable from a file for the same reason the bracket
///   family is: `splitTopLevel` refuses the line before a name exists to refuse.
///
/// THE THIRD ONE IS WHY THIS PARAGRAPH SAYS "residue" AND NOT "exactly". A previous version
/// of this comment said there were exactly two, and a sweep of every name up to three
/// characters over the punctuation this parser cares about found nineteen in a third bucket.
/// The code was right and the sentence was not, which is the same defect — a categorical
/// claim execution contradicts — that this whole passage was rewritten to remove.
///
/// The claim that used to stand here was that the refused set "in practice means one
/// holding a colon". It is written down as a warning because it was false in both
/// directions: a corpus of 506 hand-written frontmatters, each checked against PyYAML
/// 6.0.2, was refused in 22 places, and `he said "hi", ok` — one of them — holds no colon.
/// A comment asserting a categorical safety claim that execution contradicts is the bug,
/// not the wording. THE CLAIM ABOVE IS NARROW ON PURPOSE. It is about this refusal and
/// nothing else: this reader is still narrower than PyYAML in the two ways the subset notes
/// above describe, and neither of them is fixed by a sentence here.
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
        case metadataNameIsNotWritable(verb: String, name: String)

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
            case .metadataNameIsNotWritable(let verb, let name):
                // "WHERE IT SITS", NOT "INTO A .duck FILE", because the one trait that
                // still reaches this on a name an author could plausibly type — brackets
                // that do not close — depends on where in the metadata the name is. `a}b`
                // is written and read back perfectly one level up; it is only inside a
                // `[ ]` or a `{ }` that nothing can carry it. Saying the name is
                // unwritable outright would send an author renaming a key that is fine.
                return "The learned verb \"\(verb)\" has a metadata setting named "
                     + "\"\(name)\", and there is no way to write that name where it sits "
                     + "and read it back: \(DuckYAML.whyNameIsNotWritable(name)). "
                     + "Written out, \"\(name)\" would come back as a different name "
                     + "holding a different value, and nothing would complain. Rename it."
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
                } else if DuckYAML.everyNameFitsBlockForm(verb.metadata) {
                    out += "    metadata:\n"
                    out += DuckYAML.blockMapping(verb.metadata, indent: 6)
                } else {
                    // ONE NAME BLOCK FORM CANNOT CARRY SENDS THE WHOLE MAPPING TO FLOW, and
                    // it has to be the whole mapping: a block line writes its name raw, so
                    // there is no way to quote one entry and leave its neighbours alone.
                    // Flow form is where a quoted name survives, because the flow reader
                    // unquotes a key and the block reader never does — which is why a name
                    // starting with a space, or a `#`, or holding a comma is WRITTEN HERE
                    // rather than refused. Measured before this existed: ` x` came back as
                    // `x`, and `#x` was read as a comment and vanished, both in silence.
                    out += "    metadata: \(DuckYAML.inlineMapping(verb.metadata))\n"
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
        // `learned_verbs[].metadata` IS THE ONE UNTYPED CORNER OF THE FORMAT (`dict[str,
        // Any]`), and so the one place a caller names something themselves. Measured before
        // the writer learned to place a name: `["a: b": 1]` was written as `a: b: 1` and read
        // back as `["a": "b: 1"]`, a name and a value nobody wrote, with nothing thrown; a
        // name opening with `#` was worse still, because the line became a comment and the
        // entry vanished outright. Both are silent, which is the failure this app treats as
        // first-order.
        //
        // THIS RUNS ON DECODE TOO, so it may only refuse a name NO FILE CAN PRODUCE — a
        // `.duck` quackd runs and this reader turns away is the one failure this reader
        // exists to prevent, and two rounds of this check committed it. The first refused
        // ` x`, `#x`, `-x`, `a, b` and a leading tab; the answer was to WIDEN THE WRITER,
        // which now puts them in flow form, quoted. The second still refused 22 places in a
        // 506-file corpus of hand-written PyYAML-legal frontmatter, in two families that had
        // nothing to do with the names themselves: a
        // quoted flow key holding `\"` or `''` was cut in half by `splitTopLevel`, and any
        // quoted flow key holding a colon was cut before `unquote` ran, so the refusal fired
        // on names like `"{a` that the READER had invented. Both were fixed where they were
        // — in `splitTopLevel` and `flowKeyColon` — rather than by narrowing the refusal,
        // because a refusal is not the right place to apologise for a misread.
        //
        // WHAT IS LEFT CANNOT COME OUT OF A FILE AT ALL; the class comment lists the two
        // traits and why. `testTheMetadataRefusalNeverTurnsAwayAFileThisReaderCanRead` holds
        // it down by feeding every awkward name through all nine shapes a real file can put
        // one in, and `testTheTrueSetOfMetadataNamesThisWriterRefuses` pins the residue.
        for verb in learnedVerbs {
            if let name = DuckYAML.unwritableMetadataName(in: .mapping(verb.metadata)) {
                throw ReadError.metadataNameIsNotWritable(verb: verb.name, name: name)
            }
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
                } else if let opener = rest.first, !"\"'[{".contains(opener),
                          splitKey(rest) != nil {
                    // `- name: moonwalk` opens a mapping whose remaining keys line up under
                    // `name`. Rewriting the dash away and re-entering the mapping parser at
                    // that column is the whole trick, and it is why `lines` is mutable.
                    //
                    // THE OPENER SET IS `fold`'s, CHARACTER FOR CHARACTER, AND IT HAS TO BE.
                    // `splitKey` cannot see quotes — it cuts at the first colon followed by
                    // a space, wherever that sits — so a QUOTED item was being handed to it
                    // and read as a mapping. This half of the set (`{` and `[`) was excluded
                    // from the first line of this parser; `"` and `'` were simply missed,
                    // and the omission made the writer emit a file its own reader refused:
                    // `quoteIfNeeded` quotes any criterion containing `: `, so
                    // `success: ["ball moved: at least 0.3 m"]` went out as
                    // `  - "ball moved: at least 0.3 m"` and came back as the mapping
                    // `"ball moved` -> `at least 0.3 m"`, whereupon `stringList` told the
                    // author "success has to be text" about a file this app had just
                    // written. PyYAML — and so quackd — reads that line as a plain string,
                    // which makes it the mirror of the promise at the top of this file.
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
                guard let colon = flowKeyColon(in: piece) else {
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
        if let unquoted = unquote(withoutTrailingComment(text)) { return .string(unquoted) }

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

    /// Cut a trailing `# comment` off a scalar that OPENS with a quote, so that
    /// `- "ball moved: 0.3 m" # note` reads as `ball moved: 0.3 m`.
    ///
    /// IT CANNOT WAIT FOR THE PLAIN-SCALAR COMMENT STRIP BELOW, and that ordering is the
    /// whole bug this exists to close. That strip runs only AFTER `unquote` has failed, and
    /// `unquote` fails on a quoted scalar with a comment after it for the trivial reason
    /// that the text no longer ENDS in a quote — so the value came back carrying its own
    /// quote characters, a wrong answer nobody was told about. Worse, that strip cuts at the
    /// first ` #` anywhere in the line, so `"a # b" # note` was truncated to `"a`. Both are
    /// silent, which is the failure mode this app treats as first-order.
    ///
    /// ONLY A SCALAR OPENING WITH A QUOTE IS CONSIDERED, and only the text after the
    /// matching CLOSING quote is inspected. That is what keeps an apostrophe in the middle
    /// of a plain scalar — `rok's fork`, the one that already cost this parser a bug — from
    /// opening anything here.
    private static func withoutTrailingComment(_ text: String) -> String {
        guard let opener = text.first, opener == "\"" || opener == "'",
              let close = closingQuote(of: text) else { return text }
        let after = String(text[text.index(after: close)...])
        // YAML needs whitespace before a `#` for it to start a comment; `"a"#b` is not a
        // comment, it is malformed, and guessing at it would invent a value.
        guard after.first == " " || after.first == "\t",
              after.trimmingCharacters(in: .whitespaces).hasPrefix("#") else { return text }
        return String(text[...close])
    }

    /// The index of the quote closing a scalar that opens at the first character, honouring
    /// the same two escapes `unquote` understands — `\"` inside a double-quoted scalar and
    /// `''` inside a single-quoted one. Nil when the scalar never closes, in which case the
    /// caller leaves the text exactly as it found it rather than guessing at an end.
    private static func closingQuote(of text: String) -> String.Index? {
        guard let opener = text.first else { return nil }
        var index = text.index(after: text.startIndex)
        while index < text.endIndex {
            let character = text[index]
            if opener == "\"", character == "\\" {
                index = text.index(after: index)
                if index == text.endIndex { return nil }
            } else if character == opener {
                guard opener == "'" else { return index }
                let next = text.index(after: index)
                // `''` inside a single-quoted scalar is one apostrophe, not the end of it.
                if next < text.endIndex, text[next] == "'" { index = next } else { return index }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// Where a flow mapping's `key: value` divides — the first colon OUTSIDE the key's own
    /// quotes, and outside its own text.
    ///
    /// SCANNING FOR THE FIRST COLON ANYWHERE WAS A SILENT MISREAD, and a wide one. PyYAML,
    /// and so quackd, reads `{"a: b": 1}` as the name `a: b`; cutting at the colon inside
    /// the quotes handed back the name `"a` holding the value `b": 1` — a name and a value
    /// nobody wrote, with nothing thrown. It cost refusals too: the invented name `"{a`
    /// carries an unbalanced brace, so `outer: [{"{a: b}": 1}]` was turned away for a defect
    /// in the reader's own answer rather than anything in the file.
    ///
    /// Only a key OPENING with a quote is treated as quoted, and only its matching closing
    /// quote ends it — the same rule `withoutTrailingComment` uses, and for the same reason:
    /// an apostrophe in the middle of a plain key is an apostrophe. When the quote never
    /// closes there is nothing to be gained by guessing, so the first colon is used and the
    /// piece fails downstream the way it always did.
    ///
    /// AN UNQUOTED KEY DIVIDES AT THE FIRST COLON FOLLOWED BY A SPACE, or at one ending the
    /// piece — `splitKey`'s rule, and PyYAML's. A bare `a:b` is one plain scalar to PyYAML,
    /// so `{a:b: 1}` is the name `a:b`; cutting at the first colon regardless made it the
    /// name `a` holding `b: 1`, and then refused `a:b` as unwritable, because the writer
    /// cannot reproduce a name the reader will not hand back. The fallback to the first
    /// colon stands for a piece with no qualifying colon at all, so that a shape this reader
    /// used to make something of is not newly turned away.
    private static func flowKeyColon(in piece: String) -> String.Index? {
        if let opener = piece.first, opener == "\"" || opener == "'",
           let close = closingQuote(of: piece) {
            return piece[piece.index(after: close)...].firstIndex(of: ":")
        }
        var index = piece.startIndex
        while let colon = piece[index...].firstIndex(of: ":") {
            let after = piece.index(after: colon)
            if after == piece.endIndex || piece[after] == " " { return colon }
            index = after
        }
        return piece.firstIndex(of: ":")
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
    ///
    /// THE TWO ESCAPES ARE HONOURED HERE BECAUSE THE COMMA THEY HIDE IS REAL. This ran on
    /// raw characters once and ended a quoted run at the first bare quote it saw, so the
    /// `\"` in `{"he said \"hi\", ok": 1}` closed the key and the comma after it split the
    /// entry in half — a file PyYAML and quackd read without complaint, refused here as
    /// `is not a key: value pair`, and refused a second time as a metadata name the writer
    /// could not place. The rule is `closingQuote`'s, character for character: `\"` inside a
    /// double-quoted scalar and `''` inside a single-quoted one are content, not an end.
    private static func splitTopLevel(_ text: String, line: Int) throws -> [String] {
        var out: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if let open = quote {
                current.append(character)
                if open == "\"", character == "\\" {
                    let next = text.index(after: index)
                    // A trailing backslash closes nothing. Leaving `quote` set is what makes
                    // the guard below report the unbalanced quote this really is.
                    guard next < text.endIndex else { break }
                    current.append(text[next])
                    index = text.index(after: next)
                    continue
                }
                if character == open {
                    let next = text.index(after: index)
                    if open == "'", next < text.endIndex, text[next] == "'" {
                        current.append("'")
                        index = text.index(after: next)
                        continue
                    }
                    quote = nil
                }
                index = text.index(after: index)
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
            index = text.index(after: index)
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
            // THE SAME FORM CHOICE `encode` MAKES FOR `metadata` ITSELF, and the two have to
            // keep agreeing: a nested mapping stays in block form only while every one of
            // its own names can be written on a line of its own. Otherwise it falls through
            // to `inlineScalar` below, which writes flow and quotes its keys.
            case .mapping(let nested) where !nested.isEmpty && everyNameFitsBlockForm(nested):
                out += "\(pad)\(key):\n" + blockMapping(nested, indent: indent + 2)
            case .list(let items) where !items.isEmpty && items.allSatisfy(isScalar):
                out += "\(pad)\(key): [" + items.map(inlineScalar).joined(separator: ", ") + "]\n"
            default:
                out += "\(pad)\(key): \(inlineScalar(value))\n"
            }
        }
        return out
    }

    /// WHERE A METADATA NAME LANDS IN THE FILE, which is what decides whether it survives.
    ///
    /// `block` is a line of its own, `name: value`, read back by `splitKey`, which never
    /// unquotes anything. `flow` is a `{ }` mapping sitting in a block line's value, read
    /// back by `scalar`, which DOES unquote a key — that is why a name block form cannot
    /// carry is written in flow rather than refused. `nestedFlow` is the same `{ }` one
    /// level deeper, inside a `[ ]` or another `{ }`, and it is stricter than `flow`
    /// because `splitTopLevel` only lets a quote open at the START of a piece: by the time
    /// it reaches a nested key's quote it has already seen the enclosing `{`, so the quote
    /// is inert there and the name's own brackets have to balance on their own.
    enum NamePlacement {
        case block
        case flow
        case nestedFlow
    }

    /// Whether this writer can put `name` in front of a metadata value at `placement` and
    /// have the reader hand back the same name.
    ///
    /// ANSWERED BY DOING IT, not by a list of characters. Two hand-written rules stood here
    /// before and both were wrong in the same direction — they refused names a real file
    /// hands this reader every day (` x` and `#x` and `a, b` through a quoted flow key) and
    /// they waved through `a}b`, which passed the rule, encoded, and then threw
    /// `unbalanced quotes or brackets` on the way back in. A predicate that reasons ABOUT
    /// the parser will keep drifting away from the parser. This one writes the name exactly
    /// as the writer would, reads it back with exactly the reader the file will meet, and
    /// answers with what came out.
    ///
    /// THE READER THROWING IS THE ANSWER, not an error to pass on: a name that makes the
    /// parser refuse the line is a name this writer must not put there. That is the one
    /// place in this file where a caught error is a measurement rather than a swallowed
    /// failure, and it is caught HERE so that `validate` can throw a sentence naming the
    /// name instead of a parser complaint naming a line number the author never wrote.
    static func nameFits(_ name: String, at placement: NamePlacement) -> Bool {
        // A CARRIAGE RETURN IS SETTLED BEFORE THE ORACLE RUNS. `decode` normalises `\r` to
        // `\n` and splits the file into lines before the parser sees a character of it,
        // while `quoteIfNeeded` escapes `\n` and `\t` and leaves `\r` alone — so a name
        // holding one would cut its own line in half in a real file and still read back
        // cleanly here, where nothing splits lines. This is the one hazard the oracle below
        // is structurally blind to, and it is written down rather than left to be found.
        if name.contains("\r") { return false }
        switch placement {
        case .block:
            // ` #` STARTS A COMMENT FOR PyYAML, and so for quackd, even though this reader's
            // block branch keeps it. Writing `a #b: 1` would hand quackd a file it refuses,
            // and this writer's whole claim is that it cannot do that — so the name goes to
            // flow form, quoted, where the `#` is inside a scalar and harmless.
            if name.contains(" #") { return false }
            // SPLIT THE WAY `decode` SPLITS, so a name holding a line break is measured as
            // the two lines it would really become rather than as the one string it is here.
            var reader = Reader(lines: "\(name): 1".components(separatedBy: "\n"),
                                firstLineNumber: 1)
            do {
                guard case .mapping(let read) = try reader.parseDocument(),
                      read.count == 1, read[name] != nil else { return false }
                return true
            } catch {
                return false
            }
        case .flow, .nestedFlow:
            let entry = "{\(quoteIfNeeded(name, inFlow: true)): 1}"
            do {
                let value = try scalar(placement == .nestedFlow ? "[\(entry)]" : entry, line: 1)
                var read = value
                if placement == .nestedFlow {
                    guard case .list(let items) = value, items.count == 1 else { return false }
                    read = items[0]
                }
                guard case .mapping(let mapping) = read,
                      mapping.count == 1, mapping[name] != nil else { return false }
                return true
            } catch {
                return false
            }
        }
    }

    /// Whether every name in `mapping` can be written on a line of its own — the question
    /// `encode` and `blockMapping` both ask before choosing block form over flow.
    static func everyNameFitsBlockForm(_ mapping: [String: DuckValue]) -> Bool {
        mapping.keys.allSatisfy { nameFits($0, at: .block) }
    }

    /// The first metadata name anywhere in `value` that this writer cannot express in ANY
    /// form, or nil when every one of them survives a write and a read.
    ///
    /// The placement bookkeeping MIRRORS the writer's own form choice and has to keep
    /// mirroring it: a non-empty mapping stays in block form while every one of its names
    /// fits there, and otherwise the whole mapping — and everything under it — goes through
    /// `inlineScalar`, which is flow all the way down. Get that backwards and this either
    /// refuses names the writer handles fine or waves through the ones it mangles.
    static func unwritableMetadataName(in value: DuckValue,
                                       at placement: NamePlacement = .block) -> String? {
        switch value {
        case .mapping(let mapping):
            var namePlacement = placement
            if placement == .block, !everyNameFitsBlockForm(mapping) { namePlacement = .flow }
            for name in mapping.keys.sorted() {
                guard nameFits(name, at: namePlacement) else { return name }
                let nested = mapping[name] ?? .null
                // A CHILD OF A BLOCK MAPPING IS STILL A CANDIDATE FOR BLOCK; a child of any
                // flow mapping is already inside braces and can only be nested flow.
                let childPlacement: NamePlacement = namePlacement == .block ? .block : .nestedFlow
                if let bad = unwritableMetadataName(in: nested, at: childPlacement) {
                    return bad
                }
            }
            return nil
        case .list(let items):
            // A LIST WITH A MAPPING IN IT IS ALWAYS WRITTEN BY `inlineScalar`, so anything
            // inside one is nested flow however the list itself got here.
            for item in items {
                if let bad = unwritableMetadataName(in: item, at: .nestedFlow) { return bad }
            }
            return nil
        default:
            return nil
        }
    }

    /// The trait that makes `name` impossible to write down where it sits, as the sentence
    /// an author reads. Computed from the name itself so the refusal names the offending
    /// character rather than a rule — "invalid name" sends somebody hunting through their
    /// own file.
    ///
    /// TWO NAMED BRANCHES AND A FALLBACK, WHICH IS THREE ANSWERS, NOT TWO — see the class
    /// comment's list of what `nameFits` still turns away. The fallback is not a gap: a name
    /// whose brackets balance by count but whose depth returns to zero at a comma (`},{`) is
    /// genuinely unwritable and genuinely has no single offending character to point at, and
    /// saying so beats naming the wrong one. The colon, quote and comma branches that stood
    /// here were all written for a reader that no longer misreads any of them, and a
    /// refusal that keeps explaining itself with a character that is not the problem is
    /// worse than one that says it does not know: `a: }` was told its colon was the trouble
    /// when the trouble was the brace.
    static func whyNameIsNotWritable(_ name: String) -> String {
        if name.contains("\r") { return "it contains a carriage return" }
        if !bracketsClose(name) {
            return "its brackets do not close each other, and a name nested inside a [ ] "
                 + "or a { } has to close its own"
        }
        return "this writer has no form that reads it back unchanged"
    }

    /// Whether the name's own `{`, `[`, `}` and `]` cancel out.
    ///
    /// COUNTED, NOT LOOKED FOR, because counting is what `splitTopLevel` does: it tracks one
    /// depth for both bracket pairs and never inspects which kind closed which, so `a}b{c`
    /// survives a nested flow key and `a, }` does not. A predicate that asked "does this
    /// name contain a brace" would refuse the first and explain the second wrongly.
    private static func bracketsClose(_ name: String) -> Bool {
        var depth = 0
        for character in name {
            if character == "{" || character == "[" { depth += 1 }
            if character == "}" || character == "]" { depth -= 1 }
        }
        return depth == 0
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
            // A FLOW KEY IS QUOTED WHEN IT NEEDS IT, unlike a block key, and the difference
            // is the reader's: the flow branch of `scalar` runs `unquote` on a key, the
            // block reader's `splitKey` never does. So quoting here gets the same name back
            // — `{"a, b": 1}` reads as `a, b` — where quoting a block key would only hand
            // back `"a` and its stray quote.
            return map.isEmpty
                ? "{}"
                : "{" + map.keys.sorted().map {
                        "\(quoteIfNeeded($0, inFlow: true)): \(inlineScalar(map[$0] ?? .null))"
                    }.joined(separator: ", ") + "}"
        }
    }

    /// A whole metadata mapping written in flow form, for the moment `encode` finds a name
    /// that block form cannot carry.
    static func inlineMapping(_ mapping: [String: DuckValue]) -> String {
        inlineScalar(.mapping(mapping))
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
