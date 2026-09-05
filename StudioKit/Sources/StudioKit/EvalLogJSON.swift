import Foundation

/// JSON spelled the way CPython's `json.dumps` spells it, so an evaluation log
/// written on a phone is byte for byte a log inspect-robots wrote itself.
///
/// THERE ARE TWO JSON WRITERS IN THIS PACKAGE AND THEY HAVE OPPOSITE
/// CONTRACTS. `HarnessJSON` exists so a stairs challenge intent re-encodes with
/// its keys in INSERTION order and its numbers in their ORIGINAL source text,
/// because the bench takes `intentHash` over `JSON.stringify` of that object
/// and a reordered key is a different move. This one exists so an evaluation
/// log re-encodes with its keys SORTED and its numbers spelled the way
/// `repr(float)` spells them, because `inspect-robots` writes
/// `json.dump(..., indent=2, sort_keys=True)` and a log that differs from that
/// by one byte is a log whose fidelity nobody can check. Neither writer can do
/// the other's job. Do not merge them: collapsing the two would silently change
/// the hashes of a published dataset.
///
/// WHY BYTES AND NOT "VALID JSON". Any JSON writer produces a file their reader
/// accepts. Only a writer that reproduces their own output exactly can be
/// PROVED right without running Python: `EvalLogFidelityTests` parses a real
/// log written by inspect-robots 0.58.0, re-encodes it through this type, and
/// requires the bytes back. That test needs no network, no venv and no Pi, so
/// it runs on every commit, which is the only kind of gate that survives.
///
/// The six rules, each with a test in `EvalLogJSONTests`:
///
///   1. Two-space indent, `": "` after a key, a comma and a newline between
///      members, `{}` and `[]` for an empty container.
///   2. Keys sorted by UTF-8 bytes, which is Python's code point order. Swift's
///      own `String.<` is a normalising comparison and is exactly wrong here:
///      it puts U+212B before U+0100 and Python puts U+0100 first.
///   3. A double is spelled `"\(value)"`, which agrees with `repr(float)` on
///      every value measured, `1e15` spelled `1000000000000000.0` included.
///   4. `.integer` and `.double` stay apart all the way to the file, so a trial
///      count is `3` and a score of one is `1.0`.
///   5. Strings escape the way `py_encode_basestring_ascii` escapes: the two
///      structural characters, the five short escapes, and every scalar outside
///      0x20 to 0x7e as a lowercase `\uXXXX`, with a surrogate pair above the
///      BMP. A forward slash is NOT escaped.
///   6. No trailing newline.
///
/// A non-finite double is `null`, recursively, the way `json_log._sanitize`
/// does it, because `Infinity` and `NaN` are not JSON and their reader passes
/// `allow_nan=False`.
public indirect enum EvalLogJSON: Equatable, Sendable {

    case null
    case bool(Bool)
    /// A whole number that was written as a whole number. Kept apart from
    /// `.double` because Python does: `total_trials` is `3` and a score of one
    /// is `1.0`, and a writer that collapsed them would break the round trip in
    /// the least visible way there is.
    case integer(Int)
    case double(Double)
    case string(String)
    case array([EvalLogJSON])
    /// Unordered on purpose. The key order in the file is derived by sorting,
    /// so there is nothing here for a caller to get wrong.
    case object([String: EvalLogJSON])

    // MARK: - building one

    /// A double, with a non-finite value turned into `null` HERE rather than at
    /// the file, so a value that cannot be written can never be held either.
    public static func number(_ value: Double) -> EvalLogJSON {
        value.isFinite ? .double(value) : .null
    }

    public static func number(_ value: Int) -> EvalLogJSON { .integer(value) }

    public static func numbers(_ values: [Double]) -> EvalLogJSON {
        .array(values.map { number($0) })
    }

    public static func strings(_ values: [String]) -> EvalLogJSON {
        .array(values.map { .string($0) })
    }

    /// A map of doubles, which is what every scorer block in the log is.
    public static func numbers(_ values: [String: Double]) -> EvalLogJSON {
        .object(values.mapValues { number($0) })
    }

    /// An absent value, which their schema spells `null` rather than by
    /// leaving the key out. Named apart from the cases so a `String?` can never
    /// pick up the `String` case by promotion, which is the kind of overload
    /// that compiles and writes the wrong thing.
    public static func maybe(_ value: String?) -> EvalLogJSON {
        value.map { EvalLogJSON.string($0) } ?? .null
    }

    public static func maybe(_ value: Double?) -> EvalLogJSON {
        value.map { number($0) } ?? .null
    }

    public static func maybe(_ value: Int?) -> EvalLogJSON {
        value.map { EvalLogJSON.integer($0) } ?? .null
    }

    /// The same walk `json_log._sanitize` does, kept as a separate operation so
    /// a tree assembled from `case .double(...)` by hand can still be cleaned.
    public func sanitized() -> EvalLogJSON {
        switch self {
        case .double(let value): return value.isFinite ? self : .null
        case .array(let items): return .array(items.map { $0.sanitized() })
        case .object(let members): return .object(members.mapValues { $0.sanitized() })
        default: return self
        }
    }

    // MARK: - reading one

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// A number as a Double, whichever case carried it. Reading is lenient
    /// where writing is strict: their `max_steps` is an int and their
    /// `duration_s` is a float, and a reader that refused to see `3` as `3.0`
    /// would refuse half of their own logs.
    public var doubleValue: Double? {
        switch self {
        case .integer(let value): return Double(value)
        case .double(let value): return value
        default: return nil
        }
    }

    public var integerValue: Int? {
        if case .integer(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var arrayValue: [EvalLogJSON]? {
        if case .array(let items) = self { return items }
        return nil
    }

    public var objectValue: [String: EvalLogJSON]? {
        if case .object(let members) = self { return members }
        return nil
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    public subscript(key: String) -> EvalLogJSON? {
        guard case .object(let members) = self else { return nil }
        return members[key]
    }

    // MARK: - writing it

    public func encoded() -> Data {
        var out = ""
        write(into: &out, depth: 0)
        return Data(out.utf8)
    }

    /// The text, for a test that wants to read the failure rather than a byte
    /// count.
    public func encodedText() -> String {
        var out = ""
        write(into: &out, depth: 0)
        return out
    }

    private func write(into out: inout String, depth: Int) {
        let pad = String(repeating: " ", count: (depth + 1) * 2)
        let closePad = String(repeating: " ", count: depth * 2)
        switch self {
        case .null: out += "null"
        case .bool(let value): out += value ? "true" : "false"
        case .integer(let value): out += String(value)
        case .double(let value): out += Self.spelled(value)
        case .string(let value): out += Self.escaped(value)
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            out += "[\n"
            for (index, item) in items.enumerated() {
                out += pad
                item.write(into: &out, depth: depth + 1)
                if index < items.count - 1 { out += "," }
                out += "\n"
            }
            out += closePad + "]"
        case .object(let members):
            if members.isEmpty { out += "{}"; return }
            out += "{\n"
            let keys = Self.sortedKeys(of: members)
            for (index, key) in keys.enumerated() {
                out += pad + Self.escaped(key) + ": "
                members[key]!.write(into: &out, depth: depth + 1)
                if index < keys.count - 1 { out += "," }
                out += "\n"
            }
            out += closePad + "}"
        }
    }

    /// PYTHON'S ORDER, WHICH IS NOT SWIFT'S. `sort_keys=True` sorts by Unicode
    /// code point, and UTF-8 preserves code point order byte for byte, so a
    /// lexicographic comparison of the UTF-8 is exactly right. Swift's own
    /// `String.<` normalises first: it holds U+212B and U+00C5 equal and puts
    /// U+212B before U+0100, where Python puts U+0100 first. The corpus in
    /// `EvalLogJSONTests` contains that pair so the wrong comparison cannot
    /// pass.
    static func sortedKeys(of members: [String: EvalLogJSON]) -> [String] {
        members.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    /// `repr(float)` in Swift's clothing.
    ///
    /// MEASURED RATHER THAN ASSUMED. Sixteen values were put through both
    /// languages this session, `1e15`, `-0.0`, `1e-05`, `1e+16`, `1e+21`,
    /// `5e-324` and `1.2345678901234568e+17` among them, and every spelling
    /// agreed. The table is in `EvalLogJSONTests` and it is the gate: a rule
    /// that rests on "we will never write a number like that" is not a gate.
    /// A non-finite value cannot reach here through `number(_:)`, and is
    /// spelled `null` anyway so a hand-built `.double(.nan)` cannot write a
    /// token no JSON parser accepts.
    public static func spelled(_ value: Double) -> String {
        guard value.isFinite else { return "null" }
        return "\(value)"
    }

    /// `py_encode_basestring_ascii`, which is what `ensure_ascii=True` means.
    ///
    /// The rule is `([\\"]|[^ -~])`: escape the backslash, escape the quote,
    /// and escape everything that is not a printable ASCII character. So DEL is
    /// escaped, an accented letter is escaped, and a forward slash is not. Above
    /// the BMP it is two `\u` escapes and one character, because Python writes
    /// the surrogate pair.
    public static func escaped(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                let code = scalar.value
                if code >= 0x20 && code <= 0x7e {
                    out.unicodeScalars.append(scalar)
                } else if code <= 0xFFFF {
                    out += String(format: "\\u%04x", code)
                } else {
                    let offset = code - 0x10000
                    out += String(format: "\\u%04x", 0xD800 + (offset >> 10))
                    out += String(format: "\\u%04x", 0xDC00 + (offset & 0x3FF))
                }
            }
        }
        return out + "\""
    }

    // MARK: - parsing it

    public enum ParseError: Error, Equatable {
        case notUTF8
        case unexpected(String, at: Int)
        case truncated

        public var message: String {
            switch self {
            case .notUTF8: return "That file is not UTF-8 text."
            case .unexpected(let what, let at):
                return "That is not an evaluation log: \(what) at byte \(at)."
            case .truncated: return "That file stops in the middle of the JSON."
            }
        }
    }

    /// Parse a log somebody else wrote.
    ///
    /// It keeps the INTEGER AND FLOAT DISTINCTION the source text carries,
    /// because Python does: a token with no point and no exponent is an `int`
    /// and everything else is a `float`, and a reader that made them all
    /// doubles would re-encode their `80` as `80.0` and lose the round trip.
    public static func parse(_ data: Data) throws -> EvalLogJSON {
        var scanner = Scanner(bytes: [UInt8](data))
        scanner.skipWhitespace()
        let value = try scanner.value()
        scanner.skipWhitespace()
        guard scanner.atEnd else {
            throw ParseError.unexpected("more than one value", at: scanner.index)
        }
        return value
    }

    struct Scanner {
        let bytes: [UInt8]
        var index = 0
        init(bytes: [UInt8]) { self.bytes = bytes }

        var atEnd: Bool { index >= bytes.count }

        mutating func skipWhitespace() {
            while index < bytes.count {
                let byte = bytes[index]
                if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D { index += 1 }
                else { return }
            }
        }

        mutating func value() throws -> EvalLogJSON {
            guard index < bytes.count else { throw ParseError.truncated }
            switch bytes[index] {
            case UInt8(ascii: "{"): return try object()
            case UInt8(ascii: "["): return try array()
            case UInt8(ascii: "\""): return .string(try stringToken())
            case UInt8(ascii: "t"): try expect("true"); return .bool(true)
            case UInt8(ascii: "f"): try expect("false"); return .bool(false)
            case UInt8(ascii: "n"): try expect("null"); return .null
            default: return try number()
            }
        }

        mutating func expect(_ word: String) throws {
            let wanted = [UInt8](word.utf8)
            guard index + wanted.count <= bytes.count,
                  Array(bytes[index..<(index + wanted.count)]) == wanted else {
                throw ParseError.unexpected("expected \(word)", at: index)
            }
            index += wanted.count
        }

        mutating func object() throws -> EvalLogJSON {
            index += 1                                   // past '{'
            var members: [String: EvalLogJSON] = [:]
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
                index += 1
                return .object([:])
            }
            while true {
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else {
                    throw ParseError.unexpected("a key was expected", at: index)
                }
                let key = try stringToken()
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else {
                    throw ParseError.unexpected("a colon was expected", at: index)
                }
                index += 1
                skipWhitespace()
                members[key] = try value()
                skipWhitespace()
                guard index < bytes.count else { throw ParseError.truncated }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
                throw ParseError.unexpected("a comma or a closing brace was expected", at: index)
            }
        }

        mutating func array() throws -> EvalLogJSON {
            index += 1                                   // past '['
            var items: [EvalLogJSON] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
                index += 1
                return .array([])
            }
            while true {
                skipWhitespace()
                items.append(try value())
                skipWhitespace()
                guard index < bytes.count else { throw ParseError.truncated }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
                throw ParseError.unexpected("a comma or a closing bracket was expected", at: index)
            }
        }

        mutating func stringToken() throws -> String {
            index += 1                                   // past '"'
            var scalars = String.UnicodeScalarView()
            var utf8: [UInt8] = []
            func flush() throws {
                guard !utf8.isEmpty else { return }
                guard let piece = String(bytes: utf8, encoding: .utf8) else { throw ParseError.notUTF8 }
                scalars.append(contentsOf: piece.unicodeScalars)
                utf8.removeAll(keepingCapacity: true)
            }
            while index < bytes.count {
                let byte = bytes[index]
                if byte == UInt8(ascii: "\"") {
                    index += 1
                    try flush()
                    return String(scalars)
                }
                if byte == UInt8(ascii: "\\") {
                    try flush()
                    index += 1
                    guard index < bytes.count else { throw ParseError.truncated }
                    switch bytes[index] {
                    case UInt8(ascii: "\""): scalars.append("\""); index += 1
                    case UInt8(ascii: "\\"): scalars.append("\\"); index += 1
                    case UInt8(ascii: "/"): scalars.append("/"); index += 1
                    case UInt8(ascii: "b"): scalars.append("\u{08}"); index += 1
                    case UInt8(ascii: "f"): scalars.append("\u{0C}"); index += 1
                    case UInt8(ascii: "n"): scalars.append("\n"); index += 1
                    case UInt8(ascii: "r"): scalars.append("\r"); index += 1
                    case UInt8(ascii: "t"): scalars.append("\t"); index += 1
                    case UInt8(ascii: "u"):
                        index += 1
                        let first = try hex4()
                        if first >= 0xD800, first <= 0xDBFF,
                           index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"),
                           bytes[index + 1] == UInt8(ascii: "u") {
                            index += 2
                            let second = try hex4()
                            let combined = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
                            guard let scalar = Unicode.Scalar(UInt32(combined)) else {
                                throw ParseError.unexpected("a bad \\u escape", at: index)
                            }
                            scalars.append(scalar)
                        } else {
                            guard let scalar = Unicode.Scalar(UInt32(first)) else {
                                throw ParseError.unexpected("a bad \\u escape", at: index)
                            }
                            scalars.append(scalar)
                        }
                    default: throw ParseError.unexpected("an unknown escape", at: index)
                    }
                    continue
                }
                utf8.append(byte)
                index += 1
            }
            throw ParseError.truncated
        }

        mutating func hex4() throws -> Int {
            guard index + 4 <= bytes.count else { throw ParseError.truncated }
            var value = 0
            for _ in 0..<4 {
                let byte = bytes[index]
                let digit: Int
                switch byte {
                case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = Int(byte - UInt8(ascii: "0"))
                case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = Int(byte - UInt8(ascii: "a")) + 10
                case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = Int(byte - UInt8(ascii: "A")) + 10
                default: throw ParseError.unexpected("a bad \\u escape", at: index)
                }
                value = value * 16 + digit
                index += 1
            }
            return value
        }

        mutating func number() throws -> EvalLogJSON {
            let start = index
            var isDouble = false
            if index < bytes.count, bytes[index] == UInt8(ascii: "-") { index += 1 }
            func digits() {
                while index < bytes.count,
                      bytes[index] >= UInt8(ascii: "0"), bytes[index] <= UInt8(ascii: "9") {
                    index += 1
                }
            }
            digits()
            if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
                isDouble = true
                index += 1
                digits()
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
                isDouble = true
                index += 1
                if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
                    index += 1
                }
                digits()
            }
            guard index > start,
                  let literal = String(bytes: bytes[start..<index], encoding: .utf8) else {
                throw ParseError.unexpected("a number was expected", at: start)
            }
            if !isDouble, let whole = Int(literal) { return .integer(whole) }
            guard let value = Double(literal) else {
                throw ParseError.unexpected("a number was expected", at: start)
            }
            return .double(value)
        }
    }
}
