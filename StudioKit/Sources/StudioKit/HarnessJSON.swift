import Foundation

/// JSON that survives a round trip, ORDER AND DIGITS INCLUDED.
///
/// WHY FOUNDATION'S JSON IS THE WRONG TOOL FOR EXACTLY THIS FILE. A stairs
/// challenge entry is identified by `intentHash` — the harness's sha256 over
/// `JSON.stringify` of a normalised copy of the intent (`climb/robust.mjs`
/// line 587). `JSON.stringify` writes an object's keys in insertion order, and
/// the normalised copy carries `keyframes` through UNTOUCHED, so the order of
/// the keys INSIDE each keyframe — `{"t": …, "pose": […]}` — is part of the
/// hash. `JSONSerialization` and `JSONDecoder` both land a JSON object in a
/// Swift `Dictionary`, which has no order at all: read a move with either of
/// them and write it back out and the keyframes come back in whatever order
/// hashing gives you. The bench then scores a DIFFERENT hash from the one on
/// the leaderboard, and every number the app shows is filed against a move
/// nobody can find.
///
/// The second half is the digits. `2.1153` re-encoded through a `Double` is
/// still `2.1153`, but nothing in Foundation promises that, and a blend
/// parameter that comes back `2.1152999999999999` is a different move by the
/// same argument. So every scalar this parser reads keeps THE EXACT SOURCE
/// TEXT it was written with, and the writer emits that text rather than
/// reformatting a value. An untouched file therefore re-encodes byte for byte,
/// which `StairsMoveTests` asserts over all nineteen bundled intents.
///
/// This is not a general-purpose JSON library and must not become one. It
/// exists so one published dataset can travel through this app and come out
/// the other side still being itself.
public indirect enum HarnessJSON: Equatable, Sendable {

    case null
    case bool(Bool)
    /// The value, and the characters it was written with. A number BUILT here
    /// rather than parsed carries a literal formatted by `Self.literal(for:)`,
    /// which prints the way JavaScript's `Number.prototype.toString` does, so
    /// a keyframe time this app writes hashes the same on the bench as one the
    /// harness wrote.
    case number(Double, literal: String)
    /// The decoded value, and the source text INCLUDING its quotes when this
    /// came off a file. Kept because JSON has more than one spelling of the
    /// same string — `"é"` and `"é"` are equal and are not the same
    /// bytes — and re-spelling somebody's dataset is not this app's business.
    case string(String, literal: String?)
    case array([HarnessJSON])
    case object([Member])

    /// One key and its value. A struct rather than a tuple so the enum is
    /// `Equatable` and `Sendable` without hand-writing either.
    public struct Member: Equatable, Sendable {
        public let key: String
        public let keyLiteral: String?
        public var value: HarnessJSON
        public init(key: String, keyLiteral: String? = nil, value: HarnessJSON) {
            self.key = key; self.keyLiteral = keyLiteral; self.value = value
        }
    }

    // MARK: - building one by hand

    public static func number(_ value: Double) -> HarnessJSON {
        .number(value, literal: literal(for: value))
    }

    public static func string(_ value: String) -> HarnessJSON {
        .string(value, literal: nil)
    }

    /// JavaScript's number spelling, because the hash is taken on the other
    /// side of the wire by `JSON.stringify`.
    ///
    /// The two places Swift and JavaScript disagree, both handled: an integral
    /// double prints `1.0` in Swift and `1` in JavaScript, and an exponent
    /// prints `1e-07` in Swift and `1e-7` in JavaScript.
    public static func literal(for value: Double) -> String {
        guard value.isFinite else { return "null" }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        var text = "\(value)"
        if let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            let mantissa = String(text[text.startIndex..<e])
            var exponent = String(text[text.index(after: e)...])
            var sign = ""
            if exponent.hasPrefix("-") || exponent.hasPrefix("+") {
                sign = exponent.hasPrefix("-") ? "-" : ""
                exponent.removeFirst()
            }
            while exponent.count > 1 && exponent.hasPrefix("0") { exponent.removeFirst() }
            text = mantissa + "e" + sign + exponent
        }
        return text
    }

    // MARK: - reading it

    public var doubleValue: Double? {
        if case .number(let value, _) = self { return value }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value, _) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var arrayValue: [HarnessJSON]? {
        if case .array(let items) = self { return items }
        return nil
    }

    public var members: [Member]? {
        if case .object(let members) = self { return members }
        return nil
    }

    public subscript(key: String) -> HarnessJSON? {
        guard case .object(let members) = self else { return nil }
        return members.first { $0.key == key }?.value
    }

    /// Replace a member's value, keeping its position, or append it at the end
    /// if there is none. POSITION IS LOAD-BEARING: see the note at the top.
    public func setting(_ key: String, to value: HarnessJSON) -> HarnessJSON {
        guard case .object(var members) = self else { return self }
        if let index = members.firstIndex(where: { $0.key == key }) {
            members[index].value = value
        } else {
            members.append(Member(key: key, value: value))
        }
        return .object(members)
    }

    // MARK: - writing it

    public enum WriteStyle: Equatable, Sendable {
        /// Two-space indent, exactly `JSON.stringify(value, null, 2)` — the
        /// shape every file in `duck-sounds/challenge/intents` is written in.
        case pretty
        /// No whitespace at all, for a request body.
        case compact
    }

    public func encoded(_ style: WriteStyle = .pretty) -> Data {
        var out = ""
        write(into: &out, style: style, depth: 0)
        return Data(out.utf8)
    }

    private func write(into out: inout String, style: WriteStyle, depth: Int) {
        let pretty = style == .pretty
        let pad = pretty ? String(repeating: " ", count: (depth + 1) * 2) : ""
        let closePad = pretty ? String(repeating: " ", count: depth * 2) : ""
        let newline = pretty ? "\n" : ""
        switch self {
        case .null: out += "null"
        case .bool(let value): out += value ? "true" : "false"
        case .number(_, let literal): out += literal
        case .string(let value, let literal): out += literal ?? Self.quote(value)
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            out += "[" + newline
            for (index, item) in items.enumerated() {
                out += pad
                item.write(into: &out, style: style, depth: depth + 1)
                if index < items.count - 1 { out += "," }
                out += newline
            }
            out += closePad + "]"
        case .object(let members):
            if members.isEmpty { out += "{}"; return }
            out += "{" + newline
            for (index, member) in members.enumerated() {
                out += pad + (member.keyLiteral ?? Self.quote(member.key)) + ":"
                if pretty { out += " " }
                member.value.write(into: &out, style: style, depth: depth + 1)
                if index < members.count - 1 { out += "," }
                out += newline
            }
            out += closePad + "}"
        }
    }

    /// `JSON.stringify`'s escaping rule: the two structural characters, the
    /// control range, and NOTHING ELSE. Non-ASCII goes out as itself, which is
    /// what the challenge files hold (an em dash in a family name) and what
    /// the harness reads back.
    public static func quote(_ value: String) -> String {
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
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
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
                return "That is not the harness's JSON: \(what) at byte \(at)."
            case .truncated: return "That file stops in the middle of the JSON."
            }
        }
    }

    public static func parse(_ data: Data) throws -> HarnessJSON {
        var scanner = Scanner(bytes: [UInt8](data))
        scanner.skipWhitespace()
        let value = try scanner.value()
        scanner.skipWhitespace()
        guard scanner.atEnd else {
            throw ParseError.unexpected("more than one value", at: scanner.index)
        }
        return value
    }

    /// A byte-at-a-time recursive descent. Small on purpose: everything it
    /// gives up (streaming, error recovery, numbers wider than a `Double`)
    /// belongs to a library this app does not need.
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

        mutating func value() throws -> HarnessJSON {
            guard index < bytes.count else { throw ParseError.truncated }
            switch bytes[index] {
            case UInt8(ascii: "{"): return try object()
            case UInt8(ascii: "["): return try array()
            case UInt8(ascii: "\""):
                let (text, literal) = try stringToken()
                return .string(text, literal: literal)
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

        mutating func object() throws -> HarnessJSON {
            index += 1                                   // past '{'
            var members: [Member] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object([]) }
            while true {
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else {
                    throw ParseError.unexpected("a key was expected", at: index)
                }
                let (key, keyLiteral) = try stringToken()
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else {
                    throw ParseError.unexpected("a colon was expected", at: index)
                }
                index += 1
                skipWhitespace()
                members.append(Member(key: key, keyLiteral: keyLiteral, value: try value()))
                skipWhitespace()
                guard index < bytes.count else { throw ParseError.truncated }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
                throw ParseError.unexpected("a comma or a closing brace was expected", at: index)
            }
        }

        mutating func array() throws -> HarnessJSON {
            index += 1                                   // past '['
            var items: [HarnessJSON] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array([]) }
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

        /// The decoded text and the exact source slice, quotes included.
        mutating func stringToken() throws -> (String, String) {
            let start = index
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
                    guard let literal = String(bytes: bytes[start..<index], encoding: .utf8) else {
                        throw ParseError.notUTF8
                    }
                    return (String(scalars), literal)
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
                        // A surrogate pair is two escapes and one character.
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

        mutating func number() throws -> HarnessJSON {
            let start = index
            if index < bytes.count, bytes[index] == UInt8(ascii: "-") { index += 1 }
            func digits() {
                while index < bytes.count,
                      bytes[index] >= UInt8(ascii: "0"), bytes[index] <= UInt8(ascii: "9") {
                    index += 1
                }
            }
            digits()
            if index < bytes.count, bytes[index] == UInt8(ascii: ".") { index += 1; digits() }
            if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
                index += 1
                if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
                    index += 1
                }
                digits()
            }
            guard index > start,
                  let literal = String(bytes: bytes[start..<index], encoding: .utf8),
                  let value = Double(literal) else {
                throw ParseError.unexpected("a number was expected", at: start)
            }
            return .number(value, literal: literal)
        }
    }
}
